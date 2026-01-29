//
//  SolarisApp.swift
//  solaris
//
//  Created by Erick Barcelos on 26/08/24.
//

import SwiftUI

@main
struct SolarisApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var colorSchemeManager = ColorSchemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(colorSchemeManager)
        }
    }
}
