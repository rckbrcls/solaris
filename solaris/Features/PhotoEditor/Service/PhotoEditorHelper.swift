import UIKit

struct PhotoEditorHelper {

    /// Returns a suggested max preview size in points to keep the image sharp
    /// up to the configured double-tap zoom level (default 3x) on the current device.
    /// The actual pixel resolution will be this value times the device screen scale.
    static func suggestedPreviewMaxPoints(doubleTapZoomScale: CGFloat = 3.0) -> CGFloat {
        let screenBounds: CGRect = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds ?? CGRect(x: 0, y: 0, width: 393, height: 852)
        let longestSidePoints = max(screenBounds.width, screenBounds.height)
        return longestSidePoints * doubleTapZoomScale
    }

}
