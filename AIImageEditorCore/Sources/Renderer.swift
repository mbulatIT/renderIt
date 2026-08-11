import Foundation
import CoreGraphics
import CoreImage
import CoreText
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Renders a Document to a CGImage / PNG. The renderer is pure: it doesn't touch
/// global state, it only reads the document plus assets from disk.
public struct Renderer {
    /// Directory used to resolve relative asset paths. Pass the directory of the .aiproj file.
    public let baseDirectory: URL?

    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
    }

    /// What the renderer should produce.
    public enum Mode: Sendable {
        /// Full page work area, with each preview's background painted inside its rect and
        /// everything *outside* the preview rects dimmed to 50% alpha. Used by the editor canvas.
        case editor
        /// Same as `.editor` but without the dimming — useful for previewing the export visually.
        case export
    }

    public func renderCGImage(_ document: Document, scale: Int = 1, pageId: String? = nil, mode: Mode = .editor) throws -> CGImage {
        try renderCGImage(document, pixelScale: CGFloat(scale), pageId: pageId, mode: mode)
    }

    /// Fractional-scale variant. `pixelScale` may be < 1 to render the canvas at a *fraction*
    /// of its pixel size — used by the editor canvas to render at the on-screen zoom resolution
    /// instead of always rasterizing the full work-area canvas. The integer `scale` overload
    /// (used by export/CLI/MCP for @2x/@3x) delegates here with `CGFloat(scale)`, so their
    /// behaviour is unchanged.
    public func renderCGImage(_ document: Document, pixelScale: CGFloat, pageId: String? = nil, mode: Mode = .editor) throws -> CGImage {
        let page: Page
        if let pid = pageId, let p = document.page(id: pid) { page = p } else { page = document.activePage }
        return try renderPage(page: page, assets: document.assets, pixelScale: pixelScale, mode: mode)
    }

    public func renderPage(page: Page, assets: [String: Asset], scale: Int = 1, mode: Mode = .editor) throws -> CGImage {
        try renderPage(page: page, assets: assets, pixelScale: CGFloat(scale), mode: mode)
    }

    public func renderPage(page: Page, assets: [String: Asset], pixelScale: CGFloat, mode: Mode = .editor) throws -> CGImage {
        let s = max(0.01, pixelScale)
        let w = max(1, Int((Double(page.canvas.width) * Double(s)).rounded()))
        let h = max(1, Int((Double(page.canvas.height) * Double(s)).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw EditorError.renderFailed("could not allocate CGContext (\(w)x\(h))")
        }

        // Move to top-left origin so that Document coordinates map directly. Blur radii and
        // strokes self-scale because the renderer derives device sizes from the CTM, so a
        // fractional pixelScale stays visually consistent with a full-size render.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: s, y: -s)

        // 1) Canvas background — usually transparent so the gaps between previews show
        //    through as the editor's checkerboard.
        let bg = page.canvas.background
        if bg.a > 0 {
            ctx.setFillColor(bg.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: page.canvas.width, height: page.canvas.height))
        }

        // 2) Each preview's background fills its rectangle on the canvas.
        for preview in page.previews where preview.background.a > 0 {
            ctx.setFillColor(preview.background.cgColor)
            ctx.fill(preview.frame.cgRect)
        }

        // 3) Layers — drawn normally over preview backgrounds.
        for layer in page.renderOrder where layer.visible {
            dispatchLayer(layer, in: ctx, assets: assets)
        }

        // 4) Editor decoration: dim everything *outside* any preview rectangle to 50% alpha.
        //    Two-pass destinationIn doesn't work (both passes hit the inside-preview pixels),
        //    so instead we clip to "canvas ∖ ⋃ previews" with the even-odd rule and apply a
        //    single destinationIn fill at α=0.5. Pixels inside previews aren't in the clip,
        //    so their alpha is never touched and the solid preview backgrounds stay solid.
        if mode == .editor, !page.previews.isEmpty {
            let canvasRect = CGRect(x: 0, y: 0, width: page.canvas.width, height: page.canvas.height)
            ctx.saveGState()
            let path = CGMutablePath()
            path.addRect(canvasRect)
            for preview in page.previews { path.addRect(preview.frame.cgRect) }
            ctx.addPath(path)
            ctx.clip(using: .evenOdd)
            ctx.setBlendMode(.destinationIn)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.5))
            ctx.fill(canvasRect)
            ctx.restoreGState()
        }

        guard let cg = ctx.makeImage() else {
            throw EditorError.renderFailed("failed to finalize CGImage")
        }
        return cg
    }

    /// Render a single preview as a standalone image at its native frame size. Used by export
    /// to produce one PNG per preview. Layers are drawn in the page's coordinate system but
    /// clipped to the preview's rectangle.
    public func renderPreview(page: Page, previewId: String, assets: [String: Asset], scale: Int = 1) throws -> CGImage {
        guard let preview = page.preview(id: previewId) else {
            throw EditorError.renderFailed("preview not found: \(previewId)")
        }
        let pw = max(1, Int(preview.frame.w.rounded()) * scale)
        let ph = max(1, Int(preview.frame.h.rounded()) * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil,
                                  width: pw,
                                  height: ph,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw EditorError.renderFailed("could not allocate CGContext (\(pw)x\(ph))")
        }

        // Top-left origin, then translate so the preview's origin maps to (0,0) in user space.
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        ctx.translateBy(x: -CGFloat(preview.frame.x), y: -CGFloat(preview.frame.y))

        // Preview background.
        if preview.background.a > 0 {
            ctx.setFillColor(preview.background.cgColor)
            ctx.fill(preview.frame.cgRect)
        }

        // Clip subsequent drawing to the preview rect so layers outside don't render at all.
        ctx.clip(to: preview.frame.cgRect)

        for layer in page.renderOrder where layer.visible {
            dispatchLayer(layer, in: ctx, assets: assets)
        }

        guard let cg = ctx.makeImage() else {
            throw EditorError.renderFailed("failed to finalize preview CGImage")
        }
        return cg
    }

    /// Convenience: encode a single preview as PNG.
    public func renderPreviewPNG(_ document: Document, pageId: String? = nil, previewId: String, scale: Int = 1) throws -> Data {
        let page: Page
        if let pid = pageId, let p = document.page(id: pid) { page = p } else { page = document.activePage }
        let cg = try renderPreview(page: page, previewId: previewId, assets: document.assets, scale: scale)
        guard let out = CFDataCreateMutable(nil, 0),
              let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { throw EditorError.renderFailed("could not create PNG destination") }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw EditorError.renderFailed("PNG finalize failed") }
        return out as Data
    }

    public func renderNSImage(_ document: Document, scale: Int = 1, pageId: String? = nil, mode: Mode = .editor) throws -> NSImage {
        let cg = try renderCGImage(document, scale: scale, pageId: pageId, mode: mode)
        let page: Page
        if let pid = pageId, let p = document.page(id: pid) { page = p } else { page = document.activePage }
        let img = NSImage(size: NSSize(width: page.canvas.width, height: page.canvas.height))
        img.addRepresentation(NSBitmapImageRep(cgImage: cg))
        return img
    }

    public func renderPNG(_ document: Document, scale: Int = 1, pageId: String? = nil, mode: Mode = .export) throws -> Data {
        let cg = try renderCGImage(document, scale: scale, pageId: pageId, mode: mode)
        guard let out = CFDataCreateMutable(nil, 0),
              let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { throw EditorError.renderFailed("could not create PNG destination") }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw EditorError.renderFailed("PNG finalize failed")
        }
        return out as Data
    }

    // MARK: - Layer dispatch

    /// Top-level layer dispatcher. Handles two special cases:
    ///   - **blur**: ignores rotation/blend so it can sample the existing bitmap in axis-aligned
    ///     device space.
    ///   - **shadow + corner radius on non-shape layers**: routed through a transparency layer
    ///     so the drop shadow wraps the rounded silhouette instead of being clipped by it.
    private func dispatchLayer(_ layer: Layer, in ctx: CGContext, assets: [String: Asset]) {
        if case .blur(let p) = layer.payload {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(max(0, min(1, layer.opacity))))
            paintBackground(layer: layer, ctx: ctx)
            drawBlur(payload: p, frame: layer.frame, cornerRadius: layer.cornerRadius, cornerStyle: layer.cornerStyle, corners: layer.roundedCorners, ctx: ctx)
            ctx.restoreGState()
            return
        }
        ctx.saveGState()
        applyTransform(ctx: ctx, layer: layer)
        ctx.setAlpha(CGFloat(max(0, min(1, layer.opacity))))
        ctx.setBlendMode(cgBlendMode(layer.blendMode))

        // Clip to the layer's frame path when a corner radius asks for it, OR when a group
        // opts into cropping its children to its bounds. `applyCornerClip` builds a plain
        // rectangle when `cornerRadius == 0`, so a crop-to-bounds group with no rounding still
        // clips to its frame rectangle.
        let needsAutoClip = (layer.cornerRadius > 0 && payloadNeedsAutoClip(layer.payload))
            || groupClipsToBounds(layer.payload)
        let hasShadow = layer.shadow != nil
        let hasGradientFill = layer.gradient != nil && payloadAcceptsGradientFill(layer.payload)

        // We need a transparency-layer composite when:
        //  - shadow must wrap a rounded silhouette (otherwise it gets clipped), OR
        //  - we're going to mask a gradient onto the layer's pixels.
        let useOuterTransparency = hasGradientFill || (needsAutoClip && hasShadow)

        if useOuterTransparency {
            if hasShadow { applyShadow(ctx: ctx, layer: layer) }
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.saveGState()
            if needsAutoClip { applyCornerClip(ctx: ctx, layer: layer) }
            // Background paints first so the layer's main content (and any gradient fill mask)
            // composites on top of it.
            paintBackground(layer: layer, ctx: ctx)
            if hasGradientFill, let g = layer.gradient {
                // Inner transparency layer: draw the silhouette in its natural color, then paint
                // the gradient with `sourceIn` so it only fills wherever the layer drew pixels.
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                drawLayer(layer, in: ctx, assets: assets)
                ctx.setBlendMode(.sourceIn)
                drawGradient(payload: g, frame: layer.frame, cornerRadius: 0, ctx: ctx)
                ctx.endTransparencyLayer()
            } else {
                drawLayer(layer, in: ctx, assets: assets)
            }
            ctx.restoreGState()
            ctx.endTransparencyLayer()
        } else {
            if hasShadow  { applyShadow(ctx: ctx, layer: layer) }
            if needsAutoClip { applyCornerClip(ctx: ctx, layer: layer) }
            paintBackground(layer: layer, ctx: ctx)
            drawLayer(layer, in: ctx, assets: assets)
        }
        ctx.restoreGState()
    }

    /// Whether the layer-level gradient fill is a meaningful effect for this payload. Skipped
    /// on blur (sampler), deviceBezel (defines its own colors), and the standalone .gradient
    /// kind (already a gradient).
    private func payloadAcceptsGradientFill(_ p: LayerPayload) -> Bool {
        switch p {
        case .blur, .deviceBezel, .gradient: return false
        case .image, .text, .rect, .ellipse, .line, .polygon, .star, .group: return true
        }
    }

    /// Whether the renderer should clip this layer's drawing to a rounded-rect mask matching
    /// its frame. `rect`/`gradient`/`blur` bake the corner radius into their own path, so we
    /// don't double-apply. `ellipse` and `deviceBezel` define their own shape and ignore the
    /// field.
    private func payloadNeedsAutoClip(_ p: LayerPayload) -> Bool {
        switch p {
        case .rect, .gradient, .blur, .ellipse, .deviceBezel:
            return false
        case .image, .text, .line, .polygon, .star, .group:
            return true
        }
    }

    /// Whether a group opts to crop its children to its frame bounds even without a corner
    /// radius. Only `group` layers carry this flag; every other kind returns false.
    private func groupClipsToBounds(_ p: LayerPayload) -> Bool {
        if case .group(let g) = p { return g.clipsToBounds }
        return false
    }

    private func applyCornerClip(ctx: CGContext, layer: Layer) {
        let path = Self.roundedRectPath(rect: layer.frame.cgRect,
                                        cornerRadius: CGFloat(layer.cornerRadius),
                                        style: layer.cornerStyle,
                                        corners: layer.roundedCorners)
        ctx.addPath(path)
        ctx.clip()
    }

    /// Build a path that rounds the given rect's corners according to `style`. Only the corners in
    /// `corners` are rounded; the rest stay square. Returns the plain rect when the radius is zero
    /// or no corners are selected.
    static func roundedRectPath(rect: CGRect, cornerRadius: CGFloat, style: CornerStyle,
                                corners: RectCorners = .all) -> CGPath {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        guard r > 0, !corners.isEmpty else { return CGPath(rect: rect, transform: nil) }
        switch style {
        case .arc:
            return arcCornerRectPath(rect: rect, radius: r, corners: corners)
        case .continuous:
            return continuousRoundedRectPath(rect: rect, radius: r, corners: corners)
        case .cut:
            return cutCornerRectPath(rect: rect, cornerSize: r, corners: corners)
        }
    }

    /// True quarter-circle corners. Built manually with `CGPath.addArc` instead of
    /// `CGPath(roundedRect:cornerWidth:cornerHeight:)` because the latter is documented as an
    /// "elliptical arc" approximation and can look subtly off at large radii. `addArc` uses
    /// CG's optimized arc primitive, which renders a clean circular arc at every size. A corner
    /// not in `corners` gets a zero inset, i.e. a square vertex.
    private static func arcCornerRectPath(rect: CGRect, radius: CGFloat, corners: RectCorners) -> CGPath {
        let l = rect.minX, t = rect.minY, R = rect.maxX, b = rect.maxY
        let tl = corners.contains(.topLeft)     ? radius : 0
        let tr = corners.contains(.topRight)    ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        let bl = corners.contains(.bottomLeft)  ? radius : 0
        let p = CGMutablePath()
        p.move(to: CGPoint(x: l + tl, y: t))
        p.addLine(to: CGPoint(x: R - tr, y: t))
        if tr > 0 { p.addArc(center: CGPoint(x: R - tr, y: t + tr), radius: tr,
                             startAngle: -.pi / 2, endAngle: 0, clockwise: false) }
        p.addLine(to: CGPoint(x: R, y: b - br))
        if br > 0 { p.addArc(center: CGPoint(x: R - br, y: b - br), radius: br,
                             startAngle: 0, endAngle: .pi / 2, clockwise: false) }
        p.addLine(to: CGPoint(x: l + bl, y: b))
        if bl > 0 { p.addArc(center: CGPoint(x: l + bl, y: b - bl), radius: bl,
                             startAngle: .pi / 2, endAngle: .pi, clockwise: false) }
        p.addLine(to: CGPoint(x: l, y: t + tl))
        if tl > 0 { p.addArc(center: CGPoint(x: l + tl, y: t + tl), radius: tl,
                             startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false) }
        p.closeSubpath()
        return p
    }

    /// iOS-style "squircle" rounded rectangle — corners extend further into the adjacent edges
    /// than a quarter-circle, with cubic Béziers chosen to read as a smooth continuous curve.
    /// Not a pixel-perfect match for `UIBezierPath`'s `.continuous` (which uses ~5 Béziers per
    /// corner), but visually distinct from `.arc`. Corners not in `corners` stay square.
    private static func continuousRoundedRectPath(rect: CGRect, radius: CGFloat, corners: RectCorners) -> CGPath {
        let reach = min(radius * 1.528665, min(rect.width, rect.height) / 2)
        let control = reach * 0.5            // cubic control offset along the edge tangent
        let l = rect.minX, t = rect.minY, ri = rect.maxX, b = rect.maxY
        let tl = corners.contains(.topLeft)     ? reach : 0
        let tr = corners.contains(.topRight)    ? reach : 0
        let br = corners.contains(.bottomRight) ? reach : 0
        let bl = corners.contains(.bottomLeft)  ? reach : 0
        let p = CGMutablePath()
        p.move(to: CGPoint(x: l + tl, y: t))
        p.addLine(to: CGPoint(x: ri - tr, y: t))
        if tr > 0 { p.addCurve(to: CGPoint(x: ri, y: t + tr),
                               control1: CGPoint(x: ri - control, y: t),
                               control2: CGPoint(x: ri, y: t + control)) }
        p.addLine(to: CGPoint(x: ri, y: b - br))
        if br > 0 { p.addCurve(to: CGPoint(x: ri - br, y: b),
                               control1: CGPoint(x: ri, y: b - control),
                               control2: CGPoint(x: ri - control, y: b)) }
        p.addLine(to: CGPoint(x: l + bl, y: b))
        if bl > 0 { p.addCurve(to: CGPoint(x: l, y: b - bl),
                               control1: CGPoint(x: l + control, y: b),
                               control2: CGPoint(x: l, y: b - control)) }
        p.addLine(to: CGPoint(x: l, y: t + tl))
        if tl > 0 { p.addCurve(to: CGPoint(x: l + tl, y: t),
                               control1: CGPoint(x: l, y: t + control),
                               control2: CGPoint(x: l + control, y: t)) }
        p.closeSubpath()
        return p
    }

    /// Octagonal rectangle with 45° chamfered corners — straight diagonals where the rounded
    /// arc would be. `cornerSize` is the chamfer leg length, matching the `cornerRadius` field.
    /// Corners not in `corners` stay square.
    private static func cutCornerRectPath(rect: CGRect, cornerSize: CGFloat, corners: RectCorners) -> CGPath {
        let r = min(cornerSize, min(rect.width, rect.height) / 2)
        let l = rect.minX, t = rect.minY, ri = rect.maxX, b = rect.maxY
        let tl = corners.contains(.topLeft)     ? r : 0
        let tr = corners.contains(.topRight)    ? r : 0
        let br = corners.contains(.bottomRight) ? r : 0
        let bl = corners.contains(.bottomLeft)  ? r : 0
        let p = CGMutablePath()
        p.move(to: CGPoint(x: l + tl, y: t))
        p.addLine(to: CGPoint(x: ri - tr, y: t))
        if tr > 0 { p.addLine(to: CGPoint(x: ri, y: t + tr)) }
        p.addLine(to: CGPoint(x: ri, y: b - br))
        if br > 0 { p.addLine(to: CGPoint(x: ri - br, y: b)) }
        p.addLine(to: CGPoint(x: l + bl, y: b))
        if bl > 0 { p.addLine(to: CGPoint(x: l, y: b - bl)) }
        p.addLine(to: CGPoint(x: l, y: t + tl))
        if tl > 0 { p.addLine(to: CGPoint(x: l + tl, y: t)) }
        p.closeSubpath()
        return p
    }

    /// Paint a layer's optional background (solid colour or gradient) within its frame,
    /// clipped to the corner-radius path. Called before the layer draws its own content so
    /// the payload renders on top.
    private func paintBackground(layer: Layer, ctx: CGContext) {
        guard let bg = layer.background else { return }
        let rect = layer.frame.cgRect
        ctx.saveGState()
        if layer.cornerRadius > 0 {
            let path = Self.roundedRectPath(rect: rect,
                                            cornerRadius: CGFloat(layer.cornerRadius),
                                            style: layer.cornerStyle,
                                            corners: layer.roundedCorners)
            ctx.addPath(path)
            ctx.clip()
        }
        switch bg {
        case .color(let c):
            ctx.setFillColor(c.cgColor)
            ctx.fill(rect)
        case .gradient(let g):
            // cornerRadius=0 here — we already clipped above.
            drawGradient(payload: g, frame: layer.frame, cornerRadius: 0, ctx: ctx)
        }
        ctx.restoreGState()
    }

    /// Apply the layer-level drop shadow to the context. The shadow attaches to the next draw
    /// calls (fill/stroke/text/image). The y offset is negated because our outer CTM flips y.
    private func applyShadow(ctx: CGContext, layer: Layer) {
        guard let s = layer.shadow else { return }
        let offset = CGSize(width: CGFloat(s.offsetX), height: -CGFloat(s.offsetY))
        ctx.setShadow(offset: offset, blur: CGFloat(max(0, s.blur)), color: s.color.cgColor)
    }

    private func applyTransform(ctx: CGContext, layer: Layer) {
        let (cx, cy) = layer.frame.center
        if layer.rotation != 0 {
            ctx.translateBy(x: CGFloat(cx), y: CGFloat(cy))
            ctx.rotate(by: CGFloat(layer.rotation) * .pi / 180)
            ctx.translateBy(x: -CGFloat(cx), y: -CGFloat(cy))
        }
    }

    private func cgBlendMode(_ mode: BlendMode) -> CGBlendMode {
        switch mode {
        case .normal:    return .normal
        case .multiply:  return .multiply
        case .screen:    return .screen
        case .overlay:   return .overlay
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .darken:    return .darken
        case .lighten:   return .lighten
        }
    }

    private func drawLayer(_ layer: Layer, in ctx: CGContext, assets: [String: Asset]) {
        switch layer.payload {
        case .image(let p):
            drawImage(payload: p, frame: layer.frame, ctx: ctx, assets: assets)
        case .text(let p):
            drawText(payload: p, frame: layer.frame, ctx: ctx)
        case .rect(let p):
            drawShape(payload: p, frame: layer.frame, cornerRadius: layer.cornerRadius,
                      cornerStyle: layer.cornerStyle, corners: layer.roundedCorners, ctx: ctx, ellipse: false)
        case .ellipse(let p):
            drawShape(payload: p, frame: layer.frame, cornerRadius: 0,
                      cornerStyle: .arc, ctx: ctx, ellipse: true)
        case .deviceBezel(let p):
            drawDeviceBezel(payload: p, frame: layer.frame, ctx: ctx, assets: assets)
        case .gradient(let p):
            drawGradient(payload: p, frame: layer.frame, cornerRadius: layer.cornerRadius,
                         cornerStyle: layer.cornerStyle, corners: layer.roundedCorners, ctx: ctx)
        case .blur(let p):
            // Reached only when a blur sits inside a group. Caveat: when nested in a transformed
            // group the sample rect won't perfectly track the group's rotation.
            drawBlur(payload: p, frame: layer.frame, cornerRadius: layer.cornerRadius,
                     cornerStyle: layer.cornerStyle, corners: layer.roundedCorners, ctx: ctx)
        case .line(let p):
            drawLine(payload: p, frame: layer.frame, ctx: ctx)
        case .polygon(let p):
            drawPolygon(payload: p, frame: layer.frame, ctx: ctx)
        case .star(let p):
            drawStar(payload: p, frame: layer.frame, ctx: ctx)
        case .group(let g):
            for child in g.children where child.visible {
                dispatchLayer(child, in: ctx, assets: assets)
            }
        }
    }

    // MARK: - Image

    private func drawImage(payload: ImageLayerPayload, frame: Frame, ctx: CGContext, assets: [String: Asset]) {
        guard let cg = loadImage(assetId: payload.assetId, assets: assets) else { return }
        let rect = frame.cgRect
        let target = computeFit(content: CGSize(width: cg.width, height: cg.height),
                                in: rect, mode: payload.contentMode)
        ctx.saveGState()
        ctx.translateBy(x: target.midX, y: target.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -target.midX, y: -target.midY)
        ctx.draw(cg, in: target)
        ctx.restoreGState()
    }

    private func computeFit(content: CGSize, in rect: CGRect, mode: ContentMode) -> CGRect {
        guard content.width > 0, content.height > 0 else { return rect }
        switch mode {
        case .stretch:
            return rect
        case .fit:
            let s = min(rect.width / content.width, rect.height / content.height)
            let w = content.width * s, h = content.height * s
            return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        case .fill:
            let s = max(rect.width / content.width, rect.height / content.height)
            let w = content.width * s, h = content.height * s
            return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        }
    }

    private func loadImage(assetId: String, assets: [String: Asset]) -> CGImage? {
        guard let asset = assets[assetId], let url = resolveAssetURL(asset) else { return nil }
        return CGImageCache.shared.image(at: url)
    }

    /// Public so the bezel composite cache key can use the same absolute URL we'd actually load.
    public func resolveAssetURL(_ asset: Asset) -> URL? {
        if (asset.path as NSString).isAbsolutePath {
            return URL(fileURLWithPath: asset.path)
        } else if let base = baseDirectory {
            return base.appendingPathComponent(asset.path)
        }
        return URL(fileURLWithPath: asset.path)
    }

    // MARK: - Text

    private func drawText(payload: TextLayerPayload, frame: Frame, ctx: CGContext) {
        let nsFont = resolveFont(family: payload.font, size: payload.fontSize,
                                 weight: payload.fontWeight, italic: payload.italic)
        let para = NSMutableParagraphStyle()
        switch payload.alignment {
        case .left:      para.alignment = .left
        case .center:    para.alignment = .center
        case .right:     para.alignment = .right
        case .justified: para.alignment = .justified
        }
        para.lineSpacing = CGFloat(payload.lineSpacing)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: NSColor(cgColor: payload.color.cgColor) ?? .white,
            .paragraphStyle: para,
            .kern: payload.kerning,
        ]
        let attributed = NSAttributedString(string: payload.text, attributes: attrs)

        // Draw via NSGraphicsContext so AppKit text rendering works in our flipped CG context.
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        attributed.draw(with: frame.cgRect,
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func resolveFont(family: String, size: Double, weight: FontWeight, italic: Bool) -> NSFont {
        let nsWeight = mapWeight(weight)
        let traits = italic ? NSFontDescriptor.SymbolicTraits.italic : []
        if let desc = NSFontManager.shared.font(withFamily: family,
                                                traits: NSFontTraitMask(rawValue: italic ? NSFontTraitMask.italicFontMask.rawValue : 0),
                                                weight: weightToManagerWeight(weight),
                                                size: CGFloat(size)) {
            return desc
        }
        // Fallback to system font
        let base = NSFont.systemFont(ofSize: CGFloat(size), weight: nsWeight)
        if italic {
            let desc = base.fontDescriptor.withSymbolicTraits(traits)
            if let f = NSFont(descriptor: desc, size: CGFloat(size)) { return f }
        }
        return base
    }

    private func mapWeight(_ w: FontWeight) -> NSFont.Weight {
        switch w {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .regular:    return .regular
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        }
    }

    private func weightToManagerWeight(_ w: FontWeight) -> Int {
        // NSFontManager weights: 1 (lightest) ... 14 (heaviest)
        switch w {
        case .ultraLight: return 2
        case .thin:       return 3
        case .light:      return 4
        case .regular:    return 5
        case .medium:     return 6
        case .semibold:   return 8
        case .bold:       return 9
        case .heavy:      return 11
        case .black:      return 13
        }
    }

    // MARK: - Shape

    private func drawShape(payload: ShapeLayerPayload, frame: Frame, cornerRadius: Double, cornerStyle: CornerStyle, corners: RectCorners = .all, ctx: CGContext, ellipse: Bool) {
        let rect = frame.cgRect
        let path: CGPath
        if ellipse {
            path = CGPath(ellipseIn: rect, transform: nil)
        } else {
            path = Self.roundedRectPath(rect: rect,
                                        cornerRadius: CGFloat(cornerRadius),
                                        style: cornerStyle,
                                        corners: corners)
        }
        ctx.setFillColor(payload.fill.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        if let s = payload.stroke, s.width > 0 {
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(CGFloat(s.width))
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    // MARK: - Device bezel

    private func drawDeviceBezel(payload: DeviceBezelPayload, frame: Frame, ctx: CGContext, assets: [String: Asset]) {
        guard let bezel = DeviceBezelCatalog.find(id: payload.device) else { return }
        let outer = frame.cgRect

        switch bezel.source {
        case .imageBacked:
            drawImageBackedBezel(payload: payload, outer: outer, ctx: ctx, assets: assets)
        case .programmatic(let chromeColor, let cornerFraction, let screenRect, let decorate):
            drawProgrammaticBezel(payload: payload, outer: outer, chromeColor: chromeColor,
                                  cornerFraction: cornerFraction, screenRect: screenRect,
                                  decorate: decorate, ctx: ctx, assets: assets)
        }
    }

    private func drawImageBackedBezel(payload: DeviceBezelPayload,
                                      outer: CGRect,
                                      ctx: CGContext,
                                      assets: [String: Asset]) {
        // Resolve the screenshot URL (cached separately) so the composite can be keyed by it.
        let screenshotURL: URL? = {
            guard let aid = payload.screenshotAssetId,
                  let asset = assets[aid] else { return nil }
            return resolveAssetURL(asset)
        }()
        guard let composite = BezelImageStore.shared.composedBezelImage(
                deviceId: payload.device,
                color: payload.color,
                screenshotURL: screenshotURL)
        else { return }

        ctx.saveGState()
        ctx.translateBy(x: outer.midX, y: outer.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -outer.midX, y: -outer.midY)
        ctx.draw(composite, in: outer)
        ctx.restoreGState()
    }

    private func drawProgrammaticBezel(payload: DeviceBezelPayload,
                                       outer: CGRect,
                                       chromeColor: Color,
                                       cornerFraction: Double,
                                       screenRect: (CGRect) -> CGRect,
                                       decorate: (CGContext, CGRect) -> Void,
                                       ctx: CGContext,
                                       assets: [String: Asset]) {
        let chrome = (payload.chromeColor ?? chromeColor).cgColor
        let corner = outer.width * CGFloat(cornerFraction)
        let bezelPath = CGPath(roundedRect: outer,
                               cornerWidth: corner,
                               cornerHeight: corner,
                               transform: nil)
        ctx.setFillColor(chrome)
        ctx.addPath(bezelPath)
        ctx.fillPath()

        ctx.setStrokeColor(CGColor(srgbRed: 0.25, green: 0.25, blue: 0.28, alpha: 1))
        ctx.setLineWidth(max(1, outer.width * 0.002))
        ctx.addPath(bezelPath)
        ctx.strokePath()

        let screen = screenRect(outer)
        let screenCorner = corner * 0.78
        let screenPath = CGPath(roundedRect: screen,
                                cornerWidth: screenCorner,
                                cornerHeight: screenCorner,
                                transform: nil)

        ctx.saveGState()
        ctx.addPath(screenPath)
        ctx.clip()
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(screen)
        if let assetId = payload.screenshotAssetId,
           let cg = loadImage(assetId: assetId, assets: assets) {
            let target = computeFit(content: CGSize(width: cg.width, height: cg.height),
                                    in: screen, mode: .fill)
            ctx.saveGState()
            ctx.translateBy(x: target.midX, y: target.midY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: -target.midX, y: -target.midY)
            ctx.draw(cg, in: target)
            ctx.restoreGState()
        }
        ctx.restoreGState()

        decorate(ctx, outer)
    }

    // MARK: - Gradient

    private func drawGradient(payload: GradientLayerPayload, frame: Frame, cornerRadius: Double, cornerStyle: CornerStyle = .arc, corners: RectCorners = .all, ctx: CGContext) {
        let rect = frame.cgRect
        guard !payload.stops.isEmpty,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }

        // CGGradient needs ascending locations; sort defensively.
        let sorted = payload.stops.sorted(by: { $0.at < $1.at })
        let colors = sorted.map { $0.color.cgColor } as CFArray
        let locations = sorted.map { CGFloat(max(0, min(1, $0.at))) }
        guard let gradient = CGGradient(colorsSpace: space,
                                        colors: colors,
                                        locations: locations) else { return }

        let path = Self.roundedRectPath(rect: rect,
                                        cornerRadius: CGFloat(cornerRadius),
                                        style: cornerStyle,
                                        corners: corners)

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        let start = CGPoint(x: rect.minX + CGFloat(payload.startX) * rect.width,
                            y: rect.minY + CGFloat(payload.startY) * rect.height)
        let end = CGPoint(x: rect.minX + CGFloat(payload.endX) * rect.width,
                          y: rect.minY + CGFloat(payload.endY) * rect.height)

        switch payload.type {
        case .linear:
            ctx.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .radial:
            let radius = hypot(end.x - start.x, end.y - start.y)
            ctx.drawRadialGradient(gradient,
                                   startCenter: start, startRadius: 0,
                                   endCenter: start, endRadius: max(0.5, radius),
                                   options: [.drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }

    // MARK: - Blur

    /// Lazy-shared CIContext. CIContext is expensive to create per-draw, so we keep one alive
    /// across blur layers within a process.
    private static let ciContext: CIContext = {
        if let space = CGColorSpace(name: CGColorSpace.sRGB) {
            return CIContext(options: [.workingColorSpace: space])
        }
        return CIContext()
    }()

    private func drawBlur(payload: BlurLayerPayload, frame: Frame, cornerRadius: Double, cornerStyle: CornerStyle = .arc, corners: RectCorners = .all, ctx: CGContext) {
        // Variable-radius gradient blur path: when stops are provided, the radius varies across
        // the frame via CIMaskedVariableBlur.
        if let stops = payload.stops, stops.count >= 2 {
            drawGradientBlur(payload: payload, stops: stops, frame: frame,
                             cornerRadius: cornerRadius, cornerStyle: cornerStyle, corners: corners, ctx: ctx)
            return
        }
        guard payload.radius > 0 else {
            // No blur — just paint the tint if any, optionally with rounded corners.
            drawBlurTintOnly(payload: payload, frame: frame, cornerRadius: cornerRadius, cornerStyle: cornerStyle, corners: corners, ctx: ctx)
            return
        }
        guard let snap = ctx.makeImage() else { return }

        let userRect = frame.cgRect
        let xform = ctx.userSpaceToDeviceSpaceTransform
        let deviceRect = userRect.applying(xform).standardized

        let snapBounds = CGRect(x: 0, y: 0, width: snap.width, height: snap.height)
        let cropRect = deviceRect.integral.intersection(snapBounds)
        guard !cropRect.isEmpty, cropRect.width >= 1, cropRect.height >= 1,
              let cropped = snap.cropping(to: cropRect) else { return }

        // Device-space blur radius — accounts for the renderer's pixel scale.
        let pxScale = max(abs(xform.a), abs(xform.d))
        let pxRadius = max(0.5, payload.radius * Double(pxScale))

        let source = CIImage(cgImage: cropped)
        let blurred = source.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: pxRadius])
            .cropped(to: source.extent)
        guard let blurredCG = Self.ciContext.createCGImage(blurred, from: blurred.extent) else { return }

        let inverse = xform.inverted()
        let visibleUserRect = cropRect.applying(inverse).standardized

        ctx.saveGState()
        if cornerRadius > 0 {
            let clipPath = Self.roundedRectPath(rect: userRect,
                                                cornerRadius: CGFloat(cornerRadius),
                                                style: cornerStyle,
                                                corners: corners)
            ctx.addPath(clipPath)
            ctx.clip()
        }
        // Local y-flip so the captured bitmap draws right-side-up under the outer flipped CTM.
        ctx.saveGState()
        ctx.translateBy(x: visibleUserRect.midX, y: visibleUserRect.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -visibleUserRect.midX, y: -visibleUserRect.midY)
        ctx.draw(blurredCG, in: visibleUserRect)
        ctx.restoreGState()

        if let tint = payload.tint, tint.a > 0 {
            ctx.setFillColor(tint.cgColor)
            ctx.fill(userRect)
        }
        ctx.restoreGState()
    }

    // MARK: - Line / Polygon / Star

    private func drawLine(payload: LineLayerPayload, frame: Frame, ctx: CGContext) {
        let rect = frame.cgRect
        let start = CGPoint(x: rect.minX + CGFloat(payload.startX) * rect.width,
                            y: rect.minY + CGFloat(payload.startY) * rect.height)
        let end = CGPoint(x: rect.minX + CGFloat(payload.endX) * rect.width,
                          y: rect.minY + CGFloat(payload.endY) * rect.height)
        let width = max(0.5, CGFloat(payload.width))

        ctx.saveGState()
        ctx.setStrokeColor(payload.color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        let arrowSize = CGFloat(max(0, payload.arrowSize)) * width
        if payload.startArrow {
            drawArrowhead(at: start, from: end, color: payload.color, size: arrowSize, ctx: ctx)
        }
        if payload.endArrow {
            drawArrowhead(at: end, from: start, color: payload.color, size: arrowSize, ctx: ctx)
        }
        ctx.restoreGState()
    }

    /// Filled triangular arrowhead pointing toward `tip`, with the line segment going from
    /// `origin` to `tip` defining the direction.
    private func drawArrowhead(at tip: CGPoint, from origin: CGPoint, color: Color, size: CGFloat, ctx: CGContext) {
        guard size > 0 else { return }
        let dx = tip.x - origin.x, dy = tip.y - origin.y
        let len = max(0.001, hypot(dx, dy))
        let ux = dx / len, uy = dy / len
        let angle: CGFloat = .pi / 7
        let cosA = cos(angle), sinA = sin(angle)
        // Rotate `-u` by ±angle, then scale by size, then offset from `tip`.
        let leftX  = tip.x - size * (ux * cosA - uy * sinA)
        let leftY  = tip.y - size * (uy * cosA + ux * sinA)
        let rightX = tip.x - size * (ux * cosA + uy * sinA)
        let rightY = tip.y - size * (uy * cosA - ux * sinA)

        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: leftX, y: leftY))
        path.addLine(to: CGPoint(x: rightX, y: rightY))
        path.closeSubpath()

        ctx.setFillColor(color.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func drawPolygon(payload: PolygonLayerPayload, frame: Frame, ctx: CGContext) {
        let sides = max(3, payload.sides)
        let rect = frame.cgRect
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        let path = CGMutablePath()
        for i in 0..<sides {
            let theta = -.pi / 2 + Double(i) * 2 * .pi / Double(sides)
            let x = cx + rx * CGFloat(cos(theta))
            let y = cy + ry * CGFloat(sin(theta))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        fillThenStroke(path: path, fill: payload.fill, stroke: payload.stroke, ctx: ctx)
    }

    private func drawStar(payload: StarLayerPayload, frame: Frame, ctx: CGContext) {
        let points = max(3, payload.points)
        let inner = max(0.05, min(0.95, payload.innerRadius))
        let rect = frame.cgRect
        let cx = rect.midX, cy = rect.midY
        let outerRx = rect.width / 2, outerRy = rect.height / 2
        let innerRx = outerRx * CGFloat(inner), innerRy = outerRy * CGFloat(inner)
        let total = points * 2
        let path = CGMutablePath()
        for i in 0..<total {
            let theta = -.pi / 2 + Double(i) * .pi / Double(points)
            let rxv = (i % 2 == 0) ? outerRx : innerRx
            let ryv = (i % 2 == 0) ? outerRy : innerRy
            let x = cx + rxv * CGFloat(cos(theta))
            let y = cy + ryv * CGFloat(sin(theta))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        fillThenStroke(path: path, fill: payload.fill, stroke: payload.stroke, ctx: ctx)
    }

    private func fillThenStroke(path: CGPath, fill: Color, stroke: Stroke?, ctx: CGContext) {
        ctx.setFillColor(fill.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        if let s = stroke, s.width > 0 {
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(CGFloat(s.width))
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    /// Variable-radius blur driven by `BlurStop` keypoints. Builds a grayscale mask matching
    /// the cropped source bitmap — each pixel's brightness encodes `radius / maxRadius` — then
    /// runs `CIMaskedVariableBlur` with `inputRadius` set to the device-space max radius. The
    /// mask is painted with the user-space y axis flipped relative to the CG bitmap, so that
    /// stop `at=0` maps to the layer's "top" and `at=1` to the "bottom" of the gradient.
    private func drawGradientBlur(payload: BlurLayerPayload,
                                  stops: [BlurStop],
                                  frame: Frame,
                                  cornerRadius: Double,
                                  cornerStyle: CornerStyle,
                                  corners: RectCorners = .all,
                                  ctx: CGContext) {
        let maxRadius = max(0.01, stops.map(\.radius).max() ?? 0)
        guard maxRadius > 0 else {
            drawBlurTintOnly(payload: payload, frame: frame, cornerRadius: cornerRadius,
                             cornerStyle: cornerStyle, corners: corners, ctx: ctx)
            return
        }

        // Snapshot the current canvas bitmap so we can sample the existing pixels.
        guard let snap = ctx.makeImage() else { return }
        let userRect = frame.cgRect
        let xform = ctx.userSpaceToDeviceSpaceTransform
        let deviceRect = userRect.applying(xform).standardized
        let snapBounds = CGRect(x: 0, y: 0, width: snap.width, height: snap.height)
        let cropRect = deviceRect.integral.intersection(snapBounds)
        guard !cropRect.isEmpty, cropRect.width >= 1, cropRect.height >= 1,
              let cropped = snap.cropping(to: cropRect) else { return }

        let pxScale = max(abs(xform.a), abs(xform.d))
        let pxMaxRadius = max(0.5, maxRadius * Double(pxScale))

        // Build the grayscale mask. We paint a CGGradient where each stop's brightness is the
        // ratio of its radius to maxRadius; CIMaskedVariableBlur reads white = full blur.
        let mw = cropped.width, mh = cropped.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let maskCtx = CGContext(data: nil, width: mw, height: mh,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

        let sorted = stops.sorted(by: { $0.at < $1.at })
        let cfColors = sorted.map { stop -> CGColor in
            let g = CGFloat(max(0, min(1, stop.radius / maxRadius)))
            return CGColor(srgbRed: g, green: g, blue: g, alpha: 1)
        } as CFArray
        let locations = sorted.map { CGFloat(max(0, min(1, $0.at))) }
        guard let gradient = CGGradient(colorsSpace: space,
                                        colors: cfColors,
                                        locations: locations) else { return }

        // Default the mask to black (no-blur) so stops outside [0,1] don't leak into the result.
        maskCtx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        maskCtx.fill(CGRect(x: 0, y: 0, width: mw, height: mh))

        // Map normalized user-space coordinates to mask pixel coordinates. The user expects
        // `startY = 0` to mean "top of layer", but maskCtx (a plain CG bitmap) has its origin
        // at the bottom-left. We flip y so that `at=0` lands at the top row of the mask, which
        // matches the bitmap orientation of the cropped source (also bottom-up in pixels).
        let startPt = CGPoint(x: payload.startX * Double(mw),
                              y: (1.0 - payload.startY) * Double(mh))
        let endPt = CGPoint(x: payload.endX * Double(mw),
                            y: (1.0 - payload.endY) * Double(mh))

        switch payload.gradientType {
        case .linear:
            maskCtx.drawLinearGradient(gradient, start: startPt, end: endPt,
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .radial:
            let radius = hypot(endPt.x - startPt.x, endPt.y - startPt.y)
            maskCtx.drawRadialGradient(gradient,
                                       startCenter: startPt, startRadius: 0,
                                       endCenter: startPt, endRadius: max(0.5, radius),
                                       options: [.drawsAfterEndLocation])
        }

        guard let maskImage = maskCtx.makeImage() else { return }

        let sourceCI = CIImage(cgImage: cropped)
        let maskCI   = CIImage(cgImage: maskImage)
        let blurred = sourceCI.clampedToExtent()
            .applyingFilter("CIMaskedVariableBlur", parameters: [
                kCIInputRadiusKey: pxMaxRadius,
                "inputMask": maskCI
            ])
            .cropped(to: sourceCI.extent)
        guard let blurredCG = Self.ciContext.createCGImage(blurred, from: blurred.extent) else { return }

        // Map the cropped device rect back to user space (in case we got clipped to snapBounds
        // along an edge), then draw with the same y-flip trick that drawBlur uses.
        let inverse = xform.inverted()
        let visibleUserRect = cropRect.applying(inverse).standardized

        ctx.saveGState()
        if cornerRadius > 0 {
            let clipPath = Self.roundedRectPath(rect: userRect,
                                                cornerRadius: CGFloat(cornerRadius),
                                                style: cornerStyle,
                                                corners: corners)
            ctx.addPath(clipPath); ctx.clip()
        }
        ctx.saveGState()
        ctx.translateBy(x: visibleUserRect.midX, y: visibleUserRect.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -visibleUserRect.midX, y: -visibleUserRect.midY)
        ctx.draw(blurredCG, in: visibleUserRect)
        ctx.restoreGState()
        if let tint = payload.tint, tint.a > 0 {
            ctx.setFillColor(tint.cgColor)
            ctx.fill(userRect)
        }
        ctx.restoreGState()
    }

    private func drawBlurTintOnly(payload: BlurLayerPayload, frame: Frame, cornerRadius: Double, cornerStyle: CornerStyle = .arc, corners: RectCorners = .all, ctx: CGContext) {
        guard let tint = payload.tint, tint.a > 0 else { return }
        let rect = frame.cgRect
        ctx.saveGState()
        if cornerRadius > 0 {
            let path = Self.roundedRectPath(rect: rect,
                                            cornerRadius: CGFloat(cornerRadius),
                                            style: cornerStyle,
                                            corners: corners)
            ctx.addPath(path)
            ctx.clip()
        }
        ctx.setFillColor(tint.cgColor)
        ctx.fill(rect)
        ctx.restoreGState()
    }
}
