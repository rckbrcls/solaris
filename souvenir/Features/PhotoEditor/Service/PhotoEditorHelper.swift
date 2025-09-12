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
    
    static func sliderRange(for option: String) -> ClosedRange<Double> {
        switch option {
        case "brightness": return -1.0...1.0
        case "contrast": return 0.5...1.5
        case "saturation": return 0.0...2.0
        case "exposure": return -2.0...2.0
        case "sharpness": return 0.0...2.0
        case "grain": return 0.0...0.1
        case "whitePoint": return 0.0...1.0
        default: return 0...1
        }
    }
    static func defaultSliderValue(for option: String) -> Double {
        switch option {
        case "brightness": return 0.0
        case "contrast": return 1.0
        case "saturation": return 1.0
        case "exposure": return 0.0
        case "sharpness": return 0.0
        case "grain": return 0.02
        case "whitePoint": return 1.0
        default: return 0.0
        }
    }
    static func editOptionIcon(for option: String) -> String {
        switch option {
        case "brightness": return "sun.max"
        case "contrast": return "circle.lefthalf.fill"
        case "saturation": return "drop"
        case "exposure": return "sunrise"
        case "sharpness": return "eye"
        case "grain": return "circle.grid.cross"
        case "whitePoint": return "circle.dotted"
        default: return "slider.horizontal.3"
        }
    }
    static func thumbnail(for image: UIImage, maxDimension: CGFloat = 60) -> UIImage? {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let thumb = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return thumb
    }
}
