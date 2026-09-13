import Foundation
#if canImport(UIKit)
import UIKit

/// Decodes attachment image data once and reuses the `UIImage` across bubble re-renders.
enum DecodedImageCache {
    // NSCache is thread-safe; mark unsafe for Swift 6 static storage rules.
    nonisolated(unsafe) private static let cache: NSCache<NSUUID, UIImage> = {
        let cache = NSCache<NSUUID, UIImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func image(for attachment: ChatImageAttachment) -> UIImage? {
        let key = attachment.id as NSUUID
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = UIImage(data: attachment.data) else { return nil }
        cache.setObject(image, forKey: key, cost: attachment.data.count)
        return image
    }
}
#endif
