import SwiftUI
import PhotosUI
import FluidGradient

struct HomeView: View {
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager
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
                        .scaledToFit()
                        .frame(height: 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .overlay(
                            Rectangle()
                                .fill(Color.borderSubtle)
                                .frame(height: 1),
                            alignment: .bottom
                        )
                    PhotosScrollView(
                        photos: $photos,
                        selectedItems: $selectedItems,
                        ns: ns,
                        onPhotoSelected: { index in
                            openEditor(for: index)
                        },
                        onPhotosChanged: {
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
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            SettingsFloatingButtonView {
                                showSettings = true
                            }
                            .padding(.trailing, 18)
                            .padding(.bottom, 30)
                        }
                    }
                }

                LoadingOverlay(isVisible: $isBusy, title: busyTitle)
            }
            .onChange(of: selectedItems) { _, newItems in
                importWorkItem?.cancel()
                guard !newItems.isEmpty else { return }
                let snapshot = newItems
                let work = DispatchWorkItem {
                    if isImportFlowActive { return }
                    isImportFlowActive = true
                    processImport(items: snapshot)
                }
                importWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            }
            .onAppear {
                guard !didInitialLoad else { return }
                busyTitle = "Loading photos..."
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
                PhotoCaptureView(onPhotoCaptured: { data, ext, isFrontCamera in
                    busyTitle = "Saving photo..."
                    isBusy = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        let lib = PhotoLibrary.shared
                        lib.ensureDirs()
                        var dataToWrite = data
                        var extToUse = ext
                        if isFrontCamera && AppSettings.shared.mirrorFrontCamera {
                            if let img = UIImage(data: data) {
                                let mirrored = img.horizontallyMirrored()
                                let (encoded, encExt) = encodeUIImageBestEffort(mirrored)
                                dataToWrite = encoded
                                extToUse = encExt
                            }
                        }
                        let id = UUID().uuidString
                        let origURL = lib.originalsDir().appendingPathComponent("\(id).\(extToUse)")
                        try? dataToWrite.write(to: origURL)
                        var thumbURL = lib.thumbsDir().appendingPathComponent("\(id).jpg")
                        if let thumbImg = loadUIImageThumbnail(from: dataToWrite, maxPixel: 512),
                           let (tdata, text) = encodeThumbnailImage(thumbImg) {
                            thumbURL = lib.thumbsDir().appendingPathComponent("\(id).\(text)")
                            try? tdata.write(to: thumbURL)
                        }
                        let rec = PhotoRecord(id: id, originalURL: origURL, thumbURL: thumbURL, editedURL: nil, editState: nil, createdAt: Date())
                        records.append(rec)
                        try? lib.saveManifest(PhotoManifest(items: records))
                        let uiThumb = UIImage(contentsOfFile: thumbURL.path) ?? loadUIImageThumbnail(from: dataToWrite, maxPixel: 512)
                        if let thumb = uiThumb {
                            ImageCache.shared.set(thumb, forKey: "thumb_\(id)")
                            DispatchQueue.main.async {
                                photos.append(PhotoItem(id: id, record: rec, image: thumb))
                                isBusy = false
                            }
                        } else {
                            DispatchQueue.main.async { isBusy = false }
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
                    let previewImage = selectedPhotoForEditor ?? item.image
                    PhotoEditorView(photo: previewImage, originalURL: rec.originalURL, namespace: ns, matchedID: "", initialEditState: initialEditState, initialBaseFilterState: rec.baseFilterState, initialHistory: rec.editHistory ?? []) { finalImage, editState, baseFilterState, history, didSave in
                        if didSave, let finalImage, let editState {
                            busyTitle = "Saving edit..."
                            isBusy = true
                            DispatchQueue.global(qos: .userInitiated).async {
                                let lib = PhotoLibrary.shared
                                lib.ensureDirs()
                                var ext = "heic"
                                var editURL = lib.editsDir().appendingPathComponent("\(rec.id).\(ext)")
                                if let url = writeUIImageWithSourceMetadata(finalImage, preferHEIC: true, destDir: lib.editsDir(), baseName: rec.id, sourceURL: rec.originalURL) {
                                    editURL = url
                                    ext = url.pathExtension.lowercased()
                                } else {
                                    var dataOut: Data? = nil
                                    if let heic = exportUIImageAsHEIC(finalImage) { dataOut = heic; ext = "heic" }
                                    else if let jpg = finalImage.jpegData(compressionQuality: 1.0) { dataOut = jpg; ext = "jpg" }
                                    else if let png = finalImage.pngData() { dataOut = png; ext = "png" }
                                    guard let dataOut else { DispatchQueue.main.async { isBusy = false }; return }
                                    editURL = lib.editsDir().appendingPathComponent("\(rec.id).\(ext)")
                                    try? dataOut.write(to: editURL)
                                }
                                var thumbURL = lib.thumbsDir().appendingPathComponent("\(rec.id).jpg")
                                if let thumbImg = finalImage.resizeToFit(maxSize: 512), let (tdata, text) = encodeThumbnailImage(thumbImg) {
                                    thumbURL = lib.thumbsDir().appendingPathComponent("\(rec.id).\(text)")
                                    try? tdata.write(to: thumbURL)
                                }
                                var updated = rec
                                updated.editedURL = editURL
                                updated.thumbURL = thumbURL
                                updated.editState = editState
                                updated.baseFilterState = baseFilterState
                                updated.editHistory = Array(history.suffix(100))
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
        let orientationFixedPhoto = photo.fixOrientation()
        if let safePhoto = orientationFixedPhoto.withAlpha() {
            selectedPhotoForEditor = safePhoto
        }
    }

    func savePhotos() {
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
        let baseURL = rec.originalURL
        busyTitle = "Opening..."
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

    // MARK: - Import
    func processImport(items: [PhotosPickerItem]) {
        busyTitle = "Importing photos..."
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
                            let ext = isRaw ? (rawFileExtension(from: uti) ?? "raw") : detectImageExtension(data: data)
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
                    semaphore.signal()
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                try? lib.saveManifest(PhotoManifest(items: records))
                selectedItems.removeAll()
                isBusy = false
                isImportFlowActive = false
            }
        }
    }
}

#Preview {
    HomeView()
}
