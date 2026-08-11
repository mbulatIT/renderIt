import Foundation
import CoreGraphics
import ImageIO

/// Tiny in-memory CGImage cache shared by every renderer in the process. Keyed by URL.
/// All decode work happens once; subsequent calls return the same CGImage instance, so
/// CG can short-circuit re-uploads and SwiftUI Image diffing stays cheap.
public final class CGImageCache: @unchecked Sendable {
    public static let shared = CGImageCache(capacity: 96)

    private let queue = DispatchQueue(label: "com.bulat.aiimageeditor.imageCache")
    private var cache: [String: CGImage] = [:]
    private var order: [String] = []
    private let capacity: Int

    public init(capacity: Int = 96) {
        self.capacity = max(8, capacity)
    }

    /// Decode the image at `url` if needed, then return the cached CGImage.
    /// Returns nil only if the file can't be decoded.
    public func image(at url: URL) -> CGImage? {
        let key = url.absoluteString
        if let cached = queue.sync(execute: { cache[key] }) {
            return cached
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return nil
        }
        queue.sync {
            cache[key] = cg
            order.append(key)
            while order.count > capacity {
                let evict = order.removeFirst()
                cache.removeValue(forKey: evict)
            }
        }
        return cg
    }

    /// Drop a single entry — call when an asset file is known to have changed.
    public func invalidate(at url: URL) {
        let key = url.absoluteString
        queue.sync {
            cache.removeValue(forKey: key)
            order.removeAll { $0 == key }
        }
    }

    public func invalidateAll() {
        queue.sync {
            cache.removeAll()
            order.removeAll()
        }
    }
}
