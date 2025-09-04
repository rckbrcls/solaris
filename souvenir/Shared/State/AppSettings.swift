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

    private let key = "AppSettings_v1"

    private init() {
        restore()
    }

    private struct Stored: Codable {
        let rawHandlingDefault: RawHandlingChoice
        let maxRawLongestSide: Int
        let maxNonRawLongestSide: Int
    }

    private func persist() {
        let payload = Stored(
            rawHandlingDefault: rawHandlingDefault,
            maxRawLongestSide: maxRawLongestSide,
            maxNonRawLongestSide: maxNonRawLongestSide
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        rawHandlingDefault = stored.rawHandlingDefault
        maxRawLongestSide = stored.maxRawLongestSide
        maxNonRawLongestSide = stored.maxNonRawLongestSide
    }
}

