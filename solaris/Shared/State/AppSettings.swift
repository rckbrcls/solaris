import Foundation
import SwiftUI

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var preserveMetadata: Bool = true { didSet { persist() } }
    @Published var exportColorSpace: ExportColorSpacePreference = .auto { didSet { persist() } }
    @Published var historyLimit: Int = 100 { didSet { persist() } }
    @Published var mirrorFrontCamera: Bool = false { didSet { persist() } }

    // Camera settings (persisted between sessions)
    @Published var cameraFlashOn: Bool = false { didSet { persist() } }
    @Published var cameraGridOn: Bool = false { didSet { persist() } }
    @Published var cameraAspectRatio: AspectOption = .ratio4x3 { didSet { persist() } }
    @Published var cameraUseFrontCamera: Bool = false { didSet { persist() } }

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
        case .auto: return "Auto (match source)"
        case .sRGB: return "sRGB (default)"
        case .displayP3: return "Display P3 (wide gamut)"
        }
    }
    }

    private struct Stored: Codable {
        let preserveMetadata: Bool
        let exportColorSpace: ExportColorSpacePreference
        let historyLimit: Int
        let mirrorFrontCamera: Bool
        let cameraFlashOn: Bool
        let cameraGridOn: Bool
        let cameraAspectRatio: AspectOption
        let cameraUseFrontCamera: Bool
    }

    private func persist() {
        let payload = Stored(
            preserveMetadata: preserveMetadata,
            exportColorSpace: exportColorSpace,
            historyLimit: historyLimit,
            mirrorFrontCamera: mirrorFrontCamera,
            cameraFlashOn: cameraFlashOn,
            cameraGridOn: cameraGridOn,
            cameraAspectRatio: cameraAspectRatio,
            cameraUseFrontCamera: cameraUseFrontCamera
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        preserveMetadata = stored.preserveMetadata
        exportColorSpace = stored.exportColorSpace
        historyLimit = stored.historyLimit
        mirrorFrontCamera = stored.mirrorFrontCamera
        cameraFlashOn = stored.cameraFlashOn
        cameraGridOn = stored.cameraGridOn
        cameraAspectRatio = stored.cameraAspectRatio
        cameraUseFrontCamera = stored.cameraUseFrontCamera
    }
}
