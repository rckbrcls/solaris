import SwiftUI

/// Circular liquid glass icon style — shared between camera and editor buttons.
struct GlassIconStyle: ViewModifier {
    var size: CGFloat = 44
    var foreground: Color = .textPrimary

    func body(content: Content) -> some View {
        content
            .foregroundColor(foreground)
            .frame(width: size, height: size)
            .liquidGlass(in: Circle(), borderColor: Color.borderStrong)
            .contentShape(Circle())
    }
}

extension View {
    func glassIconStyle(size: CGFloat = 44, foreground: Color = .textPrimary) -> some View {
        modifier(GlassIconStyle(size: size, foreground: foreground))
    }
}
