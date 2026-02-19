//
//  SolarisApp.swift
//  solaris
//
//  Created by Erick Barcelos on 26/08/24.
//

import SwiftUI

@main
struct SolarisApp: App {
    @StateObject private var colorSchemeManager = ColorSchemeManager()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(colorSchemeManager)
        }
    }
}
