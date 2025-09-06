import Foundation
import SwiftUI

enum RawHandlingChoice: String, CaseIterable, Codable, Identifiable {
    case ask
    case optimized
    case original
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ask: return "Perguntar"
        case .optimized: return "Otimizado"
        case .original: return "Original"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var rawHandlingDefault: RawHandlingChoice = .ask { didSet { persist() } }
    @Published var maxRawLongestSide: Int = 5000 { didSet { persist() } }
    @Published var maxNonRawLongestSide: Int = 8000 { didSet { persist() } }
    @Published var preserveMetadata: Bool = true { didSet { persist() } }
    @Published var exportColorSpace: ExportColorSpacePreference = .auto { didSet { persist() } }
    @Published var historyLimit: Int = 100 { didSet { persist() } }
    @Published var hapticsEnabled: Bool = true { didSet { persist() } }
    @Published var mirrorFrontCamera: Bool = false { didSet { persist() } }

    private let key = "AppSettings_v1"

    private init() {
        restore()
    }

    enum ExportColorSpacePreference: String, CaseIterable, Codable, Identifiable {
        case auto
        case sRGB
        case displayP3
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Auto (igual original)"
            case .sRGB: return "sRGB (padrão)"
            case .displayP3: return "Display P3 (wide-gamut)"
            }
        }
    }

    private struct StoredV1: Codable {
        let rawHandlingDefault: RawHandlingChoice
        let maxRawLongestSide: Int
        let maxNonRawLongestSide: Int
    }

    private struct StoredV2: Codable {
        let rawHandlingDefault: RawHandlingChoice
        let maxRawLongestSide: Int
        let maxNonRawLongestSide: Int
        let preserveMetadata: Bool
        let exportColorSpace: ExportColorSpacePreference
        let historyLimit: Int
        let hapticsEnabled: Bool
        let mirrorFrontCamera: Bool
    }

    private func persist() {
        let payload = StoredV2(
            rawHandlingDefault: rawHandlingDefault,
            maxRawLongestSide: maxRawLongestSide,
            maxNonRawLongestSide: maxNonRawLongestSide,
            preserveMetadata: preserveMetadata,
            exportColorSpace: exportColorSpace,
            historyLimit: historyLimit,
            hapticsEnabled: hapticsEnabled,
            mirrorFrontCamera: mirrorFrontCamera
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        let dec = JSONDecoder()
        if let stored2 = try? dec.decode(StoredV2.self, from: data) {
            rawHandlingDefault = stored2.rawHandlingDefault
            maxRawLongestSide = stored2.maxRawLongestSide
            maxNonRawLongestSide = stored2.maxNonRawLongestSide
            preserveMetadata = stored2.preserveMetadata
            exportColorSpace = stored2.exportColorSpace
            historyLimit = stored2.historyLimit
            hapticsEnabled = stored2.hapticsEnabled
            mirrorFrontCamera = stored2.mirrorFrontCamera
            return
        }
        if let stored1 = try? dec.decode(StoredV1.self, from: data) {
            rawHandlingDefault = stored1.rawHandlingDefault
            maxRawLongestSide = stored1.maxRawLongestSide
            maxNonRawLongestSide = stored1.maxNonRawLongestSide
            // defaults for new fields
            preserveMetadata = true
            exportColorSpace = .auto
            historyLimit = 100
            hapticsEnabled = true
            mirrorFrontCamera = false
            hapticsEnabled = true
        }
    }
}
