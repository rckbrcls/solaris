import UIKit

/// Convenience wrappers for UIImpactFeedbackGenerator to eliminate boilerplate.
enum Haptics {
    static func light(intensity: CGFloat = 1.0) {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred(intensity: intensity)
    }

    static func medium() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }

    static func heavy() {
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.impactOccurred()
    }

    static func rigid(intensity: CGFloat = 1.0) {
        let gen = UIImpactFeedbackGenerator(style: .rigid)
        gen.impactOccurred(intensity: intensity)
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1.0) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred(intensity: intensity)
    }
}
