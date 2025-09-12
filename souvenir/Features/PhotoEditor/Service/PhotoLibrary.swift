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
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(PhotoManifest.self, from: data) else {
            return PhotoManifest()
        }
        // Normaliza caminhos absolutos antigos para o diretório atual do app
        let root = storageRoot().path
        let fm = FileManager.default
        func fixURL(_ old: URL, in subdir: URL) -> URL {
            let fname = old.lastPathComponent
            let candidate = subdir.appendingPathComponent(fname)
            return candidate
        }
        let normalizedItems: [PhotoRecord] = manifest.items.compactMap { rec in
            var r = rec
            // Reaponta se estiver fora do container atual
            if !r.originalURL.path.hasPrefix(root) { r.originalURL = fixURL(r.originalURL, in: originalsDir()) }
            if !r.thumbURL.path.hasPrefix(root) { r.thumbURL = fixURL(r.thumbURL, in: thumbsDir()) }
            if let e = r.editedURL, !e.path.hasPrefix(root) { r.editedURL = fixURL(e, in: editsDir()) }
            // Filtra itens cujos arquivos não existem mais (aplicativo reinstalado, etc.)
            guard fm.fileExists(atPath: r.originalURL.path) else { return nil }
            return r
        }
        return PhotoManifest(items: normalizedItems)
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
