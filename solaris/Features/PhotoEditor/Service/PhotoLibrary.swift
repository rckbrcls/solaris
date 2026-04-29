import Foundation
import UIKit

struct PhotoRecord: Codable, Identifiable, Equatable {
    let id: String
    var originalURL: URL
    var thumbURL: URL
    var editedURL: URL?
    var editState: PhotoEditState?
    // Novo: persiste o filtro aplicado via TAP (baseFilterState)
    var baseFilterState: PhotoEditState? = nil
    var editHistory: [PhotoEditState]? = nil // histórico persistente de estados anteriores
    let createdAt: Date
}

struct PhotoManifest: Codable {
    var items: [PhotoRecord] = []
}

enum PhotoLibraryError: Error, LocalizedError {
    case io(String)
    case decode
    case manifestCorrupted

    var errorDescription: String? {
        switch self {
        case .io(let detail): return "File I/O error: \(detail)"
        case .decode: return "Failed to decode photo data"
        case .manifestCorrupted: return "Photo catalog is corrupted"
        }
    }
}

final class PhotoLibrary {
    static let shared = PhotoLibrary()
    private let queue = DispatchQueue(label: "com.solaris.photolibrary")
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
    func manifestBackupURL() -> URL { storageRoot().appendingPathComponent("manifest.json.bak") }

    func ensureDirs() {
        let fm = FileManager.default
        [storageRoot(), originalsDir(), thumbsDir(), editsDir()].forEach { url in
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        // Exclude photo storage from iCloud backup to avoid consuming user's iCloud quota
        var root = storageRoot()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    // MARK: - Manifest
    func loadManifest() -> PhotoManifest {
        queue.sync { _loadManifest() }
    }

    private func _loadManifest() -> PhotoManifest {
        ensureDirs()
        let url = manifestURL()
        let backupURL = manifestBackupURL()

        // Try primary, then backup
        let manifest: PhotoManifest
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(PhotoManifest.self, from: data) {
            manifest = decoded
        } else if let bakData = try? Data(contentsOf: backupURL),
                  let decoded = try? JSONDecoder().decode(PhotoManifest.self, from: bakData) {
            // Primary corrupted — recover from backup
            manifest = decoded
        } else {
            return PhotoManifest()
        }

        // Normalize paths to current app container
        let root = storageRoot().path
        let fm = FileManager.default
        func fixURL(_ old: URL, in subdir: URL) -> URL {
            subdir.appendingPathComponent(old.lastPathComponent)
        }
        let normalizedItems: [PhotoRecord] = manifest.items.compactMap { rec in
            var r = rec
            if !r.originalURL.path.hasPrefix(root) { r.originalURL = fixURL(r.originalURL, in: originalsDir()) }
            if !r.thumbURL.path.hasPrefix(root) { r.thumbURL = fixURL(r.thumbURL, in: thumbsDir()) }
            if let e = r.editedURL, !e.path.hasPrefix(root) { r.editedURL = fixURL(e, in: editsDir()) }
            guard fm.fileExists(atPath: r.originalURL.path) else { return nil }
            return r
        }
        return PhotoManifest(items: normalizedItems)
    }

    func saveManifest(_ manifest: PhotoManifest) throws {
        try queue.sync { try _saveManifest(manifest) }
    }

    private func _saveManifest(_ manifest: PhotoManifest) throws {
        ensureDirs()
        let url = manifestURL()
        let backupURL = manifestBackupURL()
        let fm = FileManager.default

        // Create backup of current manifest before overwriting
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: url, to: backupURL)
        }

        let data = try JSONEncoder().encode(manifest)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try? fm.replaceItemAt(url, withItemAt: tmp)
        if fm.fileExists(atPath: tmp.path) {
            try? fm.removeItem(at: tmp)
        }
    }

    /// Removes orphan files not referenced in manifest
    func cleanupOrphanFiles() {
        queue.sync {
            let manifest = _loadManifest()
            let fm = FileManager.default
            let referencedFiles = Set(manifest.items.flatMap { rec -> [String] in
                var files = [rec.originalURL.lastPathComponent, rec.thumbURL.lastPathComponent]
                if let e = rec.editedURL { files.append(e.lastPathComponent) }
                return files
            })

            for dir in [originalsDir(), thumbsDir(), editsDir()] {
                guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
                for file in files where !referencedFiles.contains(file) {
                    try? fm.removeItem(at: dir.appendingPathComponent(file))
                }
            }
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
