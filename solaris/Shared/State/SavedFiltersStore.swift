import Foundation

struct SavedFilterRecord: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let state: PhotoEditState
    let createdAt: Date
}

@Observable
final class SavedFiltersStore {
    static let shared = SavedFiltersStore()

    private(set) var filters: [SavedFilterRecord] = []

    var isEmpty: Bool { filters.isEmpty }

    private let key = "SavedFilters_v1"

    private init() {
        restore()
    }

    func addFilter(name: String, state: PhotoEditState) {
        let record = SavedFilterRecord(
            id: UUID().uuidString,
            name: name,
            state: state,
            createdAt: Date()
        )
        filters.append(record)
        persist()
    }

    func deleteFilter(id: String) {
        filters.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(filters) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedFilterRecord].self, from: data) else { return }
        filters = decoded
    }
}
