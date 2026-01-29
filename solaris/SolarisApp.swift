//
//  SolarisApp.swift
//  solaris
//
//  Created by Erick Barcelos on 26/08/24.
//

import SwiftUI
import SwiftData

@main
struct SolarisApp: App {
    @StateObject private var colorSchemeManager = ColorSchemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: Item.self)
                .environmentObject(colorSchemeManager)
        }
    }
}
