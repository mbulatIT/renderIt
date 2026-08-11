import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import AIImageEditorCore

struct EditorView: View {
    @ObservedObject var document: ProjectDocument
    let fileURL: URL?

    @State private var zoom: CGFloat = 0.25
    @State private var showExport = false

    var body: some View {
        VStack(spacing: 0) {
            PageTabBar(document: document)
            Divider()
            HSplitView {
                LayerListPanel(document: document)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

                CanvasView(document: document,
                           zoom: $zoom,
                           baseDirectory: fileURL?.deletingLastPathComponent())
                    .frame(minWidth: 400)

                InspectorPanel(document: document)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showExport) {
            ExportSheet(document: document.document,
                        pageId: document.selectedPageId,
                        baseDirectory: fileURL?.deletingLastPathComponent(),
                        isPresented: $showExport)
        }
        .onReceive(menuActionPublisher) { name in handleMenuAction(name) }
        .background(KeyShortcutCatcher(document: document,
                                       showExport: $showExport,
                                       zoom: $zoom))
    }

    /// All menu/notification triggers are collapsed into a single publisher and dispatched in
    /// one place. Keeping them as 20 separate `.onReceive` modifiers tipped the SwiftUI body
    /// type-checker past its budget.
    private var menuActionPublisher: AnyPublisher<Notification.Name, Never> {
        let names: [Notification.Name] = [
            .exportRequested, .undoRequested, .redoRequested,
            .copyRequested, .cutRequested, .pasteRequested,
            .deleteRequested, .duplicateRequested,
            .newPageRequested, .nextPageRequested, .prevPageRequested,
            .zoomInRequested, .zoomOutRequested, .zoomActualRequested, .zoomResetRequested,
            .bringToFrontRequested, .bringForwardRequested,
            .sendBackwardRequested, .sendToBackRequested,
        ]
        let streams = names.map { name in
            NotificationCenter.default.publisher(for: name)
                .map { _ in name }
                .eraseToAnyPublisher()
        }
        return Publishers.MergeMany(streams).eraseToAnyPublisher()
    }

    private func handleMenuAction(_ name: Notification.Name) {
        switch name {
        case .exportRequested:    showExport = true
        case .undoRequested:      document.undo()
        case .redoRequested:      document.redo()
        case .copyRequested:      handleCopy()
        case .cutRequested:       handleCut()
        case .pasteRequested:     handlePaste()
        case .deleteRequested:    handleDelete()
        case .duplicateRequested: handleDuplicate()
        case .newPageRequested:   document.mutate(.addPage(id: nil, name: nil, canvas: nil))
        case .nextPageRequested:  selectPage(offset: +1)
        case .prevPageRequested:  selectPage(offset: -1)
        case .zoomInRequested:     zoomBy(1.25)
        case .zoomOutRequested:    zoomBy(0.8)
        case .zoomActualRequested: zoom = 1.0
        case .zoomResetRequested:  zoom = 0.25
        case .bringToFrontRequested: handleZOrder(.front)
        case .bringForwardRequested: handleZOrder(.forward)
        case .sendBackwardRequested: handleZOrder(.backward)
        case .sendToBackRequested:   handleZOrder(.back)
        default: break
        }
    }

    private func zoomBy(_ factor: CGFloat) {
        zoom = max(0.05, min(2.0, zoom * factor))
    }

    private enum ZOrderAction { case front, back, forward, backward }
    private func handleZOrder(_ action: ZOrderAction) {
        let ids = document.selectedLayerIds
        guard !ids.isEmpty else { return }
        let pid = document.selectedPageId
        for id in ids {
            switch action {
            case .front:    document.mutate(.bringToFront(pageId: pid, id: id))
            case .back:     document.mutate(.sendToBack(pageId: pid, id: id))
            case .forward:  document.mutate(.moveForward(pageId: pid, id: id))
            case .backward: document.mutate(.moveBackward(pageId: pid, id: id))
            }
        }
    }

    private func handleCopy() {
        guard let id = document.selectedLayerId,
              let layer = document.selectedPage.layer(id: id) else { return }
        LayerClipboard.copy(layer)
    }
    private func handleCut() {
        guard let id = document.selectedLayerId,
              let layer = document.selectedPage.layer(id: id) else { return }
        LayerClipboard.copy(layer)
        document.mutate(.remove(pageId: document.selectedPageId, id: id))
        document.selectedLayerId = nil
    }
    private func handlePaste() {
        if let layer = LayerClipboard.paste() {
            let r = document.mutate(.insertLayer(pageId: document.selectedPageId, layer: layer))
            document.selectedLayerId = r?.newLayerId
        }
    }
    private func handleDuplicate() {
        let ids = document.selectedLayerIds
        guard !ids.isEmpty else { return }
        var newIds: Set<String> = []
        for id in ids {
            if let r = document.mutate(.duplicate(pageId: document.selectedPageId, id: id, newId: nil)),
               let nid = r.newLayerId {
                newIds.insert(nid)
            }
        }
        if !newIds.isEmpty { document.selectedLayerIds = newIds }
    }
    private func selectPage(offset: Int) {
        let pages = document.document.pages
        guard let idx = pages.firstIndex(where: { $0.id == document.selectedPageId }) else { return }
        let nIdx = (idx + offset + pages.count) % pages.count
        document.selectedPageId = pages[nIdx].id
        document.selectedLayerId = nil
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { addText() } label: { Label("Text", systemImage: "textformat") }
            Menu {
                Button("Rectangle") { addRect() }
                Button("Ellipse")   { addEllipse() }
                Button("Line")      { addLine() }
                Button("Arrow")     { addArrow() }
                Divider()
                Button("Triangle")  { addPolygon(sides: 3) }
                Button("Pentagon")  { addPolygon(sides: 5) }
                Button("Hexagon")   { addPolygon(sides: 6) }
                Button("Octagon")   { addPolygon(sides: 8) }
                Divider()
                Button("Star (5-pt)") { addStar(points: 5) }
                Button("Star (6-pt)") { addStar(points: 6) }
            } label: { Label("Shape", systemImage: "rectangle.on.rectangle") }
            Button { addGradient() } label: { Label("Gradient", systemImage: "square.righthalf.filled") }
            Button { addBlur() } label: { Label("Blur", systemImage: "drop.halffull") }
            Menu {
                ForEach(DeviceBezelCatalog.all, id: \.id) { bezel in
                    Button(bezel.title) { addBezel(bezel.id) }
                }
            } label: { Label("Bezel", systemImage: "iphone") }
            Button { importImage() } label: { Label("Image", systemImage: "photo") }
            Spacer()
            Button { document.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!document.canUndo)
            Button { document.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(!document.canRedo)
            Button { showExport = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
            HStack(spacing: 6) {
                Slider(value: $zoom, in: 0.05...1.5)
                    .frame(width: 100)
                Text("\(Int(zoom * 100))%").monospacedDigit().font(.caption)
            }
        }
    }

    // MARK: - Toolbar actions

    private var canvas: AIImageEditorCore.Canvas { document.selectedPage.canvas }

    private func addText() {
        let cw = Double(canvas.width)
        let frame = Frame(cw * 0.08, 200, cw * 0.84, 220)
        let payload = TextLayerPayload(text: "Edit me", fontSize: 96, fontWeight: .bold, color: .white)
        let r = document.mutate(.addText(pageId: document.selectedPageId, id: nil, payload: payload, frame: frame, z: nil))
        document.selectedLayerId = r?.newLayerId
    }

    private func addRect() {
        let frame = Frame(100, 100, 400, 400)
        let payload = ShapeLayerPayload(fill: (try? Color(hex: "#FFFFFF")) ?? .white, stroke: nil)
        let r = document.mutate(.addRect(pageId: document.selectedPageId, id: nil, payload: payload, frame: frame, z: nil))
        if let id = r?.newLayerId {
            document.mutate(.setCornerRadius(pageId: document.selectedPageId, id: id, value: 24))
            document.selectedLayerId = id
        }
    }

    private func addGradient() {
        let cw = Double(canvas.width), ch = Double(canvas.height)
        let frame = Frame(0, 0, cw, ch)
        let payload = GradientLayerPayload(
            type: .linear,
            stops: [
                .init(color: (try? Color(hex: "#1A1A2E")) ?? .black, at: 0),
                .init(color: (try? Color(hex: "#16213E")) ?? .black, at: 1),
            ],
            startX: 0, startY: 0, endX: 0, endY: 1)
        let r = document.mutate(.addGradient(pageId: document.selectedPageId, id: nil, payload: payload, frame: frame, z: nil))
        document.selectedLayerId = r?.newLayerId
    }

    private func addEllipse() {
        let frame = Frame(100, 100, 400, 400)
        let payload = ShapeLayerPayload(fill: (try? Color(hex: "#FFFFFF")) ?? .white, stroke: nil)
        let r = document.mutate(.addEllipse(pageId: document.selectedPageId, id: nil, payload: payload, frame: frame, z: nil))
        document.selectedLayerId = r?.newLayerId
    }

    private func addLine() {
        let cw = Double(canvas.width)
        let frame = Frame(cw * 0.1, 400, cw * 0.8, 8)
        let payload = LineLayerPayload(color: (try? Color(hex: "#FFFFFF")) ?? .white,
                                       width: 8, startX: 0, startY: 0.5, endX: 1, endY: 0.5)
        let r = document.mutate(.addLine(pageId: document.selectedPageId, id: nil, payload: payload, frame: frame, z: nil))
        document.selectedLayerId = r?.newLayerId
    }

    private func addArrow() {
        let cw = Double(canvas.width)
        let frame = Frame(cw * 0.1, 400, cw * 0.8, 80)
        let payload = LineLayerPayload(color: (try? Color(hex: "#FFFFFF")) ?? .white,
                                       width: 12, startX: 0, startY: 0.5, endX: 1, endY: 0.5,
                                       startArrow: false, endArrow: true)
        let r = document.mutate(.addLine(pageId: document.selectedPageId, id: nil, payload: payload, frame: frame, z: nil))
        document.selectedLayerId = r?.newLayerId
    }

    private func addPolygon(sides: Int) {
        let frame = Frame(100, 100, 400, 400)
        let payload = PolygonLayerPayload(sides: sides, fill: (try? Color(hex: "#FFFFFF")) ?? .white)
        let r = document.mutate(.addPolygon(pageId: document.selectedPageId, id: nil, payload: payload, frame: frame, z: nil))
        document.selectedLayerId = r?.newLayerId
    }

    private func addStar(points: Int) {
        let frame = Frame(100, 100, 400, 400)
        let payload = StarLayerPayload(points: points, innerRadius: 0.4,
                                       fill: (try? Color(hex: "#FFD60A")) ?? .white)
        let r = document.mutate(.addStar(pageId: document.selectedPageId, id: nil, payload: payload, frame: frame, z: nil))
        document.selectedLayerId = r?.newLayerId
    }

    private func addBlur() {
        let cw = Double(canvas.width)
        let frame = Frame(cw * 0.1, 200, cw * 0.8, 360)
        let payload = BlurLayerPayload(radius: 32, tint: nil)
        let r = document.mutate(.addBlur(pageId: document.selectedPageId, id: nil, payload: payload, frame: frame, z: nil))
        if let id = r?.newLayerId {
            document.mutate(.setCornerRadius(pageId: document.selectedPageId, id: id, value: 28))
            document.selectedLayerId = id
        }
    }

    private func addBezel(_ deviceId: String) {
        guard let bezel = DeviceBezelCatalog.find(id: deviceId) else { return }
        let height = Double(canvas.height) * 0.6
        let width = height * bezel.aspect
        let frame = AnchorPosition.center.frame(layerSize: (width, height), canvas: canvas)
        let payload = DeviceBezelPayload(device: deviceId)
        let r = document.mutate(.addDeviceBezel(pageId: document.selectedPageId, id: nil, payload: payload, frame: frame, z: nil))
        document.selectedLayerId = r?.newLayerId
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let assetId = "asset-\(document.document.assets.count + 1)"
        _ = document.mutate(.addAsset(id: assetId, path: url.path))
        // Frame = the image's natural pixel size (capped to the canvas). Place it at the
        // canvas centre for visibility; users can drag/resize from there.
        let natural = ProjectAssetHelper.naturalImageDefaultSize(fileURL: url, canvas: canvas)
        let w = natural?.w ?? 600
        let h = natural?.h ?? 600
        let frame = Frame((Double(canvas.width) - w) / 2, (Double(canvas.height) - h) / 2, w, h)
        // contentMode = .stretch so any subsequent resize follows the frame exactly.
        let r = document.mutate(.addImage(pageId: document.selectedPageId, id: nil, assetId: assetId,
                                          frame: frame, contentMode: .stretch, z: nil))
        document.selectedLayerId = r?.newLayerId
    }

    private func handleDelete() {
        let ids = document.selectedLayerIds
        guard !ids.isEmpty else { return }
        for id in ids {
            document.mutate(.remove(pageId: document.selectedPageId, id: id))
        }
        document.selectedLayerIds = []
    }
}

/// Catches global keyboard shortcuts at the window level so they fire even when no text field
/// has focus. Handles bindings that menu commands can't reach naturally — arrow-key nudge,
/// Tab cycling, Esc to deselect — plus a redundant catch for the standard editing shortcuts.
struct KeyShortcutCatcher: NSViewRepresentable {
    let document: ProjectDocument
    @Binding var showExport: Bool
    @Binding var zoom: CGFloat

    func makeNSView(context: Context) -> NSView {
        let v = ShortcutView()
        v.document = document
        v.exportTrigger = { showExport = true }
        v.zoomGet = { zoom }
        v.zoomSet = { zoom = $0 }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let v = nsView as? ShortcutView {
            v.document = document
            v.exportTrigger = { showExport = true }
            v.zoomGet = { zoom }
            v.zoomSet = { zoom = $0 }
        }
    }

    final class ShortcutView: NSView {
        weak var document: ProjectDocument?
        var exportTrigger: (() -> Void)?
        var zoomGet: (() -> CGFloat)?
        var zoomSet: ((CGFloat) -> Void)?
        private var monitor: Any?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                    self?.handle(event: e) == true ? nil : e
                }
            }
        }

        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }

        private func handle(event: NSEvent) -> Bool {
            guard let doc = document, event.window === self.window else { return false }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let cmd = flags.contains(.command)
            let shift = flags.contains(.shift)
            let option = flags.contains(.option)
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

            // Defer to text editing when typing — never swallow plain (non-Cmd) keys while a
            // text view has focus. This keeps arrow keys, Tab, Esc, etc. working inside fields.
            if let firstResponder = self.window?.firstResponder,
               firstResponder is NSTextView, !cmd {
                return false
            }

            if cmd && key == "z" {
                if shift { doc.redo() } else { doc.undo() }
                return true
            }
            if cmd && key == "c" {
                if let id = doc.selectedLayerId, let layer = doc.selectedPage.layer(id: id) {
                    LayerClipboard.copy(layer)
                    return true
                }
            }
            if cmd && key == "v" {
                if let layer = LayerClipboard.paste() {
                    let r = doc.mutate(.insertLayer(pageId: doc.selectedPageId, layer: layer))
                    doc.selectedLayerId = r?.newLayerId
                    return true
                }
            }
            if cmd && key == "n" {
                // New page in current project (Cmd+Shift+N still creates a new document via DocumentGroup)
                if !shift {
                    doc.mutate(.addPage(id: nil, name: nil, canvas: nil))
                    return true
                }
            }
            if cmd && key == "d" {
                if let id = doc.selectedLayerId {
                    let r = doc.mutate(.duplicate(pageId: doc.selectedPageId, id: id, newId: nil))
                    doc.selectedLayerId = r?.newLayerId
                    return true
                }
            }

            // Zoom: Cmd+= / Cmd++ / Cmd+- / Cmd+0 / Cmd+1. Mirrors the View menu so the
            // shortcut works even if the menu binding loses focus.
            if cmd && !shift && !option {
                if key == "=" || key == "+" {
                    setZoom(by: 1.25); return true
                }
                if key == "-" {
                    setZoom(by: 0.8); return true
                }
                if key == "0" {
                    zoomSet?(0.25); return true
                }
                if key == "1" {
                    zoomSet?(1.0); return true
                }
            }

            // Z-order: Cmd+Shift+] / [ for to-front / to-back; Cmd+Option+] / [ for forward / backward.
            if cmd && (key == "]" || key == "[") {
                guard let id = doc.selectedLayerId else { return false }
                let pid = doc.selectedPageId
                if shift && !option {
                    doc.mutate(key == "]" ? .bringToFront(pageId: pid, id: id)
                                          : .sendToBack(pageId: pid, id: id))
                    return true
                }
                if option && !shift {
                    doc.mutate(key == "]" ? .moveForward(pageId: pid, id: id)
                                          : .moveBackward(pageId: pid, id: id))
                    return true
                }
            }

            // Backspace / Delete
            if !cmd && (event.keyCode == 51 /* delete */ || event.keyCode == 117 /* fwd delete */) {
                if let id = doc.selectedLayerId {
                    doc.mutate(.remove(pageId: doc.selectedPageId, id: id))
                    doc.selectedLayerId = nil
                    return true
                }
            }

            // Esc → deselect (frees the inspector to show page settings).
            if !cmd && event.keyCode == 53 /* esc */ {
                if doc.selectedLayerId != nil {
                    doc.selectedLayerId = nil
                    return true
                }
                return false
            }

            // Tab / Shift+Tab → cycle through the layer stack in render order.
            if !cmd && event.keyCode == 48 /* tab */ {
                cycleLayer(forward: !shift, doc: doc)
                return true
            }

            // Arrow keys → nudge the selected layer. Shift = 10px steps. Repeats (key held
            // down) update the same undo step instead of stacking dozens of entries.
            if !cmd, let delta = arrowDelta(keyCode: event.keyCode, shift: shift) {
                nudge(dx: delta.dx, dy: delta.dy, isRepeat: event.isARepeat, doc: doc)
                return true
            }

            return false
        }

        private func setZoom(by factor: CGFloat) {
            guard let get = zoomGet, let set = zoomSet else { return }
            set(max(0.05, min(2.0, get() * factor)))
        }

        private func arrowDelta(keyCode: UInt16, shift: Bool) -> (dx: Double, dy: Double)? {
            let step: Double = shift ? 10 : 1
            switch keyCode {
            case 123: return (-step, 0)   // left
            case 124: return ( step, 0)   // right
            case 125: return (0,  step)   // down
            case 126: return (0, -step)   // up
            default:  return nil
            }
        }

        private func nudge(dx: Double, dy: Double, isRepeat: Bool, doc: ProjectDocument) {
            let ids = doc.selectedLayerIds
            guard !ids.isEmpty else { return }
            // First press = one new undo entry. Auto-repeat ticks fold into the same entry.
            if !isRepeat { doc.beginUndoableEdit() }
            var working = doc.document
            for id in ids {
                guard let layer = findLayerInPage(id: id, doc: doc) else { continue }
                _ = try? CommandEngine.apply(
                    .move(pageId: doc.selectedPageId, id: id,
                          to: (layer.frame.x + dx, layer.frame.y + dy)),
                    to: &working)
            }
            doc.objectWillChange.send()
            doc.document = working
        }

        /// Resolve a layer id against the active page, walking into groups so nested children
        /// can still be nudged when multi-selected.
        private func findLayerInPage(id: String, doc: ProjectDocument) -> Layer? {
            func search(_ layers: [Layer]) -> Layer? {
                for l in layers {
                    if l.id == id { return l }
                    if case .group(let g) = l.payload, let f = search(g.children) { return f }
                }
                return nil
            }
            return search(doc.selectedPage.layers)
        }

        private func cycleLayer(forward: Bool, doc: ProjectDocument) {
            let order = doc.selectedPage.renderOrder
            guard !order.isEmpty else { return }
            if let cur = doc.selectedLayerId,
               let idx = order.firstIndex(where: { $0.id == cur }) {
                let next = (idx + (forward ? 1 : -1) + order.count) % order.count
                doc.selectedLayerId = order[next].id
            } else {
                doc.selectedLayerId = forward ? order.first?.id : order.last?.id
            }
        }
    }
}
