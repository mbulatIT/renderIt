import Foundation
import CoreGraphics
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
        let page: Page
        if let pid = pageId, let p = document.page(id: pid) { page = p } else { page = document.activePage }
        return try renderPage(page: page, assets: document.assets, scale: scale, mode: mode)
    }

    public func renderPage(page: Page, assets: [String: Asset], scale: Int = 1, mode: Mode = .editor) throws -> CGImage {
        let w = max(1, page.canvas.width * scale)
        let h = max(1, page.canvas.height * scale)
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

        // Move to top-left origin so that Document coordinates map directly.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))

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
            ctx.saveGState()
            applyTransform(ctx: ctx, layer: layer)
            ctx.setAlpha(CGFloat(max(0, min(1, layer.opacity))))
            ctx.setBlendMode(cgBlendMode(layer.blendMode))
            drawLayer(layer, in: ctx, assets: assets)
            ctx.restoreGState()
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
            ctx.saveGState()
            applyTransform(ctx: ctx, layer: layer)
            ctx.setAlpha(CGFloat(max(0, min(1, layer.opacity))))
            ctx.setBlendMode(cgBlendMode(layer.blendMode))
            drawLayer(layer, in: ctx, assets: assets)
            ctx.restoreGState()
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
            drawShape(payload: p, frame: layer.frame, ctx: ctx, ellipse: false)
        case .ellipse(let p):
            drawShape(payload: p, frame: layer.frame, ctx: ctx, ellipse: true)
        case .deviceBezel(let p):
            drawDeviceBezel(payload: p, frame: layer.frame, ctx: ctx, assets: assets)
        case .group(let g):
            for child in g.children where child.visible {
                ctx.saveGState()
                applyTransform(ctx: ctx, layer: child)
                ctx.setAlpha(CGFloat(max(0, min(1, child.opacity))))
                ctx.setBlendMode(cgBlendMode(child.blendMode))
                drawLayer(child, in: ctx, assets: assets)
                ctx.restoreGState()
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
        var attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: NSColor(cgColor: payload.color.cgColor) ?? .white,
            .paragraphStyle: para,
            .kern: payload.kerning,
        ]
        if let s = payload.shadow {
            let sh = NSShadow()
            sh.shadowColor = NSColor(cgColor: s.color.cgColor)
            sh.shadowOffset = NSSize(width: s.offsetX, height: -s.offsetY)
            sh.shadowBlurRadius = CGFloat(s.blur)
            attrs[.shadow] = sh
        }
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

    private func drawShape(payload: ShapeLayerPayload, frame: Frame, ctx: CGContext, ellipse: Bool) {
        let rect = frame.cgRect
        let path: CGPath
        if ellipse {
            path = CGPath(ellipseIn: rect, transform: nil)
        } else if payload.cornerRadius > 0 {
            path = CGPath(roundedRect: rect,
                          cornerWidth: CGFloat(payload.cornerRadius),
                          cornerHeight: CGFloat(payload.cornerRadius),
                          transform: nil)
        } else {
            path = CGPath(rect: rect, transform: nil)
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
}
