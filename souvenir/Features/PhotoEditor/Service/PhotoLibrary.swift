import Foundation
import UIKit

struct PhotoRecord: Codable, Identifiable, Equatable {
    let id: String
    var originalURL: URL
    var thumbURL: URL
    var editedURL: URL?
    var editState: PhotoEditState?
    let createdAt: Date
}

struct PhotoManifest: Codable {
    var items: [PhotoRecord] = []
}

enum PhotoLibraryError: Error { case io, decode }

final class PhotoLibrary {
    static let shared = PhotoLibrary()
    private init() {}

    // MARK: - Directories
    func storageRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhotoStorage")
    }

    func originalsDir() -> URL { storageRoot().appendingPathComponent("originals") }
    func thumbsDir() -> URL { storageRoot().appendingPathComponent("thumbs") }
    func editsDir() -> URL { storageRoot().appendingPathComponent("edits") }
    func manifestURL() -> URL { storageRoot().appendingPathComponent("manifest.json") }

    func ensureDirs() {
        let fm = FileManager.default
        [storageRoot(), originalsDir(), thumbsDir(), editsDir()].forEach { url in
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Manifest
    func loadManifest() -> PhotoManifest {
        ensureDirs()
        let url = manifestURL()
        guard let data = try? Data(contentsOf: url) else { return PhotoManifest() }
        if let manifest = try? JSONDecoder().decode(PhotoManifest.self, from: data) {
            return manifest
        }
        return PhotoManifest()
    }

    func saveManifest(_ manifest: PhotoManifest) throws {
        ensureDirs()
        let url = manifestURL()
        let tmp = url.appendingPathExtension("tmp")
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        if FileManager.default.fileExists(atPath: tmp.path) {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    // MARK: - Record helpers
    func deleteFiles(for record: PhotoRecord) {
        let fm = FileManager.default
        [record.thumbURL, record.originalURL, record.editedURL].compactMap { $0 }.forEach { url in
            try? fm.removeItem(at: url)
        }
    }
}

