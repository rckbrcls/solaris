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
    @State private var isImporting: Bool = false
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
            image = loadUIImageFullQuality(from: data) ?? UIImage()
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

                if isImporting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Importando fotos...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .padding(40)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(16)
                }
            }
            .onChange(of: selectedItems) { _, newItems in
                isImporting = true
                DispatchQueue.global(qos: .userInitiated).async {
                    var importedPhotos: [StoredPhoto] = []
                    let storageDir = getPhotoStorageDir()
                    try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
                    let group = DispatchGroup()
                    for item in newItems {
                        group.enter()
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                if let img = loadUIImageFullQuality(from: data) {
                                    let ext = detectImageExtension(data: data)
                                    let filename: String
                                    let url: URL
                                    var outData: Data? = nil
                                    var outExt: String = ext
                                    switch ext {
                                    case "heic":
                                        if let heicData = exportUIImageAsHEIC(img) {
                                            outData = heicData
                                            outExt = "heic"
                                        }
                                    case "jpg":
                                        if let jpgData = img.jpegData(compressionQuality: 1.0) {
                                            outData = jpgData
                                            outExt = "jpg"
                                        }
                                    case "png":
                                        if let pngData = img.pngData() {
                                            outData = pngData
                                            outExt = "png"
                                        }
                                    default:
                                        // fallback para PNG
                                        if let pngData = img.pngData() {
                                            outData = pngData
                                            outExt = "png"
                                        }
                                    }
                                    filename = "photo_\(UUID().uuidString).\(outExt)"
                                    url = storageDir.appendingPathComponent(filename)
                                    do {
                                        if let outData {
                                            try outData.write(to: url)
                                            importedPhotos.append(StoredPhoto(url: url, data: outData, image: img, originalData: outData))
                                        }
                                    } catch {
                                        print("[Import] Falha ao salvar imagem em: \(url.path)")
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
                        isImporting = false
                    }
                }
            }
            .onAppear {
                loadPhotos()
            }
            .navigationDestination(isPresented: $showCamera) {
                PhotoCaptureView(onPhotoCaptured: { photo in
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
                        photos.append(StoredPhoto(url: url, data: data, image: orientationFixedPhoto, originalData: data))
                        savePhotos()
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
                                photos[idx] = StoredPhoto(url: url, data: data, image: finalImage, originalData: stored.originalData, editState: editState)
                                savePhotos()
                            }
                        } else if !didSave {
                            // Descartou alterações: não faz nada
                        }
                        selectedPhotoForEditor = nil
                        selectedPhotoIndex = nil
                    }
                    .navigationBarBackButtonHidden(true)
                }
            }
        }
        .observeColorScheme()
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
        // Salva paths e ajustes
        do {
            let data = try JSONEncoder().encode(photos)
            UserDefaults.standard.set(data, forKey: "savedPhotos")
        } catch {
            print("[savePhotos] Falha ao salvar fotos: \(error)")
        }
    }

    func loadPhotos() {
        if let data = UserDefaults.standard.data(forKey: "savedPhotos") {
            do {
                let loaded = try JSONDecoder().decode([StoredPhoto].self, from: data)
                photos = loaded
            } catch {
                print("[loadPhotos] Falha ao carregar fotos: \(error)")
            }
        }
    }
}

// MARK: - Carregamento de imagem com máxima qualidade
func loadUIImageFullQuality(from data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return UIImage(data: data)
    }

    // Opções para carregar a imagem já com a orientação EXIF aplicada
    let options: [CFString: Any] = [
        kCGImageSourceShouldAllowFloat: true,
        kCGImageSourceCreateThumbnailFromImageAlways: false,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true
    ]

    // Pega a orientação EXIF
    let propertiesOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    var orientation: UIImage.Orientation = .up
    if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, propertiesOptions) as? [CFString: Any],
       let exifOrientation = properties[kCGImagePropertyOrientation] as? UInt32 {
        orientation = UIImage.Orientation(exifOrientation: exifOrientation)
    }

    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
        return UIImage(data: data)
    }

    let scale: CGFloat = UIScreen.main.scale
    let image = UIImage(cgImage: cgImage, scale: scale, orientation: orientation)
    // Garante que a orientação será .up para todo o app
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
