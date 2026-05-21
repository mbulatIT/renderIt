import Foundation

public struct CanvasPreset: Sendable {
    public let id: String
    public let title: String
    public let width: Int
    public let height: Int
}

public enum PresetCatalog {
    public static let all: [CanvasPreset] = [
        .init(id: "iphone-6.7",      title: "iPhone 6.7\" (1290×2796)", width: 1290, height: 2796),
        .init(id: "iphone-6.5",      title: "iPhone 6.5\" (1284×2778)", width: 1284, height: 2778),
        .init(id: "iphone-5.5",      title: "iPhone 5.5\" (1242×2208)", width: 1242, height: 2208),
        .init(id: "ipad-13",         title: "iPad Pro 13\" (2064×2752)", width: 2064, height: 2752),
        .init(id: "ipad-12.9",       title: "iPad Pro 12.9\" (2048×2732)", width: 2048, height: 2732),
        .init(id: "mac",             title: "Mac (2880×1800)",            width: 2880, height: 1800),
        .init(id: "watch-ultra",     title: "Apple Watch Ultra (410×502)", width: 410, height: 502),
        .init(id: "iphone-portrait", title: "Portrait 9:16 (1080×1920)",  width: 1080, height: 1920),
        .init(id: "iphone-landscape",title: "Landscape 16:9 (1920×1080)", width: 1920, height: 1080),
        .init(id: "square-1k",       title: "Square (1024×1024)",          width: 1024, height: 1024),
    ]

    public static func find(id: String) -> CanvasPreset? {
        all.first { $0.id == id }
    }
}
