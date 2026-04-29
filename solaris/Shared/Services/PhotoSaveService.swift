import UIKit

/// Thread-safe service for saving captured and edited photos.
/// Uses Swift actor to guarantee serialized file I/O without manual DispatchQueue management.
actor PhotoSaveService {

    /// Saves a newly captured photo: writes original + thumbnail, returns a PhotoRecord.
    func saveCapturedPhoto(data: Data, ext: String, isFrontCamera: Bool, mirror: Bool) throws -> PhotoRecord {
        let lib = PhotoLibrary.shared
        lib.ensureDirs()

        var dataToWrite = data
        var extToUse = ext

        if isFrontCamera && mirror {
            if let img = UIImage(data: data) {
                let mirrored = img.horizontallyMirrored()
                let (encoded, encExt) = encodeUIImageBestEffort(mirrored)
                dataToWrite = encoded
                extToUse = encExt
            }
        }

        let id = UUID().uuidString
        let origURL = lib.originalsDir().appendingPathComponent("\(id).\(extToUse)")
        try dataToWrite.write(to: origURL)

        var thumbURL = lib.thumbsDir().appendingPathComponent("\(id).jpg")
        if let thumbImg = loadUIImageThumbnail(from: dataToWrite, maxPixel: 512),
           let (tdata, text) = encodeThumbnailImage(thumbImg) {
            thumbURL = lib.thumbsDir().appendingPathComponent("\(id).\(text)")
            try? tdata.write(to: thumbURL)
        }

        let rec = PhotoRecord(
            id: id,
            originalURL: origURL,
            thumbURL: thumbURL,
            editedURL: nil,
            editState: nil,
            createdAt: Date()
        )

        return rec
    }

    /// Saves an edited photo: writes edited file + updated thumbnail, returns updated PhotoRecord.
    func saveEditedPhoto(
        record: PhotoRecord,
        finalImage: UIImage,
        editState: PhotoEditState,
        baseFilterState: PhotoEditState?,
        editHistory: [PhotoEditState]
    ) throws -> PhotoRecord {
        let lib = PhotoLibrary.shared
        lib.ensureDirs()

        // Delete previous edit file
        if let oldEditURL = record.editedURL {
            try? FileManager.default.removeItem(at: oldEditURL)
        }

        var ext = "heic"
        var editURL = lib.editsDir().appendingPathComponent("\(record.id).\(ext)")

        if let url = writeUIImageWithSourceMetadata(finalImage, preferHEIC: true, destDir: lib.editsDir(), baseName: record.id, sourceURL: record.originalURL) {
            editURL = url
            ext = url.pathExtension.lowercased()
        } else {
            var dataOut: Data? = nil
            if let heic = exportUIImageAsHEIC(finalImage) { dataOut = heic; ext = "heic" }
            else if let jpg = finalImage.jpegData(compressionQuality: 1.0) { dataOut = jpg; ext = "jpg" }
            else if let png = finalImage.pngData() { dataOut = png; ext = "png" }
            guard let dataOut else { throw PhotoLibraryError.io("Failed to encode edited image") }
            editURL = lib.editsDir().appendingPathComponent("\(record.id).\(ext)")
            try? dataOut.write(to: editURL)
        }

        var thumbURL = lib.thumbsDir().appendingPathComponent("\(record.id).jpg")
        if let thumbImg = finalImage.resizeToFit(maxSize: 512),
           let (tdata, text) = encodeThumbnailImage(thumbImg) {
            thumbURL = lib.thumbsDir().appendingPathComponent("\(record.id).\(text)")
            try? tdata.write(to: thumbURL)
        }

        var updated = record
        updated.editedURL = editURL
        updated.thumbURL = thumbURL
        updated.editState = editState
        updated.baseFilterState = baseFilterState
        updated.editHistory = Array(editHistory.suffix(100))

        return updated
    }
}
