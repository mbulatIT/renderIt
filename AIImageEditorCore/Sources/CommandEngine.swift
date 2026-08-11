import Foundation

/// Typed mutations on a Document. Each case maps 1:1 to a CLI subcommand and an MCP tool.
public enum EditorCommand {
    // Page lifecycle
    case addPage(id: String?, name: String?, canvas: Canvas?)
    case removePage(id: String)
    case renamePage(id: String, name: String)
    case selectPage(id: String)
    case setLayout(pageId: String?, layout: PageLayout)

    // Previews (export viewports on a page)
    /// Add or remove previews so the page has exactly `count` previews. New previews use the
    /// page's current `PageLayout.previewWidth/Height/spacing`.
    case setPreviewCount(pageId: String?, count: Int)
    case addPreview(pageId: String?, id: String?, name: String?, background: Color?)
    case removePreview(pageId: String?, id: String)
    case renamePreview(pageId: String?, id: String, name: String)
    case setPreviewBackground(pageId: String?, id: String, color: Color)
    /// Update the page's default preview size + spacing and relayout the existing previews.
    case setPreviewSize(pageId: String?, width: Double, height: Double)
    case setPreviewSpacing(pageId: String?, spacing: Double)

    // Canvas (per page)
    case setCanvas(pageId: String?, width: Int, height: Int)
    case setBackground(pageId: String?, color: Color)

    // Add layers
    case addImage(pageId: String?, id: String?, assetId: String, frame: Frame, contentMode: ContentMode, z: Double?)
    case addText(pageId: String?, id: String?, payload: TextLayerPayload, frame: Frame, z: Double?)
    case addRect(pageId: String?, id: String?, payload: ShapeLayerPayload, frame: Frame, z: Double?)
    case addEllipse(pageId: String?, id: String?, payload: ShapeLayerPayload, frame: Frame, z: Double?)
    case addDeviceBezel(pageId: String?, id: String?, payload: DeviceBezelPayload, frame: Frame, z: Double?)
    case addGradient(pageId: String?, id: String?, payload: GradientLayerPayload, frame: Frame, z: Double?)
    case addBlur(pageId: String?, id: String?, payload: BlurLayerPayload, frame: Frame, z: Double?)
    case addLine(pageId: String?, id: String?, payload: LineLayerPayload, frame: Frame, z: Double?)
    case addPolygon(pageId: String?, id: String?, payload: PolygonLayerPayload, frame: Frame, z: Double?)
    case addStar(pageId: String?, id: String?, payload: StarLayerPayload, frame: Frame, z: Double?)
    /// Set or clear a layer's drop shadow. Applies uniformly to any layer kind (text, shape, image, bezel, gradient).
    case setShadow(pageId: String?, id: String, shadow: Shadow?)
    /// Set the corner radius applied to a layer. `0` disables corner rounding.
    case setCornerRadius(pageId: String?, id: String, value: Double)
    /// Set the corner-radius shape (arc/continuous/cut). Ignored when cornerRadius is 0.
    case setCornerStyle(pageId: String?, id: String, style: CornerStyle)
    /// Set which corners the cornerRadius rounds. Pass `.all` for every corner (the default), or a
    /// subset to round only those. Ignored when cornerRadius is 0.
    case setRoundedCorners(pageId: String?, id: String, corners: RectCorners)
    /// Set or clear a layer's optional background fill (solid color or gradient).
    case setLayerBackground(pageId: String?, id: String, background: LayerBackground?)
    /// Set or clear a layer-level gradient fill. Passing nil clears it. Has no effect on
    /// blur/deviceBezel/.gradient kind layers (those carry their own fill).
    case setLayerGradient(pageId: String?, id: String, gradient: GradientLayerPayload?)

    // Position / shape / lifetime
    case move(pageId: String?, id: String, to: (Double, Double))
    case resize(pageId: String?, id: String, w: Double?, h: Double?)
    case setFrame(pageId: String?, id: String, frame: Frame)
    case rotate(pageId: String?, id: String, degrees: Double)
    case setOpacity(pageId: String?, id: String, value: Double)
    case setVisible(pageId: String?, id: String, value: Bool)
    case setBlendMode(pageId: String?, id: String, mode: BlendMode)
    case rename(pageId: String?, id: String, name: String)
    case duplicate(pageId: String?, id: String, newId: String?)
    case remove(pageId: String?, id: String)

    // Insert an existing-shaped layer (used by paste). Returns a new id if conflict.
    case insertLayer(pageId: String?, layer: Layer)

    /// Bundle one or more existing layers into a new `group` layer. The group's frame is the
    /// union of the children's frames. Children are removed from the top-level layer list and
    /// become the group's nested children.
    case addGroup(pageId: String?, id: String?, name: String?, childIds: [String])
    /// Replace a group layer with its children promoted back to the top-level layer list.
    case ungroup(pageId: String?, id: String)
    /// Toggle whether a group crops its children's drawing to its frame bounds (the union of the
    /// children's frames, respecting cornerRadius/cornerStyle). No-op on non-group layers.
    case setGroupClipsToBounds(pageId: String?, id: String, value: Bool)
    /// Relocate a layer within the page's layer tree. Pass `intoGroupId: nil` to promote the
    /// layer to top-level, or a group id to nest it as a child of that group. Source location
    /// (top-level vs nested) is detected automatically. If `beforeLayerId` is provided, the
    /// layer is inserted before that sibling; otherwise it's appended at the end. Refuses to
    /// move a group into itself or any of its descendants.
    case moveLayer(pageId: String?, layerId: String, intoGroupId: String?, beforeLayerId: String?)

    // Text-only
    case setText(pageId: String?, id: String, text: String)
    case setFont(pageId: String?, id: String, family: String?, size: Double?, weight: FontWeight?, italic: Bool?)
    case setColor(pageId: String?, id: String, color: Color)
    case setAlignment(pageId: String?, id: String, alignment: TextAlignment)
    /// Set the color *variant* of an image-backed device bezel. Pass nil to clear.
    case setBezelColor(pageId: String?, id: String, color: String?)
    /// Set / clear the screenshot drawn inside a device bezel. Pass nil for `assetId` to clear.
    case setBezelScreenshot(pageId: String?, id: String, assetId: String?)
    /// Replace a gradient layer's payload wholesale.
    case setGradientPayload(pageId: String?, id: String, payload: GradientLayerPayload)
    /// Replace a blur layer's payload wholesale.
    case setBlurPayload(pageId: String?, id: String, payload: BlurLayerPayload)

    // Z-order
    case setZIndex(pageId: String?, id: String, value: Double)
    case bringToFront(pageId: String?, id: String)
    case sendToBack(pageId: String?, id: String)
    case moveForward(pageId: String?, id: String)
    case moveBackward(pageId: String?, id: String)

    // Assets (document-level)
    case addAsset(id: String, path: String)
    case removeAsset(id: String)
}

public struct EditorCommandResult: Sendable {
    public var message: String
    public var newLayerId: String?
    public var newPageId: String?
    public var newAssetId: String?
}

public enum CommandEngine {

    /// Apply a single command to a document. After the underlying command runs, every page is
    /// post-processed so each group's frame is the axis-aligned union of its current children
    /// — that way groups stay glued to their contents through any add/remove/move/resize.
    @discardableResult
    public static func apply(_ command: EditorCommand, to doc: inout Document) throws -> EditorCommandResult {
        let result = try applyCommand(command, to: &doc)
        for i in 0..<doc.pages.count {
            recomputeGroupFrames(in: &doc.pages[i].layers)
        }
        return result
    }

    /// Core command dispatch — kept private so the public entry point can run post-processing
    /// uniformly after every mutation.
    @discardableResult
    private static func applyCommand(_ command: EditorCommand, to doc: inout Document) throws -> EditorCommandResult {
        switch command {

        // MARK: - Pages

        case .addPage(let id, let name, let canvas):
            let pid = try ensureUniquePageId(in: doc, suggested: id)
            let c = canvas ?? doc.activePage.canvas
            let p = Page(id: pid, name: name ?? "Page \(doc.pages.count + 1)", canvas: c)
            doc.pages.append(p)
            doc.activePageId = pid
            return .init(message: "added page \(pid)", newLayerId: nil, newPageId: pid, newAssetId: nil)

        case .removePage(let id):
            guard doc.pageIndex(id: id) != nil else { throw EditorError.layerNotFound("page:\(id)") }
            doc.pages.removeAll { $0.id == id }
            if doc.activePageId == id { doc.activePageId = doc.pages.first?.id }
            if doc.pages.isEmpty {
                let p = Page(id: "page-1", name: "Page 1", canvas: Canvas(width: 1290, height: 2796))
                doc.pages.append(p)
                doc.activePageId = p.id
            }
            return .init(message: "removed page \(id)", newLayerId: nil, newPageId: nil, newAssetId: nil)

        case .renamePage(let id, let name):
            try doc.updatePage(id: id) { $0.name = name }
            return .init(message: "renamed page \(id) → \(name)", newLayerId: nil, newPageId: nil, newAssetId: nil)

        case .selectPage(let id):
            guard doc.page(id: id) != nil else { throw EditorError.layerNotFound("page:\(id)") }
            doc.activePageId = id
            return .init(message: "selected page \(id)", newLayerId: nil, newPageId: id, newAssetId: nil)

        case .setLayout(let pid, let layout):
            let pageId = pid ?? doc.activePage.id
            try doc.updatePage(id: pageId) {
                $0.layout = layout
                Page.relayout(&$0)
            }
            return .init(message: "set layout on \(pageId)", newLayerId: nil, newPageId: pageId, newAssetId: nil)

        case .setPreviewCount(let pid, let count):
            let pageId = pid ?? doc.activePage.id
            try doc.updatePage(id: pageId) { page in
                let desired = max(0, count)
                if desired > page.previews.count {
                    while page.previews.count < desired {
                        let n = page.previews.count + 1
                        let pid = "\(page.id)-preview-\(n)"
                        let sourceBg = page.previews.last?.background ?? page.canvas.background
                        page.previews.append(Preview(
                            id: pid,
                            name: "Preview \(n)",
                            frame: Frame(0, 0, page.layout.previewWidth, page.layout.previewHeight),
                            background: Preview.solidify(sourceBg)))
                    }
                } else if desired < page.previews.count {
                    page.previews.removeLast(page.previews.count - desired)
                }
                Page.relayout(&page)
            }
            return .init(message: "previews on \(pageId) → \(count)", newLayerId: nil, newPageId: pageId, newAssetId: nil)

        case .addPreview(let pid, let id, let name, let bg):
            let pageId = pid ?? doc.activePage.id
            var newId: String = ""
            try doc.updatePage(id: pageId) { page in
                let chosen = id ?? page.nextPreviewId()
                if page.preview(id: chosen) != nil { return }
                newId = chosen
                let sourceBg = bg ?? page.previews.last?.background ?? page.canvas.background
                page.previews.append(Preview(
                    id: chosen,
                    name: name ?? "Preview \(page.previews.count + 1)",
                    frame: Frame(0, 0, page.layout.previewWidth, page.layout.previewHeight),
                    background: Preview.solidify(sourceBg)))
                Page.relayout(&page)
            }
            return .init(message: "added preview \(newId)", newLayerId: nil, newPageId: pageId, newAssetId: nil)

        case .removePreview(let pid, let id):
            let pageId = pid ?? doc.activePage.id
            try doc.updatePage(id: pageId) { page in
                page.previews.removeAll { $0.id == id }
                if page.previews.isEmpty {
                    // Keep at least one preview so the page has somewhere to render to.
                    page.previews.append(Preview(
                        id: page.nextPreviewId(),
                        name: "Preview 1",
                        frame: Frame(0, 0, page.layout.previewWidth, page.layout.previewHeight),
                        background: page.canvas.background))
                }
                Page.relayout(&page)
            }
            return .init(message: "removed preview \(id)", newLayerId: nil, newPageId: pageId, newAssetId: nil)

        case .renamePreview(let pid, let id, let name):
            let pageId = pid ?? doc.activePage.id
            try doc.updatePage(id: pageId) { page in
                if let idx = page.previews.firstIndex(where: { $0.id == id }) {
                    page.previews[idx].name = name
                }
            }
            return .init(message: "renamed preview \(id) → \(name)", newLayerId: nil, newPageId: pageId, newAssetId: nil)

        case .setPreviewBackground(let pid, let id, let color):
            let pageId = pid ?? doc.activePage.id
            let solid = Preview.solidify(color)
            try doc.updatePage(id: pageId) { page in
                if let idx = page.previews.firstIndex(where: { $0.id == id }) {
                    page.previews[idx].background = solid
                }
            }
            return .init(message: "preview bg \(id) → \(solid.hex)", newLayerId: nil, newPageId: pageId, newAssetId: nil)

        case .setPreviewSize(let pid, let w, let h):
            let pageId = pid ?? doc.activePage.id
            try doc.updatePage(id: pageId) { page in
                page.layout.previewWidth = max(1, w)
                page.layout.previewHeight = max(1, h)
                Page.relayout(&page)
            }
            return .init(message: "preview size on \(pageId) → \(Int(w))x\(Int(h))",
                         newLayerId: nil, newPageId: pageId, newAssetId: nil)

        case .setPreviewSpacing(let pid, let spacing):
            let pageId = pid ?? doc.activePage.id
            try doc.updatePage(id: pageId) { page in
                page.layout.spacing = max(0, spacing)
                Page.relayout(&page)
            }
            return .init(message: "preview spacing on \(pageId) → \(spacing)",
                         newLayerId: nil, newPageId: pageId, newAssetId: nil)

        // MARK: - Canvas

        case .setCanvas(let pid, let w, let h):
            let pageId = pid ?? doc.activePage.id
            try doc.updatePage(id: pageId) {
                $0.canvas.width = max(1, w)
                $0.canvas.height = max(1, h)
            }
            return .init(message: "canvas \(w)x\(h)", newLayerId: nil, newPageId: pageId, newAssetId: nil)

        case .setBackground(let pid, let color):
            let pageId = pid ?? doc.activePage.id
            try doc.updatePage(id: pageId) { $0.canvas.background = color }
            return .init(message: "background \(color.hex)", newLayerId: nil, newPageId: pageId, newAssetId: nil)

        // MARK: - Add

        case .addImage(let pid, let id, let assetId, let frame, let mode, let z):
            guard doc.assets[assetId] != nil else { throw EditorError.assetNotFound(assetId) }
            let pageId = pid ?? doc.activePage.id
            let newId = try uniqueLayerId(in: doc, pageId: pageId, suggested: id, prefix: "image")
            try doc.updatePage(id: pageId) { page in
                let layer = Layer(id: newId, kind: .image, frame: frame,
                                  zIndex: z ?? (page.topZIndex + 1),
                                  payload: .image(.init(assetId: assetId, contentMode: mode)))
                page.layers.append(layer)
            }
            return .init(message: "added image \(newId)", newLayerId: newId, newPageId: pageId, newAssetId: nil)

        case .addText(let pid, let id, let payload, let frame, let z):
            let pageId = pid ?? doc.activePage.id
            let newId = try uniqueLayerId(in: doc, pageId: pageId, suggested: id, prefix: "text")
            try doc.updatePage(id: pageId) { page in
                let layer = Layer(id: newId, kind: .text, frame: frame,
                                  zIndex: z ?? (page.topZIndex + 1),
                                  payload: .text(payload))
                page.layers.append(layer)
            }
            return .init(message: "added text \(newId)", newLayerId: newId, newPageId: pageId, newAssetId: nil)

        case .addRect(let pid, let id, let payload, let frame, let z):
            let pageId = pid ?? doc.activePage.id
            let newId = try uniqueLayerId(in: doc, pageId: pageId, suggested: id, prefix: "rect")
            try doc.updatePage(id: pageId) { page in
                page.layers.append(.init(id: newId, kind: .rect, frame: frame,
                                         zIndex: z ?? (page.topZIndex + 1),
                                         payload: .rect(payload)))
            }
            return .init(message: "added rect \(newId)", newLayerId: newId, newPageId: pageId, newAssetId: nil)

        case .addEllipse(let pid, let id, let payload, let frame, let z):
            let pageId = pid ?? doc.activePage.id
            let newId = try uniqueLayerId(in: doc, pageId: pageId, suggested: id, prefix: "ellipse")
            try doc.updatePage(id: pageId) { page in
                page.layers.append(.init(id: newId, kind: .ellipse, frame: frame,
                                         zIndex: z ?? (page.topZIndex + 1),
                                         payload: .ellipse(payload)))
            }
            return .init(message: "added ellipse \(newId)", newLayerId: newId, newPageId: pageId, newAssetId: nil)

        case .addDeviceBezel(let pid, let id, let payload, let frame, let z):
            guard DeviceBezelCatalog.find(id: payload.device) != nil else {
                throw EditorError.unknownBezel(payload.device)
            }
            if let aId = payload.screenshotAssetId, doc.assets[aId] == nil {
                throw EditorError.assetNotFound(aId)
            }
            let pageId = pid ?? doc.activePage.id
            let newId = try uniqueLayerId(in: doc, pageId: pageId, suggested: id, prefix: "bezel")
            try doc.updatePage(id: pageId) { page in
                page.layers.append(.init(id: newId, kind: .deviceBezel, frame: frame,
                                         zIndex: z ?? (page.topZIndex + 1),
                                         payload: .deviceBezel(payload)))
            }
            return .init(message: "added bezel \(newId)", newLayerId: newId, newPageId: pageId, newAssetId: nil)

        case .addGradient(let pid, let id, let payload, let frame, let z):
            let pageId = pid ?? doc.activePage.id
            let newId = try uniqueLayerId(in: doc, pageId: pageId, suggested: id, prefix: "gradient")
            try doc.updatePage(id: pageId) { page in
                page.layers.append(.init(id: newId, kind: .gradient, frame: frame,
                                         zIndex: z ?? (page.topZIndex + 1),
                                         payload: .gradient(payload)))
            }
            return .init(message: "added gradient \(newId)", newLayerId: newId, newPageId: pageId, newAssetId: nil)

        case .addLine(let pid, let id, let payload, let frame, let z):
            let pageId = pid ?? doc.activePage.id
            let newId = try uniqueLayerId(in: doc, pageId: pageId, suggested: id, prefix: "line")
            try doc.updatePage(id: pageId) { page in
                page.layers.append(.init(id: newId, kind: .line, frame: frame,
                                         zIndex: z ?? (page.topZIndex + 1),
                                         payload: .line(payload)))
            }
            return .init(message: "added line \(newId)", newLayerId: newId, newPageId: pageId, newAssetId: nil)

        case .addPolygon(let pid, let id, let payload, let frame, let z):
            let pageId = pid ?? doc.activePage.id
            let newId = try uniqueLayerId(in: doc, pageId: pageId, suggested: id, prefix: "polygon")
            try doc.updatePage(id: pageId) { page in
                page.layers.append(.init(id: newId, kind: .polygon, frame: frame,
                                         zIndex: z ?? (page.topZIndex + 1),
                                         payload: .polygon(payload)))
            }
            return .init(message: "added polygon \(newId)", newLayerId: newId, newPageId: pageId, newAssetId: nil)

        case .addStar(let pid, let id, let payload, let frame, let z):
            let pageId = pid ?? doc.activePage.id
            let newId = try uniqueLayerId(in: doc, pageId: pageId, suggested: id, prefix: "star")
            try doc.updatePage(id: pageId) { page in
                page.layers.append(.init(id: newId, kind: .star, frame: frame,
                                         zIndex: z ?? (page.topZIndex + 1),
                                         payload: .star(payload)))
            }
            return .init(message: "added star \(newId)", newLayerId: newId, newPageId: pageId, newAssetId: nil)

        case .setCornerRadius(let pid, let id, let value):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.cornerRadius = max(0, value) }
            return .init(message: "cornerRadius \(id) → \(value)",
                         newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setCornerStyle(let pid, let id, let style):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.cornerStyle = style }
            return .init(message: "cornerStyle \(id) → \(style.rawValue)",
                         newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setRoundedCorners(let pid, let id, let corners):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.roundedCorners = corners }
            let label = corners == .all ? "all" : (corners.isEmpty ? "none" : corners.names.joined(separator: ","))
            return .init(message: "roundedCorners \(id) → \(label)",
                         newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setLayerBackground(let pid, let id, let background):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.background = background }
            return .init(message: "background \(id) → \(background == nil ? "(cleared)" : "set")",
                         newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setLayerGradient(let pid, let id, let gradient):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.gradient = gradient }
            return .init(message: "gradient \(id) → \(gradient == nil ? "(cleared)" : "set")",
                         newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setShadow(let pid, let id, let shadow):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.shadow = shadow }
            return .init(message: "shadow \(id) → \(shadow == nil ? "(cleared)" : "set")",
                         newLayerId: id, newPageId: nil, newAssetId: nil)

        case .addBlur(let pid, let id, let payload, let frame, let z):
            let pageId = pid ?? doc.activePage.id
            let newId = try uniqueLayerId(in: doc, pageId: pageId, suggested: id, prefix: "blur")
            try doc.updatePage(id: pageId) { page in
                page.layers.append(.init(id: newId, kind: .blur, frame: frame,
                                         zIndex: z ?? (page.topZIndex + 1),
                                         payload: .blur(payload)))
            }
            return .init(message: "added blur \(newId)", newLayerId: newId, newPageId: pageId, newAssetId: nil)

        case .addGroup(let pid, let id, let name, let childIds):
            let pageId = pid ?? doc.activePage.id
            let groupId = try uniqueLayerId(in: doc, pageId: pageId, suggested: id, prefix: "group")
            guard let page = doc.page(id: pageId) else {
                throw EditorError.layerNotFound("page:\(pageId)")
            }
            // Validate up front — updatePage's closure can't throw.
            let childSet = Set(childIds)
            let extracted = page.layers.filter { childSet.contains($0.id) }
            guard !extracted.isEmpty else {
                throw EditorError.layerNotFound(childIds.joined(separator: ","))
            }
            var minX = Double.infinity, minY = Double.infinity
            var maxX = -Double.infinity, maxY = -Double.infinity
            for layer in extracted {
                let f = layer.frame
                minX = min(minX, f.x);       minY = min(minY, f.y)
                maxX = max(maxX, f.x + f.w); maxY = max(maxY, f.y + f.h)
            }
            let frame = Frame(minX, minY, maxX - minX, maxY - minY)
            try doc.updatePage(id: pageId) { page in
                let remaining = page.layers.filter { !childSet.contains($0.id) }
                let topZ = (remaining.map(\.zIndex).max() ?? 0) + 1
                let group = Layer(id: groupId, name: name ?? groupId, kind: .group, frame: frame,
                                  zIndex: topZ, payload: .group(.init(children: extracted)))
                page.layers = remaining + [group]
            }
            return .init(message: "grouped \(extracted.count) layers → \(groupId)",
                         newLayerId: groupId, newPageId: pageId, newAssetId: nil)

        case .moveLayer(let pid, let layerId, let intoGroupId, let beforeLayerId):
            let pageId = pid ?? doc.activePage.id
            guard let page = doc.page(id: pageId) else {
                throw EditorError.layerNotFound("page:\(pageId)")
            }
            // Detect cycle: target group cannot equal the moved layer or live inside it.
            if let target = intoGroupId {
                if target == layerId {
                    throw EditorError.usage("cannot move \(layerId) into itself")
                }
                if isDescendant(target, ofGroupId: layerId, in: page.layers) {
                    throw EditorError.usage("cannot move \(layerId) into its own descendant \(target)")
                }
            }
            var found = false
            try doc.updatePage(id: pageId) { page in
                guard let extracted = extractLayer(from: &page.layers, id: layerId) else { return }
                found = true
                insertLayer(extracted, into: &page.layers, intoGroupId: intoGroupId, beforeLayerId: beforeLayerId)
            }
            if !found { throw EditorError.layerNotFound(layerId) }
            return .init(message: "moved \(layerId) → \(intoGroupId ?? "(root)")",
                         newLayerId: layerId, newPageId: pageId, newAssetId: nil)

        case .ungroup(let pid, let id):
            let pageId = pid ?? doc.activePage.id
            guard let page = doc.page(id: pageId),
                  let target = page.layer(id: id) else {
                throw EditorError.layerNotFound(id)
            }
            guard case .group(let g) = target.payload else {
                throw EditorError.usage("\(id) is not a group")
            }
            let baseZ = target.zIndex
            try doc.updatePage(id: pageId) { page in
                page.layers.removeAll { $0.id == id }
                for child in g.children {
                    var c = child
                    c.zIndex = baseZ
                    page.layers.append(c)
                }
            }
            return .init(message: "ungrouped \(id) → \(g.children.count) layers",
                         newLayerId: nil, newPageId: pageId, newAssetId: nil)

        case .setGroupClipsToBounds(let pid, let id, let v):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { l in
                guard case .group(var g) = l.payload else { return }
                g.clipsToBounds = v
                l.payload = .group(g)
            }
            return .init(message: "clipToBounds \(id) → \(v)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .insertLayer(let pid, let layer):
            let pageId = pid ?? doc.activePage.id
            var l = layer
            l.id = try uniqueLayerId(in: doc, pageId: pageId, suggested: l.id, prefix: l.kind.rawValue)
            try doc.updatePage(id: pageId) { page in
                l.zIndex = page.topZIndex + 1
                page.layers.append(l)
            }
            return .init(message: "inserted \(l.id)", newLayerId: l.id, newPageId: pageId, newAssetId: nil)

        // MARK: - Edits

        case .move(let pid, let id, let to):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { l in
                let old = l.frame
                l.frame.x = to.0; l.frame.y = to.1
                // Groups: shift every nested child by the same delta (sx=sy=1 since w/h unchanged).
                applyGroupFrameChange(&l, oldFrame: old)
            }
            return .init(message: "moved \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .resize(let pid, let id, let w, let h):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { l in
                let old = l.frame
                if let w { l.frame.w = max(0, w) }
                if let h { l.frame.h = max(0, h) }
                // Groups: scale every nested child proportionally to the new dimensions.
                applyGroupFrameChange(&l, oldFrame: old)
            }
            return .init(message: "resized \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setFrame(let pid, let id, let frame):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { l in
                let old = l.frame
                l.frame = frame
                // Groups: translate AND scale children to match the new frame.
                applyGroupFrameChange(&l, oldFrame: old)
            }
            return .init(message: "set frame on \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .rotate(let pid, let id, let deg):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.rotation = deg }
            return .init(message: "rotated \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setOpacity(let pid, let id, let v):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.opacity = max(0, min(1, v)) }
            return .init(message: "opacity \(id) → \(v)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setVisible(let pid, let id, let v):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.visible = v }
            return .init(message: "visible \(id) → \(v)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setBlendMode(let pid, let id, let mode):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.blendMode = mode }
            return .init(message: "blend \(id) → \(mode.rawValue)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .rename(let pid, let id, let name):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.name = name }
            return .init(message: "renamed \(id) → \(name)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .duplicate(let pid, let id, let newId):
            let pageId = pid ?? doc.activePage.id
            guard let src = doc.page(id: pageId)?.layer(id: id) else { throw EditorError.layerNotFound(id) }
            let copyId = try uniqueLayerId(in: doc, pageId: pageId, suggested: newId, prefix: src.id + "-copy")
            var copy = src
            copy.id = copyId
            copy.name = copyId
            let dx = 20.0, dy = 20.0
            copy.frame.x += dx
            copy.frame.y += dy
            // For groups, slide the children along with the group's frame so the duplicate is a
            // faithful copy of the composition, just shifted by (dx, dy).
            if case .group(var g) = copy.payload {
                translate(layers: &g.children, dx: dx, dy: dy)
                copy.payload = .group(g)
            }
            try doc.updatePage(id: pageId) { page in
                copy.zIndex = page.topZIndex + 1
                page.layers.append(copy)
            }
            return .init(message: "duplicated \(id) → \(copyId)", newLayerId: copyId, newPageId: pageId, newAssetId: nil)

        case .remove(let pid, let id):
            let pageId = pid ?? doc.activePage.id
            var found = false
            try doc.updatePage(id: pageId) { page in
                let before = page.layers.count
                page.layers.removeAll { $0.id == id }
                found = page.layers.count < before
            }
            if !found { throw EditorError.layerNotFound(id) }
            return .init(message: "removed \(id)", newLayerId: nil, newPageId: pageId, newAssetId: nil)

        // text edits

        case .setText(let pid, let id, let text):
            try mutateText(in: &doc, pageId: pid, layerId: id) { $0.text = text }
            return .init(message: "set text on \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setFont(let pid, let id, let family, let size, let weight, let italic):
            try mutateText(in: &doc, pageId: pid, layerId: id) { p in
                if let family { p.font = family }
                if let size { p.fontSize = size }
                if let weight { p.fontWeight = weight }
                if let italic { p.italic = italic }
            }
            return .init(message: "set font on \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setColor(let pid, let id, let color):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { l in
                switch l.payload {
                case .text(var p):       p.color = color; l.payload = .text(p)
                case .rect(var p):       p.fill = color;  l.payload = .rect(p)
                case .ellipse(var p):    p.fill = color;  l.payload = .ellipse(p)
                case .deviceBezel(var p):p.chromeColor = color; l.payload = .deviceBezel(p)
                case .blur(var p):       p.tint = color;  l.payload = .blur(p)
                case .line(var p):       p.color = color; l.payload = .line(p)
                case .polygon(var p):    p.fill = color;  l.payload = .polygon(p)
                case .star(var p):       p.fill = color;  l.payload = .star(p)
                case .image, .group, .gradient: break
                }
            }
            return .init(message: "set color on \(id) → \(color.hex)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setAlignment(let pid, let id, let a):
            try mutateText(in: &doc, pageId: pid, layerId: id) { $0.alignment = a }
            return .init(message: "alignment \(id) → \(a.rawValue)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setBezelColor(let pid, let id, let color):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { l in
                guard case .deviceBezel(var p) = l.payload else { return }
                p.color = color
                l.payload = .deviceBezel(p)
            }
            return .init(message: "bezel color \(id) → \(color ?? "default")",
                         newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setGradientPayload(let pid, let id, let payload):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { l in
                guard case .gradient = l.payload else { return }
                l.payload = .gradient(payload)
            }
            return .init(message: "set gradient on \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setBlurPayload(let pid, let id, let payload):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { l in
                guard case .blur = l.payload else { return }
                l.payload = .blur(payload)
            }
            return .init(message: "set blur on \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .setBezelScreenshot(let pid, let id, let assetId):
            if let aid = assetId, doc.assets[aid] == nil {
                throw EditorError.assetNotFound(aid)
            }
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { l in
                guard case .deviceBezel(var p) = l.payload else { return }
                p.screenshotAssetId = assetId
                l.payload = .deviceBezel(p)
            }
            return .init(message: "bezel screenshot \(id) → \(assetId ?? "(cleared)")",
                         newLayerId: id, newPageId: nil, newAssetId: nil)

        // z-order

        case .setZIndex(let pid, let id, let v):
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.zIndex = v }
            return .init(message: "zIndex \(id) → \(v)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .bringToFront(let pid, let id):
            let pageId = pid ?? doc.activePage.id
            let newZ = (doc.page(id: pageId)?.topZIndex ?? 0) + 1
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.zIndex = newZ }
            return .init(message: "front \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .sendToBack(let pid, let id):
            let pageId = pid ?? doc.activePage.id
            let newZ = (doc.page(id: pageId)?.lowestZIndex ?? 0) - 1
            try mutateLayer(in: &doc, pageId: pid, layerId: id) { $0.zIndex = newZ }
            return .init(message: "back \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .moveForward(let pid, let id):
            try shiftZ(in: &doc, pageId: pid, layerId: id, direction: +1)
            return .init(message: "forward \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        case .moveBackward(let pid, let id):
            try shiftZ(in: &doc, pageId: pid, layerId: id, direction: -1)
            return .init(message: "backward \(id)", newLayerId: id, newPageId: nil, newAssetId: nil)

        // assets

        case .addAsset(let id, let path):
            if doc.assets[id] != nil { throw EditorError.duplicateAssetId(id) }
            doc.assets[id] = Asset(path: path)
            return .init(message: "added asset \(id)", newLayerId: nil, newPageId: nil, newAssetId: id)

        case .removeAsset(let id):
            if doc.assets.removeValue(forKey: id) == nil { throw EditorError.assetNotFound(id) }
            return .init(message: "removed asset \(id)", newLayerId: nil, newPageId: nil, newAssetId: nil)
        }
    }

    // MARK: - Helpers

    private static func uniqueLayerId(in doc: Document, pageId: String, suggested: String?, prefix: String) throws -> String {
        let page = doc.page(id: pageId)
        if let s = suggested {
            if page?.layer(id: s) != nil { throw EditorError.duplicateLayerId(s) }
            return s
        }
        var i = 1
        while true {
            let candidate = "\(prefix)-\(i)"
            if page?.layer(id: candidate) == nil { return candidate }
            i += 1
        }
    }

    private static func ensureUniquePageId(in doc: Document, suggested: String?) throws -> String {
        if let s = suggested {
            if doc.page(id: s) != nil { throw EditorError.duplicateLayerId("page:\(s)") }
            return s
        }
        return doc.nextPageId()
    }

    private static func mutateLayer(in doc: inout Document,
                                    pageId: String?,
                                    layerId: String,
                                    _ change: (inout Layer) -> Void) throws {
        let pageId = pageId ?? doc.activePage.id
        guard let idx = doc.pageIndex(id: pageId) else { throw EditorError.layerNotFound("page:\(pageId)") }
        guard let lIdx = doc.pages[idx].layers.firstIndex(where: { $0.id == layerId }) else {
            throw EditorError.layerNotFound(layerId)
        }
        change(&doc.pages[idx].layers[lIdx])
    }

    private static func mutateText(in doc: inout Document,
                                   pageId: String?,
                                   layerId: String,
                                   _ change: (inout TextLayerPayload) -> Void) throws {
        try mutateLayer(in: &doc, pageId: pageId, layerId: layerId) { l in
            guard case .text(var p) = l.payload else { return }
            change(&p)
            l.payload = .text(p)
        }
    }

    /// Recursively shift every frame in `layers` by `(dx, dy)`. Walks into groups so deeply
    /// nested children move with their ancestor.
    private static func translate(layers: inout [Layer], dx: Double, dy: Double) {
        for i in 0..<layers.count {
            layers[i].frame.x += dx
            layers[i].frame.y += dy
            if case .group(var g) = layers[i].payload {
                translate(layers: &g.children, dx: dx, dy: dy)
                layers[i].payload = .group(g)
            }
        }
    }

    /// Propagate a frame change on a group layer to its children — translates by the (x, y)
    /// delta and scales by the (w, h) ratio so the composite stretches with the group. Recurses
    /// into nested groups so deeply-nested children also rescale. No-op on non-group layers.
    private static func applyGroupFrameChange(_ layer: inout Layer, oldFrame: Frame) {
        guard case .group(var g) = layer.payload else { return }
        let new = layer.frame
        let sx = oldFrame.w > 0 ? new.w / oldFrame.w : 1
        let sy = oldFrame.h > 0 ? new.h / oldFrame.h : 1
        for i in 0..<g.children.count {
            let childOld = g.children[i].frame
            let nx = new.x + (childOld.x - oldFrame.x) * sx
            let ny = new.y + (childOld.y - oldFrame.y) * sy
            let nw = childOld.w * sx
            let nh = childOld.h * sy
            g.children[i].frame = Frame(nx, ny, nw, nh)
            applyGroupFrameChange(&g.children[i], oldFrame: childOld)
        }
        layer.payload = .group(g)
    }

    /// Walk a layer tree bottom-up and reset every group's frame to the axis-aligned union of
    /// its children's frames. Called after every command so groups stay glued to whatever's
    /// inside them — adds, removes, individual child moves, nested edits.
    private static func recomputeGroupFrames(in layers: inout [Layer]) {
        for i in 0..<layers.count {
            if case .group(var g) = layers[i].payload {
                recomputeGroupFrames(in: &g.children)
                if !g.children.isEmpty {
                    var minX = Double.infinity, minY = Double.infinity
                    var maxX = -Double.infinity, maxY = -Double.infinity
                    for child in g.children {
                        let f = child.frame
                        minX = min(minX, f.x);       minY = min(minY, f.y)
                        maxX = max(maxX, f.x + f.w); maxY = max(maxY, f.y + f.h)
                    }
                    layers[i].frame = Frame(minX, minY, maxX - minX, maxY - minY)
                }
                layers[i].payload = .group(g)
            }
        }
    }

    /// Recursively find and remove a layer (by id) from a layer tree. Returns the extracted
    /// layer if found anywhere — top-level or nested inside any group.
    private static func extractLayer(from layers: inout [Layer], id: String) -> Layer? {
        if let idx = layers.firstIndex(where: { $0.id == id }) {
            return layers.remove(at: idx)
        }
        for i in 0..<layers.count {
            if case .group(var g) = layers[i].payload {
                if let found = extractLayer(from: &g.children, id: id) {
                    layers[i].payload = .group(g)
                    return found
                }
            }
        }
        return nil
    }

    /// Insert a layer either at the page's top level (when `intoGroupId` is nil or empty) or as
    /// a child of `intoGroupId` anywhere in the tree. Falls back to a top-level append only
    /// when called at the outermost layer; the recursive search uses `insertIntoGroup` so it
    /// can fail cleanly without polluting intermediate group children.
    private static func insertLayer(_ layer: Layer, into layers: inout [Layer],
                                    intoGroupId: String?, beforeLayerId: String?) {
        if let gid = intoGroupId, !gid.isEmpty {
            if insertIntoGroup(layer, in: &layers, groupId: gid, beforeLayerId: beforeLayerId) {
                return
            }
            // Target group not found in this subtree — append at the current top level.
            layers.append(layer)
        } else {
            insertSibling(layer, into: &layers, beforeLayerId: beforeLayerId)
        }
    }

    /// Recursive search-and-insert. Returns true if the named group was found and the layer
    /// was added to it; false if the group is not in this subtree.
    private static func insertIntoGroup(_ layer: Layer, in layers: inout [Layer],
                                        groupId: String, beforeLayerId: String?) -> Bool {
        for i in 0..<layers.count {
            if layers[i].id == groupId, case .group(var g) = layers[i].payload {
                insertSibling(layer, into: &g.children, beforeLayerId: beforeLayerId)
                layers[i].payload = .group(g)
                return true
            }
            if case .group(var g) = layers[i].payload {
                if insertIntoGroup(layer, in: &g.children, groupId: groupId, beforeLayerId: beforeLayerId) {
                    layers[i].payload = .group(g)
                    return true
                }
            }
        }
        return false
    }

    private static func insertSibling(_ layer: Layer, into siblings: inout [Layer],
                                      beforeLayerId: String?) {
        if let beforeId = beforeLayerId,
           let idx = siblings.firstIndex(where: { $0.id == beforeId }) {
            siblings.insert(layer, at: idx)
        } else {
            siblings.append(layer)
        }
    }

    /// True if `candidateId` lives inside the group `groupId`'s subtree (at any depth).
    private static func isDescendant(_ candidateId: String, ofGroupId groupId: String,
                                     in layers: [Layer]) -> Bool {
        for layer in layers {
            if layer.id == groupId, case .group(let g) = layer.payload {
                return containsId(candidateId, in: g.children)
            }
            if case .group(let g) = layer.payload {
                if isDescendant(candidateId, ofGroupId: groupId, in: g.children) { return true }
            }
        }
        return false
    }

    private static func containsId(_ id: String, in layers: [Layer]) -> Bool {
        for layer in layers {
            if layer.id == id { return true }
            if case .group(let g) = layer.payload {
                if containsId(id, in: g.children) { return true }
            }
        }
        return false
    }

    private static func shiftZ(in doc: inout Document,
                               pageId: String?,
                               layerId: String,
                               direction: Int) throws {
        let pageId = pageId ?? doc.activePage.id
        guard let page = doc.page(id: pageId) else { throw EditorError.layerNotFound("page:\(pageId)") }
        let order = page.renderOrder
        guard let idx = order.firstIndex(where: { $0.id == layerId }) else { throw EditorError.layerNotFound(layerId) }
        let other = idx + direction
        guard other >= 0, other < order.count else { return }
        let myZ = order[idx].zIndex
        let otherZ = order[other].zIndex
        let newSelfZ: Double
        let newOtherZ: Double
        if myZ == otherZ {
            newSelfZ  = direction > 0 ? myZ + 1 : myZ - 1
            newOtherZ = otherZ
        } else {
            newSelfZ = otherZ
            newOtherZ = myZ
        }
        try mutateLayer(in: &doc, pageId: pageId, layerId: layerId) { $0.zIndex = newSelfZ }
        try mutateLayer(in: &doc, pageId: pageId, layerId: order[other].id) { $0.zIndex = newOtherZ }
    }
}
