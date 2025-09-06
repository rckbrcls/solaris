//
//  ColorSchemeManager.swift
//  souvenir
//
//  Created by Erick Barcelos on 31/05/25.
//


import SwiftUI

// A view model to manage color scheme changes
class ColorSchemeManager: ObservableObject {
    @Published var currentColorScheme: ColorScheme?

    func updateColorScheme(_ colorScheme: ColorScheme) {
        currentColorScheme = colorScheme
    }

    var primaryColor: Color {
        currentColorScheme == .dark ? .white : .black
    }

    var secondaryColor: Color {
        currentColorScheme == .dark ? .black : .white
    }
    
    // Cor esmeralda para indicadores de filtros aplicados via long press
    static let emerald = Color(red: 0.1, green: 0.85, blue: 0.55)
}

struct ColorSchemeObserver: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var colorSchemeManager: ColorSchemeManager

    func body(content: Content) -> some View {
        content
            .onAppear {
                colorSchemeManager.updateColorScheme(colorScheme)
            }
            .onChange(of: colorScheme) { _, newScheme in
                colorSchemeManager.updateColorScheme(newScheme)
            }
    }
}

// Convenience method for applying the modifier easily
extension View {
    func observeColorScheme() -> some View {
        self.modifier(ColorSchemeObserver())
    }
}
