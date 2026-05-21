import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AIImageEditorCore

struct CanvasView: View {
    @ObservedObject var document: ProjectDocument
    @Binding var zoom: CGFloat
    let baseDirectory: URL?

    @State private var interaction: Interaction = .idle
    @State private var dropHighlight: String?
    /// Held in `@State` purely so the same instance survives view-body recomputations during a
    /// drag. Mutations don't trigger view updates (it's a plain class), which is exactly the
    /// behaviour we want for a render-side cache.
    @State private var renderCache = PageRenderCache()
    /// Zoom level at the start of a magnification gesture — multiplied by the gesture's
    /// magnification value to update `zoom`.
    @State private var zoomAtGestureStart: CGFloat?

    // Constant origin inset used for the dragGesture/dropDelegate coordinate math.
    private let canvasInset: CGFloat = 40

    /// Hit-tolerance for handles, in *screen* pixels.
    private let handleScreenSize: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let page = document.selectedPage
            let canvasSize = CGSize(width: CGFloat(page.canvas.width) * zoom,
                                    height: CGFloat(page.canvas.height) * zoom)
            ZStack {
                Color(white: 0.13).ignoresSafeArea()
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        CheckerboardView()
                            .frame(width: canvasSize.width, height: canvasSize.height)
                        renderedImage(size: canvasSize)
                        selectionOverlay(canvasSize: canvasSize)
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .padding(canvasInset)
                    .contentShape(Rectangle())
                    .gesture(canvasGesture())
                    .simultaneousGesture(zoomGesture())
                    .onDrop(of: [.fileURL, .image], delegate: ImageDropDelegate(
                        document: document,
                        zoom: zoom,
                        canvasOriginInset: canvasInset,
                        highlightedLayerId: $dropHighlight))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .background(Color(white: 0.1))
    }

    @ViewBuilder
    private func renderedImage(size: CGSize) -> some View {
        if let image = renderImage() {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
        } else {
            Color.gray.frame(width: size.width, height: size.height)
        }
    }

    private func renderImage() -> NSImage? {
        renderCache.render(document: document.document,
                           pageId: document.selectedPageId,
                           baseDirectory: baseDirectory)
    }

    // MARK: - Selection overlay (frame outline + handles)

    @ViewBuilder
    private func selectionOverlay(canvasSize: CGSize) -> some View {
        if let sel = document.selectedLayerId,
           let layer = document.selectedPage.layer(id: sel) {
            let f = layer.frame
            let x = CGFloat(f.x) * zoom
            let y = CGFloat(f.y) * zoom
            let w = CGFloat(f.w) * zoom
            let h = CGFloat(f.h) * zoom
            // Frame outline
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 1.5)
                .frame(width: w, height: h)
                .offset(x: x, y: y)
                .allowsHitTesting(false)

            // Resize handles
            ForEach(Handle.allCases) { handle in
                HandleView(handle: handle, isActive: handle == activeHandle)
                    .position(handlePosition(handle: handle, x: x, y: y, w: w, h: h))
                    .allowsHitTesting(false)
            }
        }
        if let hid = dropHighlight,
           let layer = document.selectedPage.layer(id: hid) {
            let f = layer.frame
            Rectangle()
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, dash: [6]))
                .frame(width: CGFloat(f.w) * zoom, height: CGFloat(f.h) * zoom)
                .offset(x: CGFloat(f.x) * zoom, y: CGFloat(f.y) * zoom)
                .allowsHitTesting(false)
        }
    }

    private var activeHandle: Handle? {
        if case .resizing(_, let h, _, _) = interaction { return h }
        return nil
    }

    private func handlePosition(handle: Handle, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> CGPoint {
        // Position is relative to the ZStack's topLeading origin.
        let (ax, ay) = handle.anchorFraction
        return CGPoint(x: x + w * ax, y: y + h * ay)
    }

    // MARK: - Gestures

    private func canvasGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in handleDragChanged(value: value) }
            .onEnded   { _      in handleDragEnded() }
    }

    /// Trackpad pinch (two-finger spread/squeeze) zooms the canvas. Multiplies the zoom level
    /// from the gesture-start baseline so a continuous pinch feels natural.
    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if zoomAtGestureStart == nil { zoomAtGestureStart = zoom }
                let base = zoomAtGestureStart ?? zoom
                zoom = max(0.05, min(2.0, base * value))
            }
            .onEnded { _ in
                zoomAtGestureStart = nil
            }
    }

    private func handleDragChanged(value: DragGesture.Value) {
        // Initialise interaction on the first event of a drag.
        if case .idle = interaction {
            startInteraction(at: value.startLocation)
        }
        applyInteraction(currentLocation: value.location)
    }

    private func handleDragEnded() {
        // Commit by clearing — final frame already lives in document.document.
        interaction = .idle
    }

    /// Decide whether the gesture begins as a handle resize, a layer move, or a deselect.
    private func startInteraction(at screenStart: CGPoint) {
        let canvasStart = toCanvas(screenStart)
        // Prefer hitting a handle of the currently-selected layer.
        if let sel = document.selectedLayerId,
           let layer = document.selectedPage.layer(id: sel),
           let handle = handleHit(local: canvasStart, frame: layer.frame) {
            document.beginUndoableEdit()
            interaction = .resizing(layerId: layer.id, handle: handle,
                                    start: layer.frame, startPoint: canvasStart)
            return
        }
        // Otherwise hit-test layers.
        if let hit = hitTestLayer(local: canvasStart) {
            document.selectedLayerId = hit.id
            document.beginUndoableEdit()
            interaction = .moving(layerId: hit.id, start: hit.frame, startPoint: canvasStart)
            return
        }
        // Tap on empty canvas → clear selection (so page settings show).
        document.selectedLayerId = nil
        interaction = .idle
    }

    private func applyInteraction(currentLocation: CGPoint) {
        let canvasNow = toCanvas(currentLocation)
        switch interaction {
        case .idle:
            return
        case .moving(let id, let start, let startPoint):
            let dx = canvasNow.x - startPoint.x
            let dy = canvasNow.y - startPoint.y
            var working = document.document
            _ = try? CommandEngine.apply(
                .move(pageId: document.selectedPageId, id: id,
                      to: (start.x + Double(dx), start.y + Double(dy))),
                to: &working)
            document.objectWillChange.send()
            document.document = working
        case .resizing(let id, let handle, let start, let startPoint):
            let dx = Double(canvasNow.x - startPoint.x)
            let dy = Double(canvasNow.y - startPoint.y)
            let lock = NSEvent.modifierFlags.contains(.command)
            // Device bezels are aspect-locked to their device — they can't be stretched
            // off-shape regardless of which handle is dragged or whether Cmd is held.
            var forceAspect: Double? = nil
            if let layer = document.selectedPage.layer(id: id),
               case .deviceBezel(let p) = layer.payload,
               let bezel = DeviceBezelCatalog.find(id: p.device) {
                forceAspect = bezel.aspect
            }
            var newFrame = handle.newFrame(start: start, dx: dx, dy: dy,
                                            lockAspect: lock, forceAspect: forceAspect)
            // Floor minimum size.
            newFrame.w = max(10, newFrame.w)
            newFrame.h = max(10, newFrame.h)
            var working = document.document
            _ = try? CommandEngine.apply(
                .setFrame(pageId: document.selectedPageId, id: id, frame: newFrame),
                to: &working)
            document.objectWillChange.send()
            document.document = working
        }
    }

    // MARK: - Hit testing

    /// Convert a coordinate inside the padded ZStack into canvas (pixel) space.
    private func toCanvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - canvasInset) / zoom, y: (p.y - canvasInset) / zoom)
    }

    private func hitTestLayer(local: CGPoint) -> Layer? {
        for layer in document.selectedPage.renderOrder.reversed() where layer.visible {
            if layer.frame.cgRect.contains(local) { return layer }
        }
        return nil
    }

    /// If `local` (in canvas units) lands on a resize handle of `frame`, return it.
    private func handleHit(local: CGPoint, frame: Frame) -> Handle? {
        // Convert handle screen size into canvas units.
        let halfSizeCanvas = (handleScreenSize / 2) / zoom
        for handle in Handle.allCases {
            let p = handle.position(in: frame)
            let dx = abs(local.x - CGFloat(p.0))
            let dy = abs(local.y - CGFloat(p.1))
            // Slightly relaxed hit zone (capsules have an elongated shape but we model them as
            // rectangles for hit testing).
            let (hx, hy) = handle.hitToleranceMultipliers
            if dx <= halfSizeCanvas * hx && dy <= halfSizeCanvas * hy { return handle }
        }
        return nil
    }
}

// MARK: - Handles

enum Handle: Identifiable, CaseIterable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    var id: String { String(describing: self) }

    /// Position on the layer frame as a fraction of (w, h).
    var anchorFraction: (CGFloat, CGFloat) {
        switch self {
        case .topLeft:     return (0,   0)
        case .top:         return (0.5, 0)
        case .topRight:    return (1,   0)
        case .left:        return (0,   0.5)
        case .right:       return (1,   0.5)
        case .bottomLeft:  return (0,   1)
        case .bottom:      return (0.5, 1)
        case .bottomRight: return (1,   1)
        }
    }

    /// Returns true if this handle resizes both width and height (corner handles).
    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }

    /// Hit-area tolerance multipliers along each axis (capsules have wider hit areas along
    /// the edge they sit on).
    var hitToleranceMultipliers: (CGFloat, CGFloat) {
        switch self {
        case .top, .bottom: return (3, 1)     // capsule lies horizontally
        case .left, .right: return (1, 3)     // capsule lies vertically
        default:            return (1.2, 1.2) // corner square
        }
    }

    /// Position of this handle in canvas-pixel coordinates, given the layer's frame.
    func position(in frame: Frame) -> (Double, Double) {
        let (ax, ay) = anchorFraction
        return (frame.x + frame.w * Double(ax),
                frame.y + frame.h * Double(ay))
    }

    /// Compute a new frame based on a cursor delta from the start position.
    ///
    /// `lockAspect` (e.g. Cmd held during a drag) preserves the layer's *starting* aspect on
    /// corner handles. `forceAspect`, if non-nil, instead **forces** the new frame to that
    /// w/h ratio for every handle (corner or edge) — used for device bezels so they can't
    /// be stretched off-aspect.
    func newFrame(start: Frame, dx: Double, dy: Double, lockAspect: Bool, forceAspect: Double? = nil) -> Frame {
        var f = start
        let startAspect = start.w / max(start.h, 1)
        switch self {
        case .topLeft:
            f.x = start.x + dx
            f.y = start.y + dy
            f.w = start.w - dx
            f.h = start.h - dy
            if lockAspect {
                let useW = abs(dx) > abs(dy)
                if useW {
                    let newH = f.w / startAspect
                    f.y = start.y + (start.h - newH)
                    f.h = newH
                } else {
                    let newW = f.h * startAspect
                    f.x = start.x + (start.w - newW)
                    f.w = newW
                }
            }
        case .topRight:
            f.y = start.y + dy
            f.w = start.w + dx
            f.h = start.h - dy
            if lockAspect {
                let useW = abs(dx) > abs(dy)
                if useW {
                    let newH = f.w / startAspect
                    f.y = start.y + (start.h - newH)
                    f.h = newH
                } else {
                    f.w = f.h * startAspect
                }
            }
        case .bottomLeft:
            f.x = start.x + dx
            f.w = start.w - dx
            f.h = start.h + dy
            if lockAspect {
                let useW = abs(dx) > abs(dy)
                if useW {
                    f.h = f.w / startAspect
                } else {
                    let newW = f.h * startAspect
                    f.x = start.x + (start.w - newW)
                    f.w = newW
                }
            }
        case .bottomRight:
            f.w = start.w + dx
            f.h = start.h + dy
            if lockAspect {
                let useW = abs(dx) > abs(dy)
                if useW {
                    f.h = f.w / startAspect
                } else {
                    f.w = f.h * startAspect
                }
            }
        case .top:
            f.y = start.y + dy
            f.h = start.h - dy
        case .bottom:
            f.h = start.h + dy
        case .left:
            f.x = start.x + dx
            f.w = start.w - dx
        case .right:
            f.w = start.w + dx
        }

        // Force a fixed aspect (used for device bezels). Picks the "primary" dimension based
        // on the handle (or the dominant axis for corners) and recomputes the other,
        // re-anchoring so the opposite edge / corner of `start` stays put.
        if let aspect = forceAspect, aspect > 0 {
            let primaryIsWidth: Bool
            switch self {
            case .top, .bottom:     primaryIsWidth = false   // only h changed
            case .left, .right:     primaryIsWidth = true    // only w changed
            default:                primaryIsWidth = abs(dx) >= abs(dy)
            }
            if primaryIsWidth {
                let newH = max(1, f.w / aspect)
                switch self {
                case .topLeft, .top, .topRight:
                    f.y = start.y + start.h - newH
                case .bottomLeft, .bottom, .bottomRight:
                    f.y = start.y
                case .left, .right:
                    f.y = start.y + (start.h - newH) / 2
                }
                f.h = newH
            } else {
                let newW = max(1, f.h * aspect)
                switch self {
                case .topLeft, .left, .bottomLeft:
                    f.x = start.x + start.w - newW
                case .topRight, .right, .bottomRight:
                    f.x = start.x
                case .top, .bottom:
                    f.x = start.x + (start.w - newW) / 2
                }
                f.w = newW
            }
        }

        return f
    }
}

private struct HandleView: View {
    let handle: Handle
    let isActive: Bool

    var body: some View {
        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            // Square corner handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .frame(width: 11, height: 11)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
                .scaleEffect(isActive ? 1.15 : 1.0)
        case .top, .bottom:
            // Horizontal capsule
            Capsule()
                .fill(Color.white)
                .frame(width: 22, height: 8)
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
                .scaleEffect(isActive ? 1.15 : 1.0)
        case .left, .right:
            // Vertical capsule
            Capsule()
                .fill(Color.white)
                .frame(width: 8, height: 22)
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
                .scaleEffect(isActive ? 1.15 : 1.0)
        }
    }
}

// MARK: - Drag-and-drop (unchanged contract)

/// Routes a dropped image file to the device-bezel layer it lands on. If the drop is on a
/// non-bezel layer or on empty canvas, falls back to adding a regular image layer at that point.
struct ImageDropDelegate: DropDelegate {
    let document: ProjectDocument
    let zoom: CGFloat
    let canvasOriginInset: CGFloat
    @Binding var highlightedLayerId: String?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL, .image])
    }

    func dropEntered(info: DropInfo) { updateHighlight(info: info) }
    func dropExited(info: DropInfo) { highlightedLayerId = nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateHighlight(info: info)
        return DropProposal(operation: .copy)
    }

    private func updateHighlight(info: DropInfo) {
        let local = canvasPoint(from: info.location)
        if let bezel = topmostBezel(at: local) {
            highlightedLayerId = bezel.id
        } else {
            highlightedLayerId = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let local = canvasPoint(from: info.location)
        let bezelLayer = topmostBezel(at: local)
        highlightedLayerId = nil
        guard let provider = info.itemProviders(for: [.fileURL, .image]).first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let u = item as? URL {
                url = u
            } else if let s = item as? String {
                url = URL(string: s)
            }
            guard let fileURL = url else { return }
            DispatchQueue.main.async {
                if let bezel = bezelLayer {
                    attach(screenshotURL: fileURL, to: bezel.id)
                } else {
                    addImageLayer(at: local, fileURL: fileURL)
                }
            }
        }
        return true
    }

    private func canvasPoint(from screenPoint: CGPoint) -> CGPoint {
        CGPoint(x: (screenPoint.x - canvasOriginInset) / zoom,
                y: (screenPoint.y - canvasOriginInset) / zoom)
    }

    private func topmostBezel(at point: CGPoint) -> Layer? {
        for layer in document.selectedPage.renderOrder.reversed() where layer.visible {
            guard layer.kind == .deviceBezel else { continue }
            if layer.frame.cgRect.contains(point) { return layer }
        }
        return nil
    }

    private func attach(screenshotURL: URL, to bezelId: String) {
        let assetId = ProjectAssetHelper.autoAssetId(in: document.document, path: screenshotURL.path)
        if document.document.assets[assetId] == nil {
            _ = document.mutate(.addAsset(id: assetId, path: screenshotURL.path))
        }
        document.mutate(.setBezelScreenshot(pageId: document.selectedPageId, id: bezelId, assetId: assetId))
        document.selectedLayerId = bezelId
    }

    private func addImageLayer(at point: CGPoint, fileURL: URL) {
        let assetId = ProjectAssetHelper.autoAssetId(in: document.document, path: fileURL.path)
        if document.document.assets[assetId] == nil {
            _ = document.mutate(.addAsset(id: assetId, path: fileURL.path))
        }
        let w: Double = 600
        let h: Double = 600
        let frame = Frame(x: point.x - w / 2, y: point.y - h / 2, w: w, h: h)
        let r = document.mutate(.addImage(pageId: document.selectedPageId, id: nil,
                                          assetId: assetId, frame: frame, contentMode: .fit, z: nil))
        document.selectedLayerId = r?.newLayerId
    }
}

struct CheckerboardView: View {
    let size: CGFloat = 16
    var body: some View {
        Canvas { ctx, area in
            let cols = Int(area.width / size) + 1
            let rows = Int(area.height / size) + 1
            for r in 0..<rows {
                for c in 0..<cols {
                    let isDark = (r + c) % 2 == 0
                    let rect = CGRect(x: CGFloat(c) * size, y: CGFloat(r) * size, width: size, height: size)
                    ctx.fill(Path(rect), with: .color(isDark ? Color(white: 0.18) : Color(white: 0.22)))
                }
            }
        }
    }
}

private extension CanvasView {
    /// Interaction states for the canvas drag gesture.
    enum Interaction {
        case idle
        case moving(layerId: String, start: Frame, startPoint: CGPoint)
        case resizing(layerId: String, handle: Handle, start: Frame, startPoint: CGPoint)
    }
}

/// Caches per-page rendered NSImages so tab-switching back to an unchanged page is essentially
/// free, and so back-to-back body recomputations during a drag don't pay the full render cost
/// when only an unrelated piece of state has changed. The cache key is `(pageId, page state,
/// asset dictionary, baseDirectory)` — anything that affects the rendered output. During a
/// resize the page state changes every tick so we still re-render that one page, but the bezel
/// composites it uses come from BezelImageStore's internal cache, so each render is cheap.
final class PageRenderCache {
    private struct Entry {
        let page: Page
        let assets: [String: Asset]
        let baseDirectory: URL?
        let image: NSImage
    }

    private var entries: [String: Entry] = [:]
    private let capacity = 12

    func render(document: Document, pageId: String, baseDirectory: URL?) -> NSImage? {
        let page = document.page(id: pageId) ?? document.activePage
        let assets = document.assets

        if let entry = entries[pageId],
           entry.page == page,
           entry.assets == assets,
           entry.baseDirectory == baseDirectory {
            return entry.image
        }

        let renderer = Renderer(baseDirectory: baseDirectory)
        guard let img = try? renderer.renderNSImage(document, scale: 1, pageId: pageId) else {
            return nil
        }
        entries[pageId] = Entry(page: page, assets: assets, baseDirectory: baseDirectory, image: img)
        // Simple eviction — drop oldest entries when we run over capacity.
        if entries.count > capacity {
            let drop = entries.keys.prefix(entries.count - capacity)
            for k in drop { entries.removeValue(forKey: k) }
        }
        return img
    }

    func invalidate(pageId: String) { entries.removeValue(forKey: pageId) }
    func invalidateAll() { entries.removeAll() }
}
