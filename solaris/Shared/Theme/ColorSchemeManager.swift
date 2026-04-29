import SwiftUI

@Observable
final class ColorSchemeManager {
    var currentColorScheme: ColorScheme?

    func updateColorScheme(_ colorScheme: ColorScheme) {
        currentColorScheme = colorScheme
    }
}

struct ColorSchemeObserver: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    @Environment(ColorSchemeManager.self) var colorSchemeManager

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

extension View {
    func observeColorScheme() -> some View {
        self.modifier(ColorSchemeObserver())
    }
}
