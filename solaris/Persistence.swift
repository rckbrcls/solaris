//
//  Persistence.swift
//  solaris
//
//  Created by Erick Barcelos on 26/08/24.
//

import Foundation
import SwiftData

struct PersistenceController {
    static let shared: ModelContainer = {
        let schema = Schema([Item.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    static var preview: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: Item.self, configurations: config)
            let context = ModelContext(container)
            for _ in 0..<10 {
                context.insert(Item(timestamp: Date()))
            }
            try context.save()
            return container
        } catch {
            fatalError("Could not create preview ModelContainer: \(error)")
        }
    }()
}
