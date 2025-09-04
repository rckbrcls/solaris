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
    @State private var showRawChoiceDialog: Bool = false
    @State private var batchRawHandling: RawHandlingChoice? = nil
    @State private var pendingImportItems: [PhotosPickerItem] = []
    struct StoredPhoto: Codable {
        let url: URL
        let data: Data
        let image: UIImage
        let originalData: Data
        var editState: PhotoEditState? = nil

        enum CodingKeys: String, CodingKey {
            case url, data, editState, originalData
        }

        // UIImage não é Codable, então customizamos
        init(url: URL, data: Data, image: UIImage, originalData: Data, editState: PhotoEditState? = nil) {
            self.url = url
            self.data = data
            self.image = image
            self.originalData = originalData
            self.editState = editState
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decode(URL.self, forKey: .url)
            data = try container.decode(Data.self, forKey: .data)
            originalData = (try? container.decode(Data.self, forKey: .originalData)) ?? data
            editState = try container.decodeIfPresent(PhotoEditState.self, forKey: .editState)
            image = loadUIImageThumbnail(from: data, maxPixel: 512) ?? UIImage()
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(url, forKey: .url)
            try container.encode(data, forKey: .data)
            try container.encodeIfPresent(editState, forKey: .editState)
            try container.encode(originalData, forKey: .originalData)
        }
    }
    @State private var photos: [StoredPhoto] = []
    @State private var showCamera = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedPhotoForEditor: UIImage? = nil
    @State private var selectedPhotoIndex: Int? = nil
    @State private var isSelectionActive: Bool = false

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
                            selectedPhotoIndex = index
                            navigateToPhotoEditor(photo: photos[index].image)
                        },
                        onPhotosChanged: {
                            savePhotos()
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
                pendingImportItems = newItems
                if AppSettings.shared.rawHandlingDefault == .ask {
                    showRawChoiceDialog = true
                } else {
                    batchRawHandling = AppSettings.shared.rawHandlingDefault
                    processImport(items: newItems, rawHandling: batchRawHandling!)
                }
            }
            .onAppear {
                busyTitle = "Carregando fotos..."
                isBusy = true
                DispatchQueue.global(qos: .userInitiated).async {
                    loadPhotos()
                    DispatchQueue.main.async { isBusy = false }
                }
            }
            .navigationDestination(isPresented: $showCamera) {
                PhotoCaptureView(onPhotoCaptured: { photo in
                    busyTitle = "Salvando foto..."
                    isBusy = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        let orientationFixedPhoto = photo.fixOrientation()
                        // Tenta salvar como HEIC, depois JPG, depois PNG
                        var data: Data? = nil
                        var ext: String = "heic"
                        if let heicData = exportUIImageAsHEIC(orientationFixedPhoto) {
                            data = heicData
                            ext = "heic"
                        } else if let jpgData = orientationFixedPhoto.jpegData(compressionQuality: 1.0) {
                            data = jpgData
                            ext = "jpg"
                        } else if let pngData = orientationFixedPhoto.pngData() {
                            data = pngData
                            ext = "png"
                        }
                        if let data {
                            let filename = "photo_\(UUID().uuidString).\(ext)"
                            let url = getPhotoStorageDir().appendingPathComponent(filename)
                            try? FileManager.default.createDirectory(at: getPhotoStorageDir(), withIntermediateDirectories: true)
                            try? data.write(to: url)
                            DispatchQueue.main.async {
                                let thumb = loadUIImageThumbnail(from: data, maxPixel: 512) ?? orientationFixedPhoto
                                photos.append(StoredPhoto(url: url, data: data, image: thumb, originalData: data))
                                savePhotos()
                                isBusy = false
                            }
                        } else {
                            DispatchQueue.main.async { isBusy = false }
                        }
                    }
                })
                .navigationTransition(
                    .zoom(
                        sourceID: "camera",
                        in: ns
                    )
                )
            }
            .navigationDestination(isPresented: Binding<Bool>(
                get: { selectedPhotoForEditor != nil },
                set: { if !$0 { selectedPhotoForEditor = nil; selectedPhotoIndex = nil } }
            )) {
                if let idx = selectedPhotoIndex, photos.indices.contains(idx) {
                    let stored = photos[idx]
                    let initialEditState = stored.editState
                    let originalImage = loadUIImageFullQuality(from: stored.originalData) ?? stored.image
                    PhotoEditorView(photo: originalImage, namespace: ns, matchedID: "", initialEditState: initialEditState) { finalImage, editState, didSave in
                        if didSave, let finalImage, let editState {
                            busyTitle = "Salvando edição..."
                            isBusy = true
                            DispatchQueue.global(qos: .userInitiated).async {
                                var data: Data? = nil
                                var ext = "heic"
                                if let heicData = exportUIImageAsHEIC(finalImage) {
                                    data = heicData
                                    ext = "heic"
                                } else if let jpgData = finalImage.jpegData(compressionQuality: 1.0) {
                                    data = jpgData
                                    ext = "jpg"
                                } else if let pngData = finalImage.pngData() {
                                    data = pngData
                                    ext = "png"
                                }
                                if let data {
                                    let filename = "photo_\(UUID().uuidString).\(ext)"
                                    let url = getPhotoStorageDir().appendingPathComponent(filename)
                                    try? FileManager.default.createDirectory(at: getPhotoStorageDir(), withIntermediateDirectories: true)
                                    try? data.write(to: url)
                                    DispatchQueue.main.async {
                                        let thumb = loadUIImageThumbnail(from: data, maxPixel: 512) ?? finalImage
                                        photos[idx] = StoredPhoto(url: url, data: data, image: thumb, originalData: stored.originalData, editState: editState)
                                        savePhotos()
                                        isBusy = false
                                    }
                                } else {
                                    DispatchQueue.main.async { isBusy = false }
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
        .confirmationDialog("Importar RAW como?", isPresented: $showRawChoiceDialog, titleVisibility: .visible) {
            Button("Otimizado", role: .none) {
                batchRawHandling = .optimized
                processImport(items: pendingImportItems, rawHandling: .optimized)
            }
            Button("Original (pode usar muita memória)", role: .destructive) {
                batchRawHandling = .original
                processImport(items: pendingImportItems, rawHandling: .original)
            }
            Button("Cancelar", role: .cancel) {
                selectedItems.removeAll()
                pendingImportItems.removeAll()
            }
        } message: {
            Text("Para este lote de fotos RAW")
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
        // Snapshot no main e salva em background para não travar a UI
        let snapshot = self.photos
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                UserDefaults.standard.set(data, forKey: "savedPhotos")
            } catch {
                print("[savePhotos] Falha ao salvar fotos: \(error)")
            }
        }
    }

    func loadPhotos() {
        if let data = UserDefaults.standard.data(forKey: "savedPhotos") {
            do {
                let loaded = try JSONDecoder().decode([StoredPhoto].self, from: data)
                // Constrói thumbs leves para a grade
                photos = loaded.map { stored in
                    var s = stored
                    if let thumb = loadUIImageThumbnail(from: s.data, maxPixel: 512) {
                        s = StoredPhoto(url: s.url, data: s.data, image: thumb, originalData: s.originalData, editState: s.editState)
                    }
                    return s
                }
            } catch {
                print("[loadPhotos] Falha ao carregar fotos: \(error)")
            }
        }
    }

    // MARK: - Import com política escolhida
    func processImport(items: [PhotosPickerItem], rawHandling: RawHandlingChoice) {
        busyTitle = "Importando fotos..."
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            var importedPhotos: [StoredPhoto] = []
            let storageDir = getPhotoStorageDir()
            try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
            let group = DispatchGroup()
            for item in items {
                group.enter()
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        autoreleasepool {
                            let (isRaw, uti) = detectImageRawInfo(data: data)
                            let gridThumb = loadUIImageThumbnail(from: data, maxPixel: 512) ?? UIImage()
                            var storedURL: URL? = nil
                            var storedData: Data? = nil
                            if isRaw && rawHandling == .original {
                                let ext = rawFileExtension(from: uti) ?? "raw"
                                let filename = "photo_\(UUID().uuidString).\(ext)"
                                let url = storageDir.appendingPathComponent(filename)
                                do {
                                    try data.write(to: url)
                                    storedURL = url
                                    storedData = data
                                } catch {
                                    print("[Import] Falha ao salvar RAW em: \(url.path)")
                                }
                            } else {
                                if let img = loadUIImageWithHandling(from: data, handling: isRaw ? rawHandling : .optimized) {
                                    let (encoded, ext) = encodeUIImageBestEffort(img)
                                    let filename = "photo_\(UUID().uuidString).\(ext)"
                                    let url = storageDir.appendingPathComponent(filename)
                                    do {
                                        try encoded.write(to: url)
                                        storedURL = url
                                        storedData = encoded
                                    } catch {
                                        print("[Import] Falha ao salvar imagem em: \(url.path)")
                                    }
                                }
                            }
                            if let url = storedURL, let sdata = storedData {
                                importedPhotos.append(StoredPhoto(url: url, data: sdata, image: gridThumb, originalData: sdata))
                            }
                        }
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                if !importedPhotos.isEmpty {
                    photos.append(contentsOf: importedPhotos)
                    savePhotos()
                }
                selectedItems.removeAll()
                pendingImportItems.removeAll()
                isBusy = false
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
    let shouldDownsample: Bool = {
        if effectiveHandling == .original { return false }
        return maxSide > cap
    }()

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

func getPhotoStorageDir() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PhotoStorage")
}

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
