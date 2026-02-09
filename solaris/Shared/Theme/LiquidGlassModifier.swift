import SwiftUI

extension View {
    /// Applies a glass-style effect that prefers the native Liquid Glass on iOS 26+
    /// and falls back to ultra-thin material on earlier OS versions.
    /// - Parameters:
    ///   - containerShape: Shape used to clip and render the effect.
    ///   - addSubtleBorder: Whether to draw a soft outline around the glass surface.
    ///   - borderColor: Color of the optional border; defaults to a subtle primary tint.
    ///   - borderLineWidth: Line width for the optional border.
    /// - Returns: A view decorated with a glass-like treatment appropriate to the OS.
    func liquidGlass<ShapeType: InsettableShape>(
        in containerShape: ShapeType = RoundedRectangle(cornerRadius: 16, style: .continuous),
        addSubtleBorder: Bool = true,
        borderColor: Color = Color.primary.opacity(0.08),
        borderLineWidth: CGFloat = 1
    ) -> some View {
        modifier(
            LiquidGlassModifier(
                containerShape: containerShape,
                addSubtleBorder: addSubtleBorder,
                borderColor: borderColor,
                borderLineWidth: borderLineWidth
            )
        )
    }
}

private struct LiquidGlassModifier<ShapeType: InsettableShape>: ViewModifier {
    let containerShape: ShapeType
    let addSubtleBorder: Bool
    let borderColor: Color
    let borderLineWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffect(in: containerShape)
            .overlayBorderIfNeeded(
                using: containerShape,
                addBorder: addSubtleBorder,
                color: borderColor,
                lineWidth: borderLineWidth
            )
            .contentShape(containerShape)
    }
}

private extension View {
    @ViewBuilder
    func overlayBorderIfNeeded<ShapeType: InsettableShape>(
        using shape: ShapeType,
        addBorder: Bool,
        color: Color,
        lineWidth: CGFloat
    ) -> some View {
        if addBorder {
            overlay(
                shape.strokeBorder(color, lineWidth: lineWidth)
                    .allowsHitTesting(false)
            )
        } else {
            self
        }
    }
}
