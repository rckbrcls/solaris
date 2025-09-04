import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FluidGradient
import ImageIO

// Exporta UIImage como HEIC (qualidade máxima), se suportado
import MobileCoreServices
import AVFoundation

func exportUIImageAsHEIC(_ image: UIImage) -> Data? {
    guard let cgImage = image.cgImage else { return nil }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, AVFileType.heic as CFString, 1, nil) else { return nil }
    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
    CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

struct ContentView: View {
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager
    // HUD de carregamento unificado
    @State private var isBusy: Bool = false
    @State private var busyTitle: String = ""
    @State private var showSettings: Bool = false
    @State private var isImportFlowActive: Bool = false
    struct PhotoItem: Identifiable {
        let id: String
        var record: PhotoRecord
        var image: UIImage // thumbnail
    }
    @State private var records: [PhotoRecord] = []
    @State private var photos: [PhotoItem] = []
    @State private var showCamera = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedPhotoForEditor: UIImage? = nil
    @State private var selectedPhotoIndex: Int? = nil
    @State private var isSelectionActive: Bool = false
    @State private var didInitialLoad: Bool = false
    @State private var importWorkItem: DispatchWorkItem? = nil

    @Namespace private var ns

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    Image(colorSchemeManager.currentColorScheme == .dark ? "logo" : "logo-light")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 50)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    PhotosScrollView(
                        photos: $photos,
                        selectedItems: $selectedItems,
                        ns: ns,
                        onPhotoSelected: { index in
                            openEditor(for: index)
                        },
                        onPhotosChanged: {
                            // Manifest salvo pelo serviço após operações
                        },
                        onDelete: { indices in
                            deletePhotos(at: indices)
                        },
                        onSelectionChanged: { active in
                            isSelectionActive = active
                        },
                        getImage: { $0.image }
                    )
                }

                if !isSelectionActive {
                    CameraButtonView(ns: ns) {
                        showCamera = true
                    }
                }

                LoadingOverlay(isVisible: $isBusy, title: busyTitle)
            }
            .onChange(of: selectedItems) { _, newItems in
                // Debounce para capturar a seleção final do PhotosPicker (vários updates sequenciais)
                importWorkItem?.cancel()
                guard !newItems.isEmpty else { return }
                let snapshot = newItems
                let work = DispatchWorkItem {
                    if isImportFlowActive { return }
                    isImportFlowActive = true
                    processImport(items: snapshot, rawHandling: .original)
                }
                importWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            }
            .onAppear {
                guard !didInitialLoad else { return }
                busyTitle = "Carregando fotos..."
                isBusy = true
                DispatchQueue.global(qos: .userInitiated).async {
                    loadPhotos()
                    DispatchQueue.main.async {
                        isBusy = false
                        didInitialLoad = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                PhotoCaptureView(onPhotoCaptured: { photo in
                    busyTitle = "Salvando foto..."
                    isBusy = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        let lib = PhotoLibrary.shared
                        lib.ensureDirs()
                        let fixed = photo.fixOrientation()
                        // Copia original da câmera (preferir HEIC): gera dados e salva como original
                        var data: Data? = nil
                        var ext = "heic"
                        if let heic = exportUIImageAsHEIC(fixed) { data = heic; ext = "heic" }
                        else if let jpg = fixed.jpegData(compressionQuality: 1.0) { data = jpg; ext = "jpg" }
                        else if let png = fixed.pngData() { data = png; ext = "png" }
                        guard let data else { DispatchQueue.main.async { isBusy = false }; return }
                        let id = UUID().uuidString
                        let origURL = lib.originalsDir().appendingPathComponent("\(id).\(ext)")
                        try? data.write(to: origURL)
                        // Thumb
                        var thumbURL = lib.thumbsDir().appendingPathComponent("\(id).jpg")
                        if let thumbImg = fixed.resizeToFit(maxSize: 512), let (tdata, text) = encodeThumbnailImage(thumbImg) {
                            thumbURL = lib.thumbsDir().appendingPathComponent("\(id).\(text)")
                            try? tdata.write(to: thumbURL)
                        }
                        // Atualiza manifest e UI
                        let rec = PhotoRecord(id: id, originalURL: origURL, thumbURL: thumbURL, editedURL: nil, editState: nil, createdAt: Date())
                        records.append(rec)
                        try? lib.saveManifest(PhotoManifest(items: records))
                        let uiThumb = UIImage(contentsOfFile: thumbURL.path) ?? fixed
                        ImageCache.shared.set(uiThumb, forKey: "thumb_\(id)")
                        DispatchQueue.main.async {
                            photos.append(PhotoItem(id: id, record: rec, image: uiThumb))
                            isBusy = false
                        }
                    }
                })
            }
            .navigationDestination(isPresented: Binding<Bool>(
                get: { selectedPhotoForEditor != nil },
                set: { if !$0 { selectedPhotoForEditor = nil; selectedPhotoIndex = nil } }
            )) {
                if let idx = selectedPhotoIndex, photos.indices.contains(idx) {
                    let item = photos[idx]
                    let rec = item.record
                    let initialEditState = rec.editState
                    let baseURL = rec.editedURL ?? rec.originalURL
                    // Usa a imagem de preview que foi preparada ao tocar
                    let previewImage = selectedPhotoForEditor ?? item.image
                    PhotoEditorView(photo: previewImage, originalURL: baseURL, namespace: ns, matchedID: "", initialEditState: initialEditState) { finalImage, editState, didSave in
                        if didSave, let finalImage, let editState {
                            busyTitle = "Salvando edição..."
                            isBusy = true
                            DispatchQueue.global(qos: .userInitiated).async {
                                let lib = PhotoLibrary.shared
                                lib.ensureDirs()
                                // Encode edição
                                var dataOut: Data? = nil
                                var ext = "heic"
                                if let heic = exportUIImageAsHEIC(finalImage) { dataOut = heic; ext = "heic" }
                                else if let jpg = finalImage.jpegData(compressionQuality: 1.0) { dataOut = jpg; ext = "jpg" }
                                else if let png = finalImage.pngData() { dataOut = png; ext = "png" }
                                guard let dataOut else { DispatchQueue.main.async { isBusy = false }; return }
                                let editURL = lib.editsDir().appendingPathComponent("\(rec.id).\(ext)")
                                try? dataOut.write(to: editURL)
                                // Atualiza thumb
                                var thumbURL = lib.thumbsDir().appendingPathComponent("\(rec.id).jpg")
                                if let thumbImg = finalImage.resizeToFit(maxSize: 512), let (tdata, text) = encodeThumbnailImage(thumbImg) {
                                    thumbURL = lib.thumbsDir().appendingPathComponent("\(rec.id).\(text)")
                                    try? tdata.write(to: thumbURL)
                                }
                                // Atualiza manifest em memória e disco
                                var updated = rec
                                updated.editedURL = editURL
                                updated.thumbURL = thumbURL
                                updated.editState = editState
                                if let pos = records.firstIndex(where: { $0.id == updated.id }) {
                                    records[pos] = updated
                                }
                                try? lib.saveManifest(PhotoManifest(items: records))
                                DispatchQueue.main.async {
                                    let newThumb = UIImage(contentsOfFile: thumbURL.path) ?? finalImage
                                    ImageCache.shared.set(newThumb, forKey: "thumb_\(updated.id)")
                                    photos[idx] = PhotoItem(id: updated.id, record: updated, image: newThumb)
                                    isBusy = false
                                }
                            }
                        }
                        selectedPhotoForEditor = nil
                        selectedPhotoIndex = nil
                    }
                    .navigationBarBackButtonHidden(true)
                }
            }
        }
        .observeColorScheme()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(AppSettings.shared)
        }
    }

    func navigateToPhotoEditor(photo: UIImage) {
        // Log image info before editing
        if let cgImage = photo.cgImage {
            print("[navigateToPhotoEditor] size: \(photo.size), alphaInfo: \(cgImage.alphaInfo), bitsPerPixel: \(cgImage.bitsPerPixel)")
        } else {
            print("[navigateToPhotoEditor] No CGImage found!")
        }
        
        // Corrige a orientação antes de qualquer outro processamento
        let orientationFixedPhoto = photo.fixOrientation()
        
        // Always ensure the image is MetalPetal-safe before editing
        if let safePhoto = orientationFixedPhoto.withAlpha() {
            if let cgImage = safePhoto.cgImage {
                print("[navigateToPhotoEditor] SAFE size: \(safePhoto.size), alphaInfo: \(cgImage.alphaInfo), bitsPerPixel: \(cgImage.bitsPerPixel)")
            }
            selectedPhotoForEditor = safePhoto
        } else {
            print("[ContentView] Failed to prepare image for editor (withAlpha failed)")
            // Optionally show an alert here
        }
    }

    func savePhotos() {
        // Salva manifest (registros) em background
        let snapshot = self.records
        DispatchQueue.global(qos: .utility).async {
            try? PhotoLibrary.shared.saveManifest(PhotoManifest(items: snapshot))
        }
    }

    func loadPhotos() {
        let lib = PhotoLibrary.shared
        let manifest = lib.loadManifest()
        records = manifest.items
        photos = manifest.items.map { rec in
            if let cached = ImageCache.shared.image(forKey: "thumb_\(rec.id)") {
                return PhotoItem(id: rec.id, record: rec, image: cached)
            }
            let img: UIImage
            if let ui = UIImage(contentsOfFile: rec.thumbURL.path) {
                img = ui
            } else if let data = try? Data(contentsOf: rec.thumbURL), let ui = UIImage(data: data) {
                img = ui
            } else {
                img = UIImage()
            }
            ImageCache.shared.set(img, forKey: "thumb_\(rec.id)")
            return PhotoItem(id: rec.id, record: rec, image: img)
        }
    }

    func deletePhotos(at indices: [Int]) {
        let lib = PhotoLibrary.shared
        let sorted = indices.sorted(by: >)
        var idsToDelete: [String] = []
        for i in sorted {
            guard photos.indices.contains(i) else { continue }
            let rec = photos[i].record
            PhotoLibrary.shared.deleteFiles(for: rec)
            idsToDelete.append(rec.id)
            photos.remove(at: i)
            ImageCache.shared.remove("thumb_\(rec.id)")
        }
        records.removeAll { idsToDelete.contains($0.id) }
        try? lib.saveManifest(PhotoManifest(items: records))
    }

    // MARK: - Editor navigation helpers
    func openEditor(for index: Int) {
        guard photos.indices.contains(index) else { return }
        selectedPhotoIndex = index
        let rec = photos[index].record
        let baseURL = rec.editedURL ?? rec.originalURL
        busyTitle = "Abrindo..."
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let data = (try? Data(contentsOf: baseURL)) ?? Data()
            let maxPixel = Int(PhotoEditorHelper.suggestedPreviewMaxPoints(doubleTapZoomScale: 3.0) * UIScreen.main.scale)
            let image = loadUIImageThumbnail(from: data, maxPixel: maxPixel) ?? photos[index].image
            DispatchQueue.main.async {
                self.navigateToPhotoEditor(photo: image)
                self.isBusy = false
            }
        }
    }

    // MARK: - Import com política escolhida
    func processImport(items: [PhotosPickerItem], rawHandling: RawHandlingChoice) {
        busyTitle = "Importando fotos..."
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let lib = PhotoLibrary.shared
            lib.ensureDirs()
            let group = DispatchGroup()
            let semaphore = DispatchSemaphore(value: 3)
            for item in items {
                group.enter()
                Task {
                    semaphore.wait()
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        autoreleasepool {
                            let (isRaw, uti) = detectImageRawInfo(data: data)
                            let id = UUID().uuidString
                            if isRaw && rawHandling == .original {
                                let ext = rawFileExtension(from: uti) ?? "raw"
                                let origURL = lib.originalsDir().appendingPathComponent("\(id).\(ext)")
                                try? data.write(to: origURL)
                                var thumbURL = lib.thumbsDir().appendingPathComponent("\(id).jpg")
                                if let timg = loadUIImageThumbnail(from: data, maxPixel: 512), let (tdata, text) = encodeThumbnailImage(timg) {
                                    thumbURL = lib.thumbsDir().appendingPathComponent("\(id).\(text)")
                                    try? tdata.write(to: thumbURL)
                                }
                                let rec = PhotoRecord(id: id, originalURL: origURL, thumbURL: thumbURL, editedURL: nil, editState: nil, createdAt: Date())
                                records.append(rec)
                                let uiThumb = UIImage(contentsOfFile: thumbURL.path) ?? UIImage()
                                ImageCache.shared.set(uiThumb, forKey: "thumb_\(id)")
                                DispatchQueue.main.async { photos.append(PhotoItem(id: id, record: rec, image: uiThumb)) }
                            } else {
                                // Não-RAW: manter qualidade original, copiar dados e gerar thumb
                                let ext = detectImageExtension(data: data)
                                let origURL = lib.originalsDir().appendingPathComponent("\(id).\(ext)")
                                try? data.write(to: origURL)
                                var thumbURL = lib.thumbsDir().appendingPathComponent("\(id).jpg")
                                if let timg = loadUIImageThumbnail(from: data, maxPixel: 512), let (tdata, text) = encodeThumbnailImage(timg) {
                                    thumbURL = lib.thumbsDir().appendingPathComponent("\(id).\(text)")
                                    try? tdata.write(to: thumbURL)
                                }
                                let rec = PhotoRecord(id: id, originalURL: origURL, thumbURL: thumbURL, editedURL: nil, editState: nil, createdAt: Date())
                                records.append(rec)
                                let uiThumb = UIImage(contentsOfFile: thumbURL.path) ?? UIImage()
                                ImageCache.shared.set(uiThumb, forKey: "thumb_\(id)")
                                DispatchQueue.main.async { photos.append(PhotoItem(id: id, record: rec, image: uiThumb)) }
                            }
                        }
                    }
                    semaphore.signal()
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                try? lib.saveManifest(PhotoManifest(items: records))
                selectedItems.removeAll()
                // fluxo de importação finalizado
                isBusy = false
                isImportFlowActive = false
            }
        }
    }
}

// MARK: - Carregamento de imagem com máxima qualidade
func loadUIImageFullQuality(from data: Data) -> UIImage? {
    let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, srcOptions) else {
        return UIImage(data: data)
    }

    // Coleta metadados para decisão de downsampling
    let propertiesOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, propertiesOptions) as? [CFString: Any]
    let pixelWidth = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let pixelHeight = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    let exifOrientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
    let typeId = CGImageSourceGetType(source)

    // Heurística: identificar RAW
    let isProbablyRAW: Bool = {
        guard let typeId = typeId else { return false }
        let uti = typeId as String
        // Checagens comuns de RAW
        let rawUTIs = [
            "public.camera-raw-image",
            "com.adobe.raw-image",
            "com.canon.cr2-raw-image", "com.canon.cr3-raw-image",
            "com.nikon.nrw-raw-image", "com.nikon.nef-raw-image",
            "com.sony.arw-raw-image", "com.panasonic.rw2-raw-image",
            "com.apple.raw-image", "com.fuji.raw-image", "com.olympus.orf-raw-image",
            "com.adobe.dng"
        ]
        return rawUTIs.contains(uti)
    }()

    let maxSide = max(pixelWidth, pixelHeight)
    // Consulta preferências do app
    let settings = AppSettings.shared
    let defaultHandling = settings.rawHandlingDefault
    let cap = isProbablyRAW ? settings.maxRawLongestSide : settings.maxNonRawLongestSide
    let effectiveHandling: RawHandlingChoice = (defaultHandling == .ask) ? .optimized : defaultHandling
    // Manter qualidade SEMPRE: não fazer downsample aqui
    let shouldDownsample: Bool = false

    let scale: CGFloat = UIScreen.main.scale
    if shouldDownsample {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: cap,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldAllowFloat: false
        ]
        if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) {
            // Já vem transformado (orientação correta). Evita passagens extras de draw.
            return UIImage(cgImage: cgThumb, scale: scale, orientation: .up)
        }
        // Fallback: tenta caminho normal se thumbnail falhar
    }

    // Caminho padrão (não gigante): cria CGImage com orientação original e aplica depois
    let createOpts: [CFString: Any] = [
        kCGImageSourceShouldAllowFloat: true,
        kCGImageSourceShouldCacheImmediately: false
    ]
    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, createOpts as CFDictionary) else {
        return UIImage(data: data)
    }
    let image = UIImage(cgImage: cgImage, scale: scale, orientation: UIImage.Orientation(exifOrientation: exifOrientation))
    return image.fixOrientation()
}

// Extensão para converter EXIF para UIImage.Orientation
extension UIImage.Orientation {
    init(exifOrientation: UInt32) {
        switch exifOrientation {
        case 1: self = .up
        case 2: self = .upMirrored
        case 3: self = .down
        case 4: self = .downMirrored
        case 5: self = .leftMirrored
        case 6: self = .right
        case 7: self = .rightMirrored
        case 8: self = .left
        default: self = .up
        }
    }
}

// MARK: - Helpers para formato original
func detectImageExtension(data: Data) -> String {
    if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
    if data.starts(with: [0x00, 0x00, 0x00, 0x18]) || data.starts(with: [0x00, 0x00, 0x00, 0x1C]) { return "heic" }
    return "img"
}

func getPhotoStorageDir() -> URL { PhotoLibrary.shared.storageRoot() }

#Preview {
    ContentView()
}

// MARK: - Helpers de importação e thumbnails
func detectImageRawInfo(data: Data) -> (Bool, String?) {
    let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, srcOptions) else { return (false, nil) }
    guard let typeId = CGImageSourceGetType(source) else { return (false, nil) }
    let uti = typeId as String
    let rawUTIs: Set<String> = [
        "public.camera-raw-image",
        "com.adobe.raw-image",
        "com.canon.cr2-raw-image", "com.canon.cr3-raw-image",
        "com.nikon.nrw-raw-image", "com.nikon.nef-raw-image",
        "com.sony.arw-raw-image", "com.panasonic.rw2-raw-image",
        "com.apple.raw-image", "com.fuji.raw-image", "com.olympus.orf-raw-image",
        "com.adobe.dng"
    ]
    return (rawUTIs.contains(uti), uti)
}

func rawFileExtension(from uti: String?) -> String? {
    guard let uti else { return nil }
    switch uti {
    case "com.adobe.dng": return "dng"
    case "com.canon.cr2-raw-image": return "cr2"
    case "com.canon.cr3-raw-image": return "cr3"
    case "com.nikon.nrw-raw-image": return "nrw"
    case "com.nikon.nef-raw-image": return "nef"
    case "com.sony.arw-raw-image": return "arw"
    case "com.panasonic.rw2-raw-image": return "rw2"
    case "com.olympus.orf-raw-image": return "orf"
    case "public.camera-raw-image", "com.adobe.raw-image", "com.apple.raw-image", "com.fuji.raw-image": return "raw"
    default: return nil
    }
}

func loadUIImageThumbnail(from data: Data, maxPixel: Int) -> UIImage? {
    let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, srcOptions) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceShouldCacheImmediately: false
    ]
    if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) {
        return UIImage(cgImage: cgThumb, scale: UIScreen.main.scale, orientation: .up)
    }
    return nil
}

func loadUIImageWithHandling(from data: Data, handling: RawHandlingChoice) -> UIImage? {
    let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, srcOptions) else { return UIImage(data: data) }
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any]
    let pixelWidth = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let pixelHeight = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    let exifOrientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
    let typeId = CGImageSourceGetType(source)
    let isRaw: Bool = {
        guard let typeId = typeId else { return false }
        let uti = typeId as String
        let rawUTIs: Set<String> = [
            "public.camera-raw-image",
            "com.adobe.raw-image",
            "com.canon.cr2-raw-image", "com.canon.cr3-raw-image",
            "com.nikon.nrw-raw-image", "com.nikon.nef-raw-image",
            "com.sony.arw-raw-image", "com.panasonic.rw2-raw-image",
            "com.apple.raw-image", "com.fuji.raw-image", "com.olympus.orf-raw-image",
            "com.adobe.dng"
        ]
        return rawUTIs.contains(uti)
    }()
    let settings = AppSettings.shared
    let cap = isRaw ? settings.maxRawLongestSide : settings.maxNonRawLongestSide
    let scale: CGFloat = UIScreen.main.scale
    let maxSide = max(pixelWidth, pixelHeight)
    let shouldDownsample: Bool = {
        switch handling {
        case .optimized: return maxSide > cap
        case .original: return false
        case .ask: return maxSide > cap // fallback seguro
        }
    }()
    if shouldDownsample {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: cap,
            kCGImageSourceShouldCacheImmediately: false
        ]
        if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) {
            return UIImage(cgImage: cgThumb, scale: scale, orientation: .up)
        }
    }
    let createOpts: [CFString: Any] = [
        kCGImageSourceShouldAllowFloat: true,
        kCGImageSourceShouldCacheImmediately: false
    ]
    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, createOpts as CFDictionary) else { return UIImage(data: data) }
    let image = UIImage(cgImage: cgImage, scale: scale, orientation: UIImage.Orientation(exifOrientation: exifOrientation))
    return image.fixOrientation()
}

func encodeUIImageBestEffort(_ image: UIImage) -> (Data, String) {
    if let heic = exportUIImageAsHEIC(image) { return (heic, "heic") }
    if let jpg = image.jpegData(compressionQuality: 1.0) { return (jpg, "jpg") }
    if let png = image.pngData() { return (png, "png") }
    // Fallback muito raro
    return (Data(), "img")
}

// MARK: - Thumbnail encode helper
func encodeThumbnailImage(_ image: UIImage) -> (Data, String)? {
    if let heic = exportUIImageAsHEIC(image) { return (heic, "heic") }
    if let jpg = image.jpegData(compressionQuality: 0.9) { return (jpg, "jpg") }
    return nil
}

// MARK: - Image metadata helper
func imageDimensions(at url: URL) -> (Int, Int, Bool) {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return (0, 0, false) }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any]
    let w = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let h = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    let typeId = CGImageSourceGetType(src)
    let isRaw: Bool = {
        guard let typeId = typeId else { return false }
        let uti = typeId as String
        let rawUTIs: Set<String> = [
            "public.camera-raw-image",
            "com.adobe.raw-image",
            "com.canon.cr2-raw-image", "com.canon.cr3-raw-image",
            "com.nikon.nrw-raw-image", "com.nikon.nef-raw-image",
            "com.sony.arw-raw-image", "com.panasonic.rw2-raw-image",
            "com.apple.raw-image", "com.fuji.raw-image", "com.olympus.orf-raw-image",
            "com.adobe.dng"
        ]
        return rawUTIs.contains(uti)
    }()
    return (w, h, isRaw)
}
