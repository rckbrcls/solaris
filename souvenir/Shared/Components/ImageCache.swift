import UIKit

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 50 * 1024 * 1024 // ~50 MB
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, forKey key: String, cost: Int? = nil) {
        if let cost { cache.setObject(image, forKey: key as NSString, cost: cost) }
        else { cache.setObject(image, forKey: key as NSString) }
    }

    func remove(_ key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}

