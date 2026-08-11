import Foundation
import CoreGraphics
import ImageIO
import AppKit

/// Loads bezel PNGs + manifest from the AIImageEditorCore bundle and detects the inner
/// screen rectangle for each device at first use, then caches the result.
public final class BezelImageStore {
    public static let shared = BezelImageStore()

    public struct DeviceEntry: Sendable {
        public let id: String
        public let title: String
        public let family: DeviceBezel.Family
        public let aspect: Double
        public let viewBoxW: Double
        public let viewBoxH: Double
        /// Color label → bundled filename.
        public let colorFiles: [String: String]
        public let defaultColor: String
    }

    private let entries: [String: DeviceEntry]
    /// `deviceId` → cached screen-rect insets (left, top, right, bottom) as fractions of width/height.
    private var insetsCache: [String: (CGFloat, CGFloat, CGFloat, CGFloat)] = [:]
    /// `<deviceId>::<color>` → decoded chrome PNG (cached so we don't re-decode every render).
    private var chromeImageCache: [String: CGImage] = [:]
    /// `<deviceId>::<color>` → cached "filled-chrome" image (outer transparent areas painted opaque),
    /// used as the destinationOut mask so screenshots are confined to the screen well.
    private var filledChromeCache: [String: CGImage] = [:]
    /// `<deviceId>::<color>::<screenshotURL or empty>` → fully-composed bezel image at chrome
    /// native pixel size. Lets the renderer just blit-with-scale on every frame.
    private var compositeCache: [String: CGImage] = [:]
    private let queue = DispatchQueue(label: "com.bulat.aiimageeditor.bezelStore")

    public var allDeviceIds: [String] { Array(entries.keys) }
    public var allDevices: [DeviceEntry] {
        // Preserve manifest order
        return Array(entries.values).sorted { $0.id < $1.id }
    }

    private init() {
        self.entries = Self.loadManifest()
    }

    public func entry(deviceId: String) -> DeviceEntry? {
        entries[deviceId]
    }

    public func image(deviceId: String, color: String?) -> CGImage? {
        guard let entry = entries[deviceId] else { return nil }
        let resolved = color ?? entry.defaultColor
        let key = "\(deviceId)::\(resolved)"
        if let cached = queue.sync(execute: { chromeImageCache[key] }) { return cached }
        guard let filename = entry.colorFiles[resolved] ?? entry.colorFiles[entry.defaultColor] else { return nil }
        guard let cg = loadImage(filename: filename) else { return nil }
        queue.sync { chromeImageCache[key] = cg }
        return cg
    }

    /// Returns (image, screen-rect insets relative to image bounds).
    public func renderInfo(deviceId: String, color: String?) -> (CGImage, CGRect)? {
        guard let cg = image(deviceId: deviceId, color: color) else { return nil }
        let rect = screenRect(for: deviceId, image: cg)
        return (cg, rect)
    }

    /// Same as `image(...)` but with the outer transparent area (everything outside the device
    /// silhouette) painted opaque. Used as the `destinationOut` mask so a screenshot drawn
    /// underneath is confined to the chrome's screen well — both the chrome material AND the
    /// outer PNG corners are subtracted.
    public func filledChromeImage(deviceId: String, color: String?) -> CGImage? {
        guard let base = image(deviceId: deviceId, color: color) else { return nil }
        let key = "\(deviceId)::\(color ?? "default")"
        if let cached = queue.sync(execute: { filledChromeCache[key] }) { return cached }
        let filled = Self.fillOuterTransparentArea(image: base) ?? base
        queue.sync { filledChromeCache[key] = filled }
        return filled
    }

    /// Returns a fully-composed bezel image (chrome with the screenshot baked into its screen
    /// well, anti-aliased to the chrome's screen-well shape) at the chrome PNG's *native pixel
    /// size*. The renderer can then `ctx.draw(composite, in: outer)` at any frame, letting CG
    /// do the (cheap) scaling. This moves the heavy offscreen + destinationOut work out of the
    /// per-frame path and makes drag/resize smooth.
    /// Pass `screenshotURL == nil` for a bezel without a screenshot (returns the chrome image).
    public func composedBezelImage(deviceId: String,
                                   color: String?,
                                   screenshotURL: URL?) -> CGImage? {
        let resolvedColor = color ?? entries[deviceId]?.defaultColor ?? "default"
        let key = "\(deviceId)::\(resolvedColor)::\(screenshotURL?.absoluteString ?? "")"
        if let cached = queue.sync(execute: { compositeCache[key] }) { return cached }

        guard let chrome = image(deviceId: deviceId, color: color) else { return nil }

        // No screenshot ⇒ composite == chrome. Cache the chrome under this key too so future
        // calls with the same arguments hit immediately.
        guard let url = screenshotURL,
              let screenshot = CGImageCache.shared.image(at: url),
              let filled = filledChromeImage(deviceId: deviceId, color: color) else {
            queue.sync { compositeCache[key] = chrome }
            return chrome
        }

        let result = buildComposite(deviceId: deviceId,
                                    chrome: chrome,
                                    filled: filled,
                                    screenshot: screenshot) ?? chrome
        queue.sync { compositeCache[key] = result }
        return result
    }

    private func buildComposite(deviceId: String,
                                chrome: CGImage,
                                filled: CGImage,
                                screenshot: CGImage) -> CGImage? {
        let w = chrome.width
        let h = chrome.height
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Top-left coordinate system.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        let fullRect = CGRect(x: 0, y: 0, width: w, height: h)
        let screen = screenRect(for: deviceId, image: chrome)

        // 1) Paint screenshot fitted to the screen rect.
        ctx.saveGState()
        ctx.clip(to: screen)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(screen)
        let target = fillRect(content: CGSize(width: screenshot.width, height: screenshot.height),
                              in: screen)
        ctx.saveGState()
        ctx.translateBy(x: target.midX, y: target.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -target.midX, y: -target.midY)
        ctx.draw(screenshot, in: target)
        ctx.restoreGState()
        ctx.restoreGState()

        // 2) destinationOut against the *filled* chrome — subtracts both chrome material and
        //    the outer transparent area of the original PNG, leaving the screenshot strictly
        //    inside the screen well.
        ctx.saveGState()
        ctx.setBlendMode(.destinationOut)
        ctx.translateBy(x: fullRect.midX, y: fullRect.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -fullRect.midX, y: -fullRect.midY)
        ctx.draw(filled, in: fullRect)
        ctx.restoreGState()

        // 3) Paint the original chrome on top (the visible bezel material).
        ctx.saveGState()
        ctx.translateBy(x: fullRect.midX, y: fullRect.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -fullRect.midX, y: -fullRect.midY)
        ctx.draw(chrome, in: fullRect)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// Mode-`fill` rect computation duplicated here so the store doesn't depend on Renderer.
    private func fillRect(content: CGSize, in rect: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0 else { return rect }
        let s = max(rect.width / content.width, rect.height / content.height)
        let w = content.width * s, h = content.height * s
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    // MARK: - Bundle loading

    /// All candidate bundles to search for resources. Tuist's `.staticFramework` places
    /// resources in a sibling `*_AIImageEditorCore.bundle` next to the framework / executable.
    /// We probe many likely locations so the same code works in app / tests / CLI / MCP.
    private static var candidateBundles: [Bundle] {
        var result: [Bundle] = []
        let framework = Bundle(for: BezelImageStore.self)
        result.append(framework)
        result.append(.main)

        // Candidate directories to look for a sibling `*_AIImageEditorCore.bundle`.
        var dirs: [URL] = [
            framework.bundleURL,
            framework.bundleURL.deletingLastPathComponent(),
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
        ]
        if let exec = Bundle.main.executableURL {
            dirs.append(exec.deletingLastPathComponent())
        }
        // CLI fallback: argv[0]'s directory (resolving symlinks).
        let argv0 = CommandLine.arguments.first ?? ""
        if !argv0.isEmpty {
            let path = (argv0 as NSString).expandingTildeInPath
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            dirs.append(resolved.deletingLastPathComponent())
        }

        var seen = Set<String>()
        for dir in dirs {
            let key = dir.path
            if !seen.insert(key).inserted { continue }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in contents where url.lastPathComponent.hasSuffix("_AIImageEditorCore.bundle") {
                if let b = Bundle(url: url) { result.append(b) }
            }
        }
        return result
    }

    private static func findResource(name: String, ext: String?, subdirectory: String?) -> URL? {
        for b in candidateBundles {
            if let u = b.url(forResource: name, withExtension: ext, subdirectory: subdirectory) { return u }
            if let u = b.url(forResource: name, withExtension: ext) { return u }
        }
        return nil
    }

    private static func loadManifest() -> [String: DeviceEntry] {
        guard let url = findResource(name: "manifest", ext: "json", subdirectory: "Bezels"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }
        var result: [String: DeviceEntry] = [:]
        for obj in raw {
            guard let id = obj["deviceId"] as? String,
                  let title = obj["title"] as? String,
                  let famStr = obj["family"] as? String,
                  let aspect = obj["aspect"] as? Double,
                  let vw = obj["viewBoxW"] as? Double,
                  let vh = obj["viewBoxH"] as? Double,
                  let colors = obj["colors"] as? [String: String]
            else { continue }
            let fam: DeviceBezel.Family = (famStr == "ipad") ? .ipad : .iphone
            // Pick a default color (preferring lighter shades for clarity).
            let order = ["Silver", "White", "Cloud white", "Light gold", "Sage", "Lavender",
                         "Mist blue", "Sky blue", "Deep blue", "Space grey", "Space black",
                         "Black", "Cosmic orange", "Default"]
            let chosen = order.first(where: { colors[$0] != nil }) ?? colors.keys.sorted().first ?? "Default"
            result[id] = DeviceEntry(id: id, title: title, family: fam,
                                     aspect: aspect, viewBoxW: vw, viewBoxH: vh,
                                     colorFiles: colors, defaultColor: chosen)
        }
        return result
    }

    private func loadImage(filename: String) -> CGImage? {
        guard let url = Self.findResource(name: filename, ext: nil, subdirectory: "Bezels") else {
            return nil
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return nil
        }
        return cg
    }

    // MARK: - Screen rect detection

    private func screenRect(for deviceId: String, image: CGImage) -> CGRect {
        let w = image.width, h = image.height
        let insets: (CGFloat, CGFloat, CGFloat, CGFloat)
        if let cached = queue.sync(execute: { insetsCache[deviceId] }) {
            insets = cached
        } else {
            insets = Self.detectScreenInsetFractions(image: image)
            queue.sync { insetsCache[deviceId] = insets }
        }
        let (l, t, r, b) = insets
        return CGRect(x: CGFloat(w) * l,
                      y: CGFloat(h) * t,
                      width:  CGFloat(w) * (1 - l - r),
                      height: CGFloat(h) * (1 - t - b))
    }

    /// Find the inner screen rectangle by scanning the chrome PNG's alpha channel. The chrome
    /// material is opaque (alpha == 255); the screen well and the area outside the device
    /// silhouette are transparent (alpha == 0). Walking outward from the centre finds the
    /// first opaque pixel in each direction — that's the inner edge of the chrome material,
    /// i.e. the boundary of the screen well.
    /// Returns insets as fractions of width/height.
    /// Returns a copy of `image` where every pixel reachable from one of the four edges by a
    /// 4-neighbour walk through transparent pixels is painted opaque white. The pixels enclosed
    /// by the chrome material (i.e. the screen well) stay untouched, so the returned image's
    /// alpha pattern is: opaque everywhere except inside the screen well.
    static func fillOuterTransparentArea(image: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        let bytesPerRow = w * 4
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let buf = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        // Any pixel with this little alpha is "outside material" for the purpose of the walk —
        // i.e. flood-fillable from the PNG edges.
        let threshold: UInt8 = 6
        var visited = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        stack.reserveCapacity(8192)

        @inline(__always) func push(_ x: Int, _ y: Int) {
            guard x >= 0, x < w, y >= 0, y < h else { return }
            let idx = y * w + x
            if visited[idx] { return }
            if buf[y * bytesPerRow + x * 4 + 3] >= threshold { return }
            visited[idx] = true
            stack.append(idx)
        }

        // Seed the stack with every edge pixel that's transparent enough.
        for x in 0..<w {
            push(x, 0)
            push(x, h - 1)
        }
        for y in 0..<h {
            push(0, y)
            push(w - 1, y)
        }

        // BFS / DFS through transparent pixels, painting them opaque white as we go.
        while let idx = stack.popLast() {
            let x = idx % w
            let y = idx / w
            let base = y * bytesPerRow + x * 4
            buf[base]     = 255
            buf[base + 1] = 255
            buf[base + 2] = 255
            buf[base + 3] = 255
            push(x + 1, y)
            push(x - 1, y)
            push(x, y + 1)
            push(x, y - 1)
        }

        return ctx.makeImage()
    }

    static func detectScreenInsetFractions(image: CGImage) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return (0.02, 0.02, 0.02, 0.02) }
        // Sample a downscaled RGBA copy for speed.
        let targetW = min(800, w)
        let scale = Double(targetW) / Double(w)
        let sw = max(2, Int(Double(w) * scale))
        let sh = max(2, Int(Double(h) * scale))
        let bytesPerRow = sw * 4
        guard let ctx = CGContext(data: nil, width: sw, height: sh,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return (0.02, 0.02, 0.02, 0.02) }
        ctx.interpolationQuality = .low
        // No fill — context is initially zeroed (alpha == 0 everywhere).
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        guard let buf = ctx.data else { return (0.02, 0.02, 0.02, 0.02) }
        let bytes = buf.assumingMemoryBound(to: UInt8.self)

        // Very low threshold — any hint of chrome material (even a 5-10% alpha edge pixel)
        // halts the walk. Higher thresholds were letting thin anti-aliased chrome edges slip
        // through, so the walk would continue past the device silhouette into the outer
        // transparent area and the resulting bounding box would reach the PNG corners.
        let opaqueThreshold: UInt8 = 12

        @inline(__always) func alpha(_ x: Int, _ y: Int) -> UInt8 {
            guard x >= 0, x < sw, y >= 0, y < sh else { return 255 }
            return bytes[y * bytesPerRow + x * 4 + 3]
        }
        @inline(__always) func isTransparent(_ x: Int, _ y: Int) -> Bool {
            alpha(x, y) < opaqueThreshold
        }

        // Walk outward from the centre. If a walk reaches the image edge without hitting
        // chrome material, treat the sample as invalid — that direction never bumped against
        // a real device boundary, so its extent is meaningless.
        func extentAlongRow(yFrac: Double) -> (Int, Int)? {
            let y = Int(Double(sh) * yFrac)
            let cx = sw / 2
            guard isTransparent(cx, y) else { return nil }
            var left = cx
            while left > 0 && isTransparent(left - 1, y) { left -= 1 }
            var right = cx
            while right < sw - 1 && isTransparent(right + 1, y) { right += 1 }
            if left == 0 || right == sw - 1 { return nil }
            return (left, right)
        }
        func extentAlongCol(xFrac: Double) -> (Int, Int)? {
            let x = Int(Double(sw) * xFrac)
            let cy = sh / 2
            guard isTransparent(x, cy) else { return nil }
            var top = cy
            while top > 0 && isTransparent(x, top - 1) { top -= 1 }
            var bottom = cy
            while bottom < sh - 1 && isTransparent(x, bottom + 1) { bottom += 1 }
            if top == 0 || bottom == sh - 1 { return nil }
            return (top, bottom)
        }

        // We want the *bounding box* of the connected screen-well transparent region — the
        // union of every column/row's transparent extent. Centre-symmetric devices have the
        // largest reach at the centre column/row (Dynamic Island cutouts aside), and the
        // smallest reach at the rounded corners. Taking the union pushes the bounding box
        // out to the screen well's true edge. Cutouts inside the well (DI, camera dots) are
        // handled correctly because the chrome's `destinationOut` step carves them back out.
        let yFracs = stride(from: 0.30, through: 0.70, by: 0.05).map { Double($0) }
        let xFracs = stride(from: 0.30, through: 0.70, by: 0.05).map { Double($0) }
        let rowSamples = yFracs.compactMap { extentAlongRow(yFrac: $0) }
        let colSamples = xFracs.compactMap { extentAlongCol(xFrac: $0) }

        guard let xMin = rowSamples.map(\.0).min(),
              let xMax = rowSamples.map(\.1).max(),
              let yMin = colSamples.map(\.0).min(),
              let yMax = colSamples.map(\.1).max(),
              xMax > xMin, yMax > yMin else {
            return (0.02, 0.02, 0.02, 0.02)
        }

        let left   = CGFloat(xMin) / CGFloat(sw)
        let right  = CGFloat(sw - 1 - xMax) / CGFloat(sw)
        let top    = CGFloat(yMin) / CGFloat(sh)
        let bottom = CGFloat(sh - 1 - yMax) / CGFloat(sh)
        return (left, top, right, bottom)
    }
}
