import Foundation

public struct Canvas: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var background: Color
    public var dpi: Int

    public init(width: Int, height: Int, background: Color = .white, dpi: Int = 72) {
        self.width = width; self.height = height; self.background = background; self.dpi = dpi
    }

    enum CodingKeys: String, CodingKey { case width, height, background, dpi }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width  = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        background = try c.decodeIfPresent(Color.self, forKey: .background) ?? .white
        dpi    = try c.decodeIfPresent(Int.self, forKey: .dpi) ?? 72
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(background, forKey: .background)
        if dpi != 72 { try c.encode(dpi, forKey: .dpi) }
    }
}

public struct Asset: Codable, Equatable, Sendable {
    /// File path. Relative paths are resolved against the project file directory.
    public var path: String
    public init(path: String) { self.path = path }
}

/// Layout mode. Kept for codec-compatibility but the GUI/engine now always lays previews out
/// in a single horizontal row using the layout's spacing.
public enum LayoutMode: String, Codable, CaseIterable, Sendable { case free, grid, row }

/// Default dimensions used when adding new previews + the spacing between adjacent previews
/// in the auto-layout. The actual `Preview` instances live on `Page.previews` and own their
/// resolved frame and background.
public struct PageLayout: Codable, Equatable, Sendable {
    public var previewWidth: Double
    public var previewHeight: Double
    public var spacing: Double
    /// Legacy fields preserved for codec stability (older docs may have set them).
    public var mode: LayoutMode
    public var columns: Int

    public init(previewWidth: Double = 1290,
                previewHeight: Double = 2796,
                spacing: Double = 80,
                mode: LayoutMode = .row,
                columns: Int = 1) {
        self.previewWidth = previewWidth
        self.previewHeight = previewHeight
        self.spacing = spacing
        self.mode = mode
        self.columns = columns
    }

    enum CodingKeys: String, CodingKey {
        case mode, previewWidth, previewHeight, spacing, columns,
             previewCount // legacy: ignored on load
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        previewWidth  = try c.decodeIfPresent(Double.self, forKey: .previewWidth)  ?? 1290
        previewHeight = try c.decodeIfPresent(Double.self, forKey: .previewHeight) ?? 2796
        spacing       = try c.decodeIfPresent(Double.self, forKey: .spacing) ?? 80
        mode          = try c.decodeIfPresent(LayoutMode.self, forKey: .mode) ?? .row
        columns       = try c.decodeIfPresent(Int.self, forKey: .columns) ?? 1
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(previewWidth,  forKey: .previewWidth)
        try c.encode(previewHeight, forKey: .previewHeight)
        try c.encode(spacing,       forKey: .spacing)
        try c.encode(mode,          forKey: .mode)
        if columns != 1 { try c.encode(columns, forKey: .columns) }
    }
}

/// A `Preview` is a rectangular export viewport on the page. The page's overall work area is
/// the bounding box of every preview. Layers cross preview boundaries freely; at export time
/// each preview yields exactly one PNG, clipped to its frame.
///
/// Preview backgrounds are always opaque (alpha forced to 1) so the export PNG never bleeds
/// the editor's checkerboard or the page background through the preview area.
public struct Preview: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var frame: Frame
    public var background: Color

    public init(id: String,
                name: String? = nil,
                frame: Frame,
                background: Color = (try? Color(hex: "#1A1A2E")) ?? .black) {
        self.id = id
        self.name = name ?? id
        self.frame = frame
        self.background = Self.solidify(background)
    }

    /// Force a color to be fully opaque — Preview backgrounds must never be transparent.
    public static func solidify(_ c: Color) -> Color {
        Color(r: c.r, g: c.g, b: c.b, a: 1)
    }

    enum CodingKeys: String, CodingKey { case id, name, frame, background }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decode(String.self, forKey: .id)
        name  = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        frame = try c.decode(Frame.self, forKey: .frame)
        background = Self.solidify(try c.decode(Color.self, forKey: .background))
    }
}

public struct Page: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Derived from the previews — equals the bounding box of all `previews`.
    public var canvas: Canvas
    public var layout: PageLayout
    public var previews: [Preview]
    public var layers: [Layer]

    public init(id: String,
                name: String? = nil,
                canvas: Canvas,
                layout: PageLayout? = nil,
                previews: [Preview] = [],
                layers: [Layer] = []) {
        self.id = id
        self.name = name ?? id
        self.canvas = canvas
        // Derive layout's preview size from the canvas if the caller didn't supply one — that
        // way `Document(canvas: Canvas(width: 100, height: 200))` doesn't have relayout
        // suddenly resize the canvas to PageLayout's static 1290×2796 default.
        self.layout = layout ?? PageLayout(previewWidth: Double(canvas.width),
                                           previewHeight: Double(canvas.height),
                                           spacing: 80)
        self.previews = previews
        self.layers = layers
        if self.previews.isEmpty {
            let default0 = Preview(id: id + "-preview-1", name: "Preview 1",
                                   frame: Frame(0, 0, Double(canvas.width), Double(canvas.height)),
                                   background: canvas.background)
            self.previews = [default0]
        }
        Self.relayout(&self)
    }

    enum CodingKeys: String, CodingKey { case id, name, canvas, layout, previews, layers }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id     = try c.decode(String.self, forKey: .id)
        name   = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        canvas = try c.decode(Canvas.self, forKey: .canvas)
        layers = try c.decodeIfPresent([Layer].self, forKey: .layers) ?? []

        let savedPreviews = try c.decodeIfPresent([Preview].self, forKey: .previews)
        let isMigration = savedPreviews?.isEmpty != false   // nil OR empty → v1/v2 doc

        if let saved = try c.decodeIfPresent(PageLayout.self, forKey: .layout) {
            layout = saved
        } else {
            layout = PageLayout()
        }

        if isMigration {
            // v1/v2 doc — promote the existing canvas to a single Preview and force the layout's
            // preview-size to match so relayout doesn't reshape the canvas.
            layout.previewWidth  = Double(canvas.width)
            layout.previewHeight = Double(canvas.height)
            previews = [Preview(id: id + "-preview-1", name: "Preview 1",
                                frame: Frame(0, 0, Double(canvas.width), Double(canvas.height)),
                                background: canvas.background)]
        } else {
            previews = savedPreviews!
        }
        Self.relayout(&self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        if name != id { try c.encode(name, forKey: .name) }
        try c.encode(canvas, forKey: .canvas)
        try c.encode(layout, forKey: .layout)
        try c.encode(previews, forKey: .previews)
        try c.encode(layers, forKey: .layers)
    }

    // MARK: - Layout

    /// Position every preview in a single horizontal row using the layout's spacing, then
    /// resize the canvas. The canvas is padded with margins on every side:
    /// one preview width on the left and right, half a preview height on the top and bottom.
    public static func relayout(_ page: inout Page) {
        let w = page.layout.previewWidth
        let h = page.layout.previewHeight
        let s = page.layout.spacing
        let marginX = w           // one preview width before the first / after the last
        let marginY = h / 2       // half preview height on top + bottom

        guard !page.previews.isEmpty else {
            page.canvas.width  = max(1, Int((marginX * 2 + w).rounded()))
            page.canvas.height = max(1, Int((marginY * 2 + h).rounded()))
            return
        }

        var x: Double = marginX
        for i in 0..<page.previews.count {
            page.previews[i].frame.x = x
            page.previews[i].frame.y = marginY
            page.previews[i].frame.w = w
            page.previews[i].frame.h = h
            x += w + s
        }
        let totalContentWidth = Double(page.previews.count) * w + Double(max(0, page.previews.count - 1)) * s
        page.canvas.width  = max(1, Int((marginX * 2 + totalContentWidth).rounded()))
        page.canvas.height = max(1, Int((marginY * 2 + h).rounded()))
    }

    /// Default-name a freshly-added preview as "Preview <next>".
    public func nextPreviewId() -> String {
        var i = previews.count + 1
        let prefix = id + "-preview-"
        while previews.contains(where: { $0.id == prefix + String(i) }) { i += 1 }
        return prefix + String(i)
    }

    public func preview(id: String) -> Preview? { previews.first { $0.id == id } }

    // Helpers
    public func layer(id: String) -> Layer? { layers.first { $0.id == id } }
    public var topZIndex: Double    { layers.map(\.zIndex).max() ?? 0 }
    public var lowestZIndex: Double { layers.map(\.zIndex).min() ?? 0 }
    public var renderOrder: [Layer] {
        let pairs = layers.enumerated().map { ($0.offset, $0.element) }
        return pairs.sorted { a, b in
            if a.1.zIndex == b.1.zIndex { return a.0 < b.0 }
            return a.1.zIndex < b.1.zIndex
        }.map { $0.1 }
    }
}

public struct Document: Equatable, Sendable {
    public var version: Int
    public var assets: [String: Asset]
    public var pages: [Page]
    /// Pointer to the active page when serialized — restored on load. Optional.
    public var activePageId: String?

    public init(version: Int = 2,
                assets: [String: Asset] = [:],
                pages: [Page] = [],
                activePageId: String? = nil) {
        self.version = version
        self.assets = assets
        self.pages = pages
        self.activePageId = activePageId ?? pages.first?.id
    }

    /// Convenience constructor matching the v1 shape (single page).
    public init(canvas: Canvas, assets: [String: Asset] = [:], layers: [Layer] = []) {
        let page = Page(id: "page-1", name: "Page 1", canvas: canvas, layers: layers)
        self.init(version: 2, assets: assets, pages: [page], activePageId: page.id)
    }

    // MARK: - Page helpers

    public func page(id: String) -> Page? { pages.first { $0.id == id } }
    public func pageIndex(id: String) -> Int? { pages.firstIndex { $0.id == id } }

    /// Currently active page (defaults to first).
    public var activePage: Page {
        if let id = activePageId, let p = page(id: id) { return p }
        return pages.first ?? Page(id: "page-1", canvas: Canvas(width: 1290, height: 2796))
    }

    public mutating func updatePage(id: String, _ change: (inout Page) -> Void) throws {
        guard let idx = pageIndex(id: id) else { throw EditorError.layerNotFound("page:\(id)") }
        change(&pages[idx])
    }

    /// Suggest a unique page id like "page-3".
    public func nextPageId() -> String {
        var i = pages.count + 1
        while pages.contains(where: { $0.id == "page-\(i)" }) { i += 1 }
        return "page-\(i)"
    }

    // MARK: - v1 compatibility convenience accessors

    /// Convenience: layers of the active page (matches v1 API).
    public var layers: [Layer] {
        get { activePage.layers }
        set {
            let id = activePage.id
            if let idx = pageIndex(id: id) { pages[idx].layers = newValue }
        }
    }

    /// Convenience: canvas of the active page (matches v1 API).
    public var canvas: Canvas {
        get { activePage.canvas }
        set {
            let id = activePage.id
            if let idx = pageIndex(id: id) { pages[idx].canvas = newValue }
        }
    }

    public func layer(id: String) -> Layer? { activePage.layer(id: id) }
    public var topZIndex: Double    { activePage.topZIndex }
    public var lowestZIndex: Double { activePage.lowestZIndex }
    public var renderOrder: [Layer] { activePage.renderOrder }

    public mutating func upsertLayer(_ layer: Layer) {
        let id = activePage.id
        if let idx = pageIndex(id: id) {
            if let lIdx = pages[idx].layers.firstIndex(where: { $0.id == layer.id }) {
                pages[idx].layers[lIdx] = layer
            } else {
                pages[idx].layers.append(layer)
            }
        }
    }

    @discardableResult
    public mutating func removeLayer(id: String) -> Bool {
        let pid = activePage.id
        guard let idx = pageIndex(id: pid) else { return false }
        let before = pages[idx].layers.count
        pages[idx].layers.removeAll { $0.id == id }
        return pages[idx].layers.count < before
    }
}

// MARK: - Codable with v1 auto-upgrade

extension Document: Codable {
    enum CodingKeys: String, CodingKey {
        case version, assets, pages, activePageId
        // v1 only
        case canvas, layers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let v = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        assets = try c.decodeIfPresent([String: Asset].self, forKey: .assets) ?? [:]
        if let pages = try c.decodeIfPresent([Page].self, forKey: .pages) {
            self.pages = pages
            self.activePageId = try c.decodeIfPresent(String.self, forKey: .activePageId) ?? pages.first?.id
            self.version = max(v, 2)
        } else {
            // v1: wrap canvas + layers into a single default page
            let canvas = try c.decode(Canvas.self, forKey: .canvas)
            let layers = try c.decodeIfPresent([Layer].self, forKey: .layers) ?? []
            let page = Page(id: "page-1", name: "Page 1", canvas: canvas, layers: layers)
            self.pages = [page]
            self.activePageId = page.id
            self.version = 2
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(2, forKey: .version)
        try c.encode(assets, forKey: .assets)
        try c.encode(pages, forKey: .pages)
        if let pid = activePageId { try c.encode(pid, forKey: .activePageId) }
    }
}
