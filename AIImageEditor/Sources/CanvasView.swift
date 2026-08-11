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
    /// Bridge to the live NSScrollView for converting pointer locations to canvas pixels through
    /// the actual magnification + scroll. `@State` so the same instance survives body recomputes.
    @State private var geometry = CanvasGeometry()
    /// Off-main, coalesced canvas renderer. Body shows its last completed image; renders happen
    /// on a background queue at the on-screen zoom resolution (a coarse draft during an active
    /// move/resize, crisp on release), so editing never blocks the main thread on rasterization.
    @StateObject private var canvasRenderer = CanvasRenderer()

    // Constant origin inset used for the dragGesture/dropDelegate coordinate math.
    private let canvasInset: CGFloat = 40

    /// Hit-tolerance for handles, in *screen* pixels.
    private let handleScreenSize: CGFloat = 14

    var body: some View {
        let page = document.selectedPage
        // Canvas content lives at canvas-pixel size inside the scroll view. NSScrollView's
        // native magnification handles the visual zoom — and crucially anchors the zoom on the
        // cursor / pinch center for free.
        let canvasSize = CGSize(width: CGFloat(page.canvas.width),
                                height: CGFloat(page.canvas.height))
        let outerSize = CGSize(width: canvasSize.width + canvasInset * 2,
                               height: canvasSize.height + canvasInset * 2)
        ZoomScrollView(contentSize: outerSize, zoom: $zoom, geometry: geometry) {
            ZStack(alignment: .topLeading) {
                CheckerboardView()
                    .frame(width: canvasSize.width, height: canvasSize.height)
                renderedImage(size: canvasSize)
                groupOutlines()
                selectionOverlay(canvasSize: canvasSize)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .padding(canvasInset)
            .contentShape(Rectangle())
            .gesture(canvasGesture())
            .onDrop(of: [.fileURL, .image], delegate: ImageDropDelegate(
                document: document,
                canvasOriginInset: canvasInset,
                highlightedLayerId: $dropHighlight))
            .onAppear { requestRender() }
            .onChange(of: renderKey) { _ in requestRender() }
        }
        .background(Color(white: 0.1))
    }

    @ViewBuilder
    private func renderedImage(size: CGSize) -> some View {
        if let image = canvasRenderer.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
        } else {
            Color.gray.frame(width: size.width, height: size.height)
        }
    }

    /// True while the user is actively dragging or resizing — drives the coarse "draft" render
    /// scale. Marquee/selection don't change canvas pixels, so they stay at the crisp scale.
    private var isManipulating: Bool {
        switch interaction {
        case .moving, .resizing: return true
        default:                 return false
        }
    }

    /// Cheap value that changes exactly when the canvas pixels must be re-rendered: the page,
    /// the document revision, or the render scale bucket (zoom / draft-vs-crisp). Drives the
    /// `.onChange` that schedules a render.
    private var renderKey: CanvasRenderer.Key {
        let scale = CanvasRenderer.renderScale(zoom: zoom, interacting: isManipulating)
        return CanvasRenderer.Key(pageId: document.selectedPageId,
                                  revision: document.revision,
                                  scaleMilli: Int((scale * 1000).rounded()),
                                  baseDir: baseDirectory)
    }

    private func requestRender() {
        let page = document.selectedPage
        canvasRenderer.request(document: document.document,
                               pageId: document.selectedPageId,
                               canvasSize: CGSize(width: page.canvas.width, height: page.canvas.height),
                               revision: document.revision,
                               zoom: zoom,
                               interacting: isManipulating,
                               baseDirectory: baseDirectory)
    }

    // MARK: - Group outlines

    /// Persistent dashed rectangle around every group layer in the page, so users can see the
    /// group bounds even when the group isn't selected. Drawn behind the selection overlay so
    /// the selected group's solid outline takes precedence. Coordinates are canvas pixels —
    /// NSScrollView's magnification scales the whole hosted view, so the stroke width is also
    /// scaled with zoom; we compensate by dividing the line width by zoom.
    @ViewBuilder
    private func groupOutlines() -> some View {
        ForEach(document.selectedPage.renderOrder, id: \.id) { layer in
            if case .group = layer.payload {
                let f = layer.frame
                Rectangle()
                    .strokeBorder(Color.accentColor.opacity(0.55),
                                  style: StrokeStyle(lineWidth: 1 / zoom, dash: [4 / zoom, 3 / zoom]))
                    .frame(width: CGFloat(f.w), height: CGFloat(f.h))
                    .offset(x: CGFloat(f.x), y: CGFloat(f.y))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Selection overlay (frame outline + handles)

    @ViewBuilder
    private func selectionOverlay(canvasSize: CGSize) -> some View {
        // Coordinates here are in canvas pixels; NSScrollView magnification scales them on
        // screen, so we divide stroke widths and handle sizes by zoom to keep them
        // visually constant regardless of magnification.
        ForEach(Array(document.selectedLayerIds), id: \.self) { sel in
            if let layer = findLayer(id: sel) {
                let f = layer.frame
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 1.5 / zoom)
                    .frame(width: CGFloat(f.w), height: CGFloat(f.h))
                    .offset(x: CGFloat(f.x), y: CGFloat(f.y))
                    .allowsHitTesting(false)
            }
        }
        // Resize handles only make sense with exactly one layer selected.
        if document.selectedLayerIds.count == 1,
           let sel = document.selectedLayerIds.first,
           let layer = findLayer(id: sel) {
            let f = layer.frame
            ForEach(Handle.allCases) { handle in
                HandleView(handle: handle, isActive: handle == activeHandle, zoom: zoom)
                    .position(handlePosition(handle: handle,
                                             x: CGFloat(f.x), y: CGFloat(f.y),
                                             w: CGFloat(f.w), h: CGFloat(f.h)))
                    .allowsHitTesting(false)
            }
        }
        if let hid = dropHighlight,
           let layer = findLayer(id: hid) {
            let f = layer.frame
            Rectangle()
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3 / zoom, dash: [6 / zoom]))
                .frame(width: CGFloat(f.w), height: CGFloat(f.h))
                .offset(x: CGFloat(f.x), y: CGFloat(f.y))
                .allowsHitTesting(false)
        }
        // Marquee selection rectangle (drawn while the user click-drags on empty canvas).
        if case .marquee(let origin, let current, _, _) = interaction {
            let rect = CGRect(x: min(origin.x, current.x),
                              y: min(origin.y, current.y),
                              width: abs(current.x - origin.x),
                              height: abs(current.y - origin.y))
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1 / zoom, dash: [3 / zoom]))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    /// Like `selectedPage.layer(id:)` but also peers inside groups so multi-select overlays
    /// work when a nested child is in the selection set.
    private func findLayer(id: String) -> Layer? {
        func search(_ layers: [Layer]) -> Layer? {
            for l in layers {
                if l.id == id { return l }
                if case .group(let g) = l.payload, let f = search(g.children) { return f }
            }
            return nil
        }
        return search(document.selectedPage.layers)
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
        // Report locations in the global (window) space; `toCanvas` maps them into canvas pixels
        // using the measured canvas frame, so the mapping is correct at any magnification.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in handleDragChanged(value: value) }
            .onEnded   { _      in handleDragEnded() }
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

    /// Decide whether the gesture begins as a handle resize, a layer move, a marquee, or a
    /// deselect. Honours the Cmd modifier for additive selection.
    private func startInteraction(at screenStart: CGPoint) {
        let canvasStart = toCanvas(screenStart)
        let cmdHeld = NSEvent.modifierFlags.contains(.command)

        // Handle resize takes priority — only valid when exactly one layer is selected.
        if document.selectedLayerIds.count == 1,
           let sel = document.selectedLayerIds.first,
           let layer = findLayer(id: sel),
           let handle = handleHit(local: canvasStart, frame: layer.frame) {
            document.beginUndoableEdit()
            interaction = .resizing(layerId: layer.id, handle: handle,
                                    start: layer.frame, startPoint: canvasStart)
            return
        }

        if let hit = hitTestLayer(local: canvasStart) {
            if cmdHeld {
                // Cmd-click: toggle this layer in the selection. Don't start a move so the user
                // can build up a multi-selection without dragging anything.
                document.toggleSelection(hit.id)
                interaction = .idle
                return
            }
            // Plain click: if the hit isn't already part of the selection, replace selection
            // with just it. Either way, start moving every selected layer together.
            if !document.selectedLayerIds.contains(hit.id) {
                document.selectedLayerIds = [hit.id]
            }
            let movingIds = topLevelSelection(document.selectedLayerIds)
            var starts: [String: Frame] = [:]
            for id in movingIds {
                if let layer = findLayer(id: id) { starts[id] = layer.frame }
            }
            document.beginUndoableEdit()
            interaction = .moving(layerIds: movingIds, starts: starts, startPoint: canvasStart)
            return
        }

        // Click on empty canvas → start a marquee. Cmd-held keeps the current selection as a
        // base; otherwise the previous selection is cleared on first drag tick.
        let baseSelection = cmdHeld ? document.selectedLayerIds : []
        if !cmdHeld { document.selectedLayerIds = [] }
        interaction = .marquee(origin: canvasStart, current: canvasStart,
                               additive: cmdHeld, baseSelection: baseSelection)
    }

    private func applyInteraction(currentLocation: CGPoint) {
        let canvasNow = toCanvas(currentLocation)
        switch interaction {
        case .idle:
            return
        case .moving(let ids, let starts, let startPoint):
            let dx = Double(canvasNow.x - startPoint.x)
            let dy = Double(canvasNow.y - startPoint.y)
            var working = document.document
            for id in ids {
                guard let start = starts[id] else { continue }
                _ = try? CommandEngine.apply(
                    .move(pageId: document.selectedPageId, id: id,
                          to: (start.x + dx, start.y + dy)),
                    to: &working)
            }
            // Assigning the @Published `document` already emits objectWillChange; the render is
            // scheduled off the main thread via the renderKey `.onChange`.
            document.document = working
        case .marquee(let origin, _, let additive, let baseSelection):
            // Update the marquee's current corner and recompute the live selection.
            interaction = .marquee(origin: origin, current: canvasNow,
                                   additive: additive, baseSelection: baseSelection)
            let rect = marqueeRect(origin: origin, current: canvasNow)
            let intersecting = Set(marqueeHits(in: rect).map(\.id))
            document.selectedLayerIds = additive ? baseSelection.union(intersecting) : intersecting
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
            document.document = working
        }
    }

    // MARK: - Hit testing

    /// Canvas-pixel location of the pointer. Reads the live AppKit mouse position (which handles
    /// magnification, scroll, and coordinate-origin correctly); the SwiftUI gesture point is only
    /// a fallback before the scroll view is wired up.
    private func toCanvas(_ fallback: CGPoint) -> CGPoint {
        geometry.canvasPointAtMouse()
            ?? CGPoint(x: fallback.x - canvasInset, y: fallback.y - canvasInset)
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

/// Bridges AppKit coordinate conversion into the SwiftUI canvas. Holds a weak reference to the
/// live `NSScrollView` (set by `ZoomScrollView`) so a pointer location in window space can be
/// converted to canvas pixels through the actual magnification + scroll offset — which is the
/// only reliable source here. (`GeometryReader.frame(in: .global)` returns zero inside the
/// hosted scroll view, and assuming gestures arrive in canvas units breaks at zoom ≠ 1.)
final class CanvasGeometry {
    weak var scrollView: NSScrollView?
    var inset: CGFloat = 40

    /// Canvas-pixel location of the pointer, read straight from AppKit. We deliberately use
    /// `NSEvent.mouseLocation` (true screen coords) rather than SwiftUI's gesture `.global` point:
    /// SwiftUI reports top-left / y-down window coords, but `NSView.convert(_:from:)` expects
    /// AppKit's bottom-left / y-up window coords, and that origin mismatch inverted Y. Going
    /// screen → window → documentView keeps every origin consistent, and `convert` applies the
    /// scroll view's magnification + scroll. The hosting view is flipped, so the result is already
    /// top-left; subtracting the outer inset yields canvas pixels. Returns nil until wired up.
    func canvasPointAtMouse() -> CGPoint? {
        guard let scroll = scrollView, let win = scroll.window, let doc = scroll.documentView else { return nil }
        let inWindow = win.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inDoc = doc.convert(inWindow, from: nil)
        return CGPoint(x: inDoc.x - inset, y: inDoc.y - inset)
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
    /// Current canvas magnification. Handles draw in canvas units, but we want their
    /// on-screen size to stay the same regardless of zoom — so every dimension is divided by
    /// `zoom` here. (The renderer's NSScrollView magnifies the whole hosted view, including
    /// these handles; dividing by `zoom` cancels out that magnification.)
    let zoom: CGFloat

    var body: some View {
        let z = max(zoom, 0.001)
        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            RoundedRectangle(cornerRadius: 2 / z)
                .fill(Color.white)
                .frame(width: 11 / z, height: 11 / z)
                .overlay(
                    RoundedRectangle(cornerRadius: 2 / z)
                        .stroke(Color.accentColor, lineWidth: 1.5 / z)
                )
                .shadow(color: .black.opacity(0.25), radius: 1 / z, x: 0, y: 0.5 / z)
                .scaleEffect(isActive ? 1.15 : 1.0)
        case .top, .bottom:
            Capsule()
                .fill(Color.white)
                .frame(width: 22 / z, height: 8 / z)
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1.5 / z))
                .shadow(color: .black.opacity(0.25), radius: 1 / z, x: 0, y: 0.5 / z)
                .scaleEffect(isActive ? 1.15 : 1.0)
        case .left, .right:
            Capsule()
                .fill(Color.white)
                .frame(width: 8 / z, height: 22 / z)
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1.5 / z))
                .shadow(color: .black.opacity(0.25), radius: 1 / z, x: 0, y: 0.5 / z)
                .scaleEffect(isActive ? 1.15 : 1.0)
        }
    }
}

// MARK: - Drag-and-drop (unchanged contract)

/// Routes a dropped image file to the device-bezel layer it lands on. If the drop is on a
/// non-bezel layer or on empty canvas, falls back to adding a regular image layer at that point.
struct ImageDropDelegate: DropDelegate {
    let document: ProjectDocument
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
        // Drop locations come in the SwiftUI host's coordinate space, which equals canvas
        // pixels because NSScrollView magnification scales the whole hosted view. Just undo
        // the `.padding(canvasInset)` offset to land on the canvas's (0, 0).
        CGPoint(x: screenPoint.x - canvasOriginInset, y: screenPoint.y - canvasOriginInset)
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
        // Frame size = the image's natural pixel dimensions (capped to canvas).
        let canvas = document.selectedPage.canvas
        let natural = ProjectAssetHelper.naturalImageDefaultSize(fileURL: fileURL, canvas: canvas)
        let w = natural?.w ?? 600
        let h = natural?.h ?? 600
        // Centre the new image on the drop point.
        let frame = Frame(x: point.x - w / 2, y: point.y - h / 2, w: w, h: h)
        // contentMode = .stretch so resizing the frame deforms the image directly.
        let r = document.mutate(.addImage(pageId: document.selectedPageId, id: nil,
                                          assetId: assetId, frame: frame, contentMode: .stretch, z: nil))
        document.selectedLayerId = r?.newLayerId
    }
}

struct CheckerboardView: View {
    var body: some View {
        // A single small tile repeated to fill the frame. A previous implementation drew the
        // whole board with one SwiftUI `Canvas`, but at App-Store work-area sizes (a 1290×2796
        // preview expands the canvas to ~3870×5592 pt) a Canvas that large fails to fill its
        // frame and renders only a small top-left patch. Tiling a 32×32 image via AppKit fills
        // any size cheaply and correctly.
        Image(nsImage: Self.tile)
            .resizable(resizingMode: .tile)
    }

    /// A 2×2 checkerboard cell (16 pt squares) used as the repeating tile.
    private static let tile: NSImage = {
        let cell: CGFloat = 16
        let img = NSImage(size: NSSize(width: cell * 2, height: cell * 2))
        img.lockFocus()
        NSColor(white: 0.22, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: cell * 2, height: cell * 2).fill()
        NSColor(white: 0.18, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: cell, height: cell).fill()
        NSRect(x: cell, y: cell, width: cell, height: cell).fill()
        img.unlockFocus()
        return img
    }()
}

private extension CanvasView {
    /// Interaction states for the canvas drag gesture.
    enum Interaction {
        case idle
        /// Multi-layer move. `layerIds` are the layers being translated; `starts` captures their
        /// original frames at drag start so each tick can recompute from the cursor delta.
        case moving(layerIds: [String], starts: [String: Frame], startPoint: CGPoint)
        case resizing(layerId: String, handle: Handle, start: Frame, startPoint: CGPoint)
        /// Marquee selection rectangle drag. `baseSelection` is the selection at drag start
        /// (preserved when `additive` = Cmd was held).
        case marquee(origin: CGPoint, current: CGPoint, additive: Bool, baseSelection: Set<String>)
    }
}

// MARK: - Marquee + multi-select helpers

private extension CanvasView {
    func marqueeRect(origin: CGPoint, current: CGPoint) -> CGRect {
        CGRect(x: min(origin.x, current.x),
               y: min(origin.y, current.y),
               width: abs(current.x - origin.x),
               height: abs(current.y - origin.y))
    }

    /// Layers (top-level only) whose frames intersect the marquee rect.
    func marqueeHits(in rect: CGRect) -> [Layer] {
        document.selectedPage.renderOrder
            .filter { $0.visible }
            .filter { $0.frame.cgRect.intersects(rect) }
    }

    /// Filter `ids` to drop any layer whose ancestor is also in the set — prevents a multi-move
    /// from translating a child twice when both the group AND a child are selected (the group
    /// move already cascades through children via CommandEngine.translate).
    func topLevelSelection(_ ids: Set<String>) -> [String] {
        let layers = document.selectedPage.layers
        var result: [String] = []
        for id in ids {
            if !hasSelectedAncestor(id, in: layers, selection: ids) {
                result.append(id)
            }
        }
        return result
    }

    private func hasSelectedAncestor(_ id: String, in layers: [Layer], selection: Set<String>) -> Bool {
        // Walk the tree; an ancestor is any group on the path from root to the target.
        func walk(_ ls: [Layer], path: [String]) -> Bool {
            for l in ls {
                if l.id == id {
                    return path.contains(where: { selection.contains($0) })
                }
                if case .group(let g) = l.payload {
                    if walk(g.children, path: path + [l.id]) { return true }
                }
            }
            return false
        }
        return walk(layers, path: [])
    }
}

/// Renders the editor canvas off the main thread, coalesced, at the on-screen zoom resolution.
///
/// The canvas used to rasterize the entire ~21 MP work-area canvas at full resolution,
/// synchronously, inside the SwiftUI body — so every edit and every drag tick froze the UI on
/// large projects. This coordinator fixes that with three levers:
///
///   1. **Display-resolution rendering.** It renders at `renderScale(zoom:)` — capped at 1.0,
///      so it never produces more pixels than the canvas, and shrunk proportionally when the
///      user is zoomed out (the common case: the default zoom is 25%). At 25% that's ~16× fewer
///      pixels. The NSImage is still sized to the full canvas in points, so NSScrollView's
///      magnification and all overlay geometry are unchanged.
///   2. **Off-main + coalesced.** Renders run on a serial background queue. Body only ever reads
///      the last completed `image`. While a render is in flight, only the newest request is kept
///      (`pending`); a burst of drag ticks collapses to "render the latest, drop the rest", so
///      the main thread never blocks and the queue never backs up.
///   3. **Draft during interaction.** While moving/resizing, a coarser draft scale makes each
///      tick cheap; releasing flips back to the crisp scale and triggers one final render.
///
/// The render cache keys on the document's monotonic `revision` (not a deep `Page ==`), so the
/// hot-path dedupe is O(1). The pure `Renderer` struct, `CGImageCache`, and `BezelImageStore`
/// are all safe to use from the background queue.
final class CanvasRenderer: ObservableObject {
    @Published private(set) var image: NSImage?

    /// Identifies a renderable canvas state. Equatable so `.onChange` fires only when the pixels
    /// must change. `scaleMilli` is the render scale × 1000 (quantized) so nearby zoom levels and
    /// draft/crisp transitions are distinguished without re-rendering on sub-pixel zoom jitter.
    struct Key: Hashable {
        let pageId: String
        let revision: Int
        let scaleMilli: Int
        let baseDir: URL?
    }

    private struct Request {
        let key: Key
        let document: Document
        let pageId: String
        let scale: CGFloat
        let canvasSize: CGSize
        let baseDir: URL?
    }

    /// Render pixel scale for a zoom level. Capped at 1.0 (never more pixels than the canvas) and
    /// quantized to quarter steps, rounded UP so the idle image is at least as dense as the
    /// display (never upscaled → stays crisp). During an active move/resize a coarser draft is
    /// used so each tick is cheap; releasing re-requests at the crisp scale.
    static func renderScale(zoom: CGFloat, interacting: Bool) -> CGFloat {
        let z = min(max(zoom, 0.01), 1.0)
        let crisp = min(1.0, ceil(z / 0.25) * 0.25)   // 0.25, 0.5, 0.75, 1.0
        // During a move/resize, draft at 75% of the crisp scale — half the resolution drop of a
        // 0.5 draft, so the dip in sharpness while dragging is much less noticeable while each
        // synchronous render stays well under a frame.
        return interacting ? max(0.1875, crisp * 0.75) : crisp
    }

    private let queue = DispatchQueue(label: "io.tuist.AIImageEditor.canvasRender", qos: .userInitiated)
    private var inFlight = false
    private var pending: Request?
    private var shownKey: Key?
    // Small LRU of completed images so page-switches / zoom-bucket returns are instant.
    private var cache: [Key: NSImage] = [:]
    private var cacheOrder: [Key] = []
    private let cacheCapacity = 12

    /// Ask for a render of the given state. Cheap and idempotent: returns immediately if the
    /// state is already shown or cached, coalesces while a render is in flight, and renders the
    /// very first frame synchronously so opening a document shows the canvas without a gray flash.
    func request(document: Document, pageId: String, canvasSize: CGSize,
                 revision: Int, zoom: CGFloat, interacting: Bool, baseDirectory: URL?) {
        let scale = Self.renderScale(zoom: zoom, interacting: interacting)
        let key = Key(pageId: pageId, revision: revision,
                      scaleMilli: Int((scale * 1000).rounded()), baseDir: baseDirectory)
        if key == shownKey { return }
        if let cached = cache[key] {
            image = cached
            shownKey = key
            return
        }
        let req = Request(key: key, document: document, pageId: pageId,
                          scale: scale, canvasSize: canvasSize, baseDir: baseDirectory)
        // Render inline (on the main thread) for the first paint AND during an active move/resize:
        // the draft scale is cheap (well under a frame), so a synchronous render keeps the dragged
        // content locked to the cursor with no async lag. Idle/crisp renders go off-main coalesced.
        if image == nil || interacting {
            if let img = Self.render(req) { publish(img, for: req.key) }
            return
        }
        if inFlight { pending = req; return }
        start(req)
    }

    private func start(_ req: Request) {
        inFlight = true
        queue.async { [weak self] in
            let img = Self.render(req)
            DispatchQueue.main.async {
                guard let self else { return }
                if let img { self.publish(img, for: req.key) }
                self.inFlight = false
                if let next = self.pending {
                    self.pending = nil
                    self.start(next)
                }
            }
        }
    }

    /// Pure render → NSImage. Safe to call on any thread: `Renderer` is a stateless value type and
    /// the caches it touches (`CGImageCache`, `BezelImageStore`) are internally serialized.
    private static func render(_ req: Request) -> NSImage? {
        guard let cg = try? Renderer(baseDirectory: req.baseDir)
            .renderCGImage(req.document, pixelScale: req.scale, pageId: req.pageId, mode: .editor)
        else { return nil }
        let img = NSImage(size: NSSize(width: req.canvasSize.width, height: req.canvasSize.height))
        img.addRepresentation(NSBitmapImageRep(cgImage: cg))
        return img
    }

    private func publish(_ img: NSImage, for key: Key) {
        if cache[key] == nil { cacheOrder.append(key) }
        cache[key] = img
        while cacheOrder.count > cacheCapacity {
            let evict = cacheOrder.removeFirst()
            if evict != key { cache.removeValue(forKey: evict) }
        }
        image = img
        shownKey = key
    }
}

// MARK: - Zoomable scroll container

/// Hosts a SwiftUI canvas inside an `NSScrollView` with native magnification. NSScrollView's
/// pinch handling anchors the zoom on the cursor / pinch center for free — much closer to the
/// behaviour of any other macOS canvas tool than SwiftUI's stock `ScrollView` can offer (its
/// content offset isn't programmatically writable on macOS 13, so we'd have nothing to "pin"
/// when zooming).
///
/// The hosted SwiftUI content draws everything in **canvas-pixel** coordinates; the scroll
/// view's magnification is what scales it on screen. The `zoom` binding is kept in sync
/// bidirectionally — slider/keyboard updates land via `updateNSView`, and trackpad pinch
/// pushes back via `didLiveMagnify` / `didEndLiveMagnify` notifications.
struct ZoomScrollView<Content: View>: NSViewRepresentable {
    let contentSize: CGSize
    @Binding var zoom: CGFloat
    let geometry: CanvasGeometry
    let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05
        scroll.maxMagnification = 4.0
        scroll.magnification = zoom
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(white: 0.1, alpha: 1)

        let hosting = NSHostingView(rootView: content())
        hosting.frame = CGRect(origin: .zero, size: contentSize)
        scroll.documentView = hosting
        geometry.scrollView = scroll

        context.coordinator.scroll = scroll
        context.coordinator.zoom = $zoom
        context.coordinator.attach()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        geometry.scrollView = scroll
        if let host = scroll.documentView as? NSHostingView<Content> {
            host.rootView = content()
            if host.frame.size != contentSize {
                host.frame = CGRect(origin: .zero, size: contentSize)
            }
        }
        // Apply external zoom changes (toolbar slider, keyboard shortcuts). Compare with a
        // small tolerance so we don't loop with the coordinator's own zoom updates.
        if abs(scroll.magnification - zoom) > 0.0005 {
            scroll.magnification = zoom
        }
    }

    final class Coordinator: NSObject {
        weak var scroll: NSScrollView?
        var zoom: Binding<CGFloat>?
        private var observation: NSKeyValueObservation?

        func attach() {
            guard let scroll = scroll else { return }
            // KVO on `magnification` fires continuously during pinch, plus we also catch the
            // end event in case AppKit ever skips a final update.
            observation = scroll.observe(\.magnification, options: [.new]) { [weak self] _, change in
                guard let self, let zoom = self.zoom, let m = change.newValue else { return }
                if abs(zoom.wrappedValue - m) > 0.0005 {
                    DispatchQueue.main.async { zoom.wrappedValue = m }
                }
            }
            NotificationCenter.default.addObserver(
                self, selector: #selector(magnifyEnded),
                name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        }

        @objc private func magnifyEnded() {
            guard let scroll = scroll, let zoom = zoom else { return }
            let m = scroll.magnification
            if abs(zoom.wrappedValue - m) > 0.0005 {
                DispatchQueue.main.async { zoom.wrappedValue = m }
            }
        }

        deinit {
            observation?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
    }
}
