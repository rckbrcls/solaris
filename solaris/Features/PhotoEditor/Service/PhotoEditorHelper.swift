import UIKit

struct PhotoEditorHelper {
    
    /// Returns a suggested max preview size in points to keep the image sharp
    /// up to the configured double-tap zoom level (default 3x) on the current device.
    /// The actual pixel resolution will be this value times the device screen scale.
    static func suggestedPreviewMaxPoints(doubleTapZoomScale: CGFloat = 3.0) -> CGFloat {
        let screen = UIScreen.main
        // Use the larger screen dimension in points, multiply by the max zoom factor
        // so the preview remains crisp when zoomed in.
        let longestSidePoints = max(screen.bounds.width, screen.bounds.height)
        return longestSidePoints * doubleTapZoomScale
    }
    
}
