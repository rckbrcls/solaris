import SwiftUI

extension Animation {
    /// Standard dismiss/overlay animation used throughout the editor (0.22s ease-out).
    static let editorDismiss = Animation.easeOut(duration: 0.22)

    /// Standard spring used for modal presentation in the editor.
    static let editorSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)
}
