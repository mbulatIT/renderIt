import Foundation

public enum BlendMode: String, Codable, CaseIterable, Sendable {
    case normal, multiply, screen, overlay, softLight, hardLight, darken, lighten
}

/// How a layer's corner radius is shaped. `arc` is the standard CG roundedRect (perfect
/// quarter-circles). `continuous` is an iOS-style "squircle" curve — softer, with a longer
/// reach into adjacent edges. `cut` chamfers the corners with a straight 45° bevel.
public enum CornerStyle: String, Codable, CaseIterable, Sendable {
    case arc, continuous, cut
}

/// Which corners a layer's `cornerRadius` actually rounds. Lets a layer round only a subset of
/// its corners (e.g. just the top two). Defaults to all four, matching the previous behaviour
/// where the radius always applied uniformly. An empty set leaves every corner square.
public struct RectCorners: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let topLeft     = RectCorners(rawValue: 1 << 0)
    public static let topRight    = RectCorners(rawValue: 1 << 1)
    public static let bottomRight = RectCorners(rawValue: 1 << 2)
    public static let bottomLeft  = RectCorners(rawValue: 1 << 3)
    public static let all: RectCorners = [.topLeft, .topRight, .bottomRight, .bottomLeft]

    /// Stable name ↔ flag table used for the human-readable JSON encoding.
    private static let named: [(RectCorners, String)] = [
        (.topLeft, "topLeft"), (.topRight, "topRight"),
        (.bottomRight, "bottomRight"), (.bottomLeft, "bottomLeft"),
    ]
    /// Corner names present in this set, in a stable order — used for `.aiproj` encoding.
    public var names: [String] { Self.named.filter { contains($0.0) }.map { $0.1 } }
    /// Build from corner-name strings (case-insensitive); unknown names are ignored.
    public init(names: [String]) {
        self = names.reduce(into: []) { set, n in
            if let m = Self.named.first(where: { $0.1.caseInsensitiveCompare(n) == .orderedSame }) {
                set.insert(m.0)
            }
        }
    }
}

public enum FontWeight: String, Codable, CaseIterable, Sendable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
}

public enum TextAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right, justified
}

public enum ContentMode: String, Codable, CaseIterable, Sendable {
    case fit, fill, stretch
}

public struct Stroke: Codable, Equatable, Sendable {
    public var color: Color
    public var width: Double
    public init(color: Color, width: Double) { self.color = color; self.width = width }
}

public struct Shadow: Codable, Equatable, Sendable {
    public var color: Color
    public var offsetX: Double
    public var offsetY: Double
    public var blur: Double
    public init(color: Color, offsetX: Double, offsetY: Double, blur: Double) {
        self.color = color; self.offsetX = offsetX; self.offsetY = offsetY; self.blur = blur
    }
    enum CodingKeys: String, CodingKey { case color, offset, blur }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decode(Color.self, forKey: .color)
        let offset = try c.decode([Double].self, forKey: .offset)
        guard offset.count == 2 else { throw EditorError.decoding("shadow.offset expects [dx, dy]") }
        offsetX = offset[0]; offsetY = offset[1]
        blur = try c.decode(Double.self, forKey: .blur)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(color, forKey: .color)
        try c.encode([offsetX, offsetY], forKey: .offset)
        try c.encode(blur, forKey: .blur)
    }
}

// MARK: - Layer kinds

public enum LayerKind: String, Codable, CaseIterable, Sendable {
    case image
    case text
    case rect
    case ellipse
    case deviceBezel
    case group
    case gradient
    case blur
    case line
    case polygon
    case star
}

public enum LayerPayload: Equatable, Sendable {
    case image(ImageLayerPayload)
    case text(TextLayerPayload)
    case rect(ShapeLayerPayload)
    case ellipse(ShapeLayerPayload)
    case deviceBezel(DeviceBezelPayload)
    case group(GroupPayload)
    case gradient(GradientLayerPayload)
    case blur(BlurLayerPayload)
    case line(LineLayerPayload)
    case polygon(PolygonLayerPayload)
    case star(StarLayerPayload)
}

/// A straight line, optionally with arrowheads on either end. Start/end are normalized
/// `0...1` to the layer's frame.
public struct LineLayerPayload: Codable, Equatable, Sendable {
    public var color: Color
    public var width: Double
    public var startX: Double
    public var startY: Double
    public var endX: Double
    public var endY: Double
    public var startArrow: Bool
    public var endArrow: Bool
    /// Arrowhead size as a multiplier of the line width. `4` means the arrowhead is 4× the
    /// stroke width long.
    public var arrowSize: Double

    public init(color: Color = .white,
                width: Double = 6,
                startX: Double = 0, startY: Double = 0.5,
                endX: Double = 1, endY: Double = 0.5,
                startArrow: Bool = false,
                endArrow: Bool = false,
                arrowSize: Double = 4) {
        self.color = color; self.width = width
        self.startX = startX; self.startY = startY
        self.endX = endX; self.endY = endY
        self.startArrow = startArrow; self.endArrow = endArrow
        self.arrowSize = arrowSize
    }
}

/// Regular N-gon inscribed in the layer's frame (vertices on the ellipse). First vertex
/// points up; rotate the layer to spin it.
public struct PolygonLayerPayload: Codable, Equatable, Sendable {
    public var sides: Int
    public var fill: Color
    public var stroke: Stroke?
    public init(sides: Int = 6, fill: Color = .white, stroke: Stroke? = nil) {
        self.sides = max(3, sides)
        self.fill = fill
        self.stroke = stroke
    }
}

/// N-pointed star inscribed in the layer's frame.
public struct StarLayerPayload: Codable, Equatable, Sendable {
    public var points: Int
    /// Inner radius as a fraction of the outer radius (`0…1`). Lower = pointier.
    public var innerRadius: Double
    public var fill: Color
    public var stroke: Stroke?
    public init(points: Int = 5, innerRadius: Double = 0.4, fill: Color = .white, stroke: Stroke? = nil) {
        self.points = max(3, points)
        self.innerRadius = max(0.05, min(0.95, innerRadius))
        self.fill = fill
        self.stroke = stroke
    }
}

public enum GradientType: String, Codable, CaseIterable, Sendable {
    case linear, radial
}

/// Fill drawn behind a layer's primary content, within its frame (respecting cornerRadius and
/// cornerStyle). Can be either a solid colour or a gradient.
public enum LayerBackground: Equatable, Sendable {
    case color(Color)
    case gradient(GradientLayerPayload)
}

extension LayerBackground: Codable {
    private enum CodingKeys: String, CodingKey { case color, gradient }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let color = try c.decodeIfPresent(Color.self, forKey: .color) {
            self = .color(color)
        } else if let g = try c.decodeIfPresent(GradientLayerPayload.self, forKey: .gradient) {
            self = .gradient(g)
        } else {
            throw EditorError.decoding("layer background requires `color` or `gradient`")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .color(let col):    try c.encode(col, forKey: .color)
        case .gradient(let g):   try c.encode(g,   forKey: .gradient)
        }
    }
}

/// One color stop in a gradient. `at` is normalized to `0...1`.
public struct GradientStop: Codable, Equatable, Sendable {
    public var color: Color
    public var at: Double
    public init(color: Color, at: Double) {
        self.color = color
        self.at = at
    }
}

public struct GradientLayerPayload: Equatable, Sendable, Codable {
    public var type: GradientType
    public var stops: [GradientStop]
    /// Start/end points are normalized `0...1` within the layer's frame. (0,0)=top-left, (1,1)=bottom-right.
    public var startX: Double
    public var startY: Double
    public var endX: Double
    public var endY: Double

    public init(type: GradientType = .linear,
                stops: [GradientStop] = [.init(color: .black, at: 0),
                                         .init(color: .white, at: 1)],
                startX: Double = 0, startY: Double = 0,
                endX: Double = 0, endY: Double = 1) {
        self.type = type
        self.stops = stops
        self.startX = startX; self.startY = startY
        self.endX = endX; self.endY = endY
    }

    enum CodingKeys: String, CodingKey { case type, stops, start, end }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(GradientType.self, forKey: .type) ?? .linear
        stops = try c.decodeIfPresent([GradientStop].self, forKey: .stops) ?? [
            .init(color: .black, at: 0), .init(color: .white, at: 1)
        ]
        let start = try c.decodeIfPresent([Double].self, forKey: .start) ?? [0, 0]
        let end   = try c.decodeIfPresent([Double].self, forKey: .end)   ?? [0, 1]
        guard start.count == 2, end.count == 2 else {
            throw EditorError.decoding("gradient start/end expect [x, y]")
        }
        startX = start[0]; startY = start[1]
        endX = end[0]; endY = end[1]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if type != .linear { try c.encode(type, forKey: .type) }
        try c.encode(stops, forKey: .stops)
        try c.encode([startX, startY], forKey: .start)
        try c.encode([endX, endY], forKey: .end)
    }
}

/// One stop of a variable-radius blur. `at` is normalized 0…1 along the layer's blur gradient
/// direction; `radius` is the blur radius in canvas pixels at that position.
public struct BlurStop: Codable, Equatable, Sendable {
    public var radius: Double
    public var at: Double
    public init(radius: Double, at: Double) {
        self.radius = radius
        self.at = at
    }
}

/// Frosted-glass blur. Samples whatever has been drawn beneath this layer within its frame,
/// applies a Gaussian blur, and draws it back (optionally with a corner radius and tint).
/// Rotation has no effect on blur layers; the sample rect is always axis-aligned.
///
/// When `stops` is set with at least two entries, the blur radius varies across the frame
/// along the gradient direction `(startX,startY) → (endX,endY)` (normalized 0…1). Each stop
/// declares the radius at its normalized position. Internally implemented via
/// `CIMaskedVariableBlur` with a grayscale mask whose brightness encodes radius/maxRadius.
public struct BlurLayerPayload: Codable, Equatable, Sendable {
    public var radius: Double
    public var tint: Color?
    public var stops: [BlurStop]?
    public var gradientType: GradientType
    public var startX: Double, startY: Double
    public var endX: Double, endY: Double

    public init(radius: Double = 24,
                tint: Color? = nil,
                stops: [BlurStop]? = nil,
                gradientType: GradientType = .linear,
                startX: Double = 0, startY: Double = 0,
                endX: Double = 0, endY: Double = 1) {
        self.radius = radius
        self.tint = tint
        self.stops = stops
        self.gradientType = gradientType
        self.startX = startX; self.startY = startY
        self.endX = endX; self.endY = endY
    }

    enum CodingKeys: String, CodingKey {
        case radius, tint, stops, gradientType, start, end
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 24
        tint   = try c.decodeIfPresent(Color.self,  forKey: .tint)
        stops  = try c.decodeIfPresent([BlurStop].self, forKey: .stops)
        gradientType = try c.decodeIfPresent(GradientType.self, forKey: .gradientType) ?? .linear
        let start = try c.decodeIfPresent([Double].self, forKey: .start) ?? [0, 0]
        let end   = try c.decodeIfPresent([Double].self, forKey: .end)   ?? [0, 1]
        guard start.count == 2, end.count == 2 else {
            throw EditorError.decoding("blur start/end expect [x, y]")
        }
        startX = start[0]; startY = start[1]
        endX   = end[0];   endY   = end[1]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(radius, forKey: .radius)
        try c.encodeIfPresent(tint, forKey: .tint)
        if let stops = stops, !stops.isEmpty {
            try c.encode(stops, forKey: .stops)
            if gradientType != .linear { try c.encode(gradientType, forKey: .gradientType) }
            try c.encode([startX, startY], forKey: .start)
            try c.encode([endX,   endY],   forKey: .end)
        }
    }
}

public struct ImageLayerPayload: Codable, Equatable, Sendable {
    public var assetId: String
    public var contentMode: ContentMode
    public init(assetId: String, contentMode: ContentMode = .fit) {
        self.assetId = assetId; self.contentMode = contentMode
    }
}

public struct TextLayerPayload: Codable, Equatable, Sendable {
    public var text: String
    public var font: String
    public var fontSize: Double
    public var fontWeight: FontWeight
    public var italic: Bool
    public var color: Color
    public var alignment: TextAlignment
    public var lineSpacing: Double
    public var kerning: Double

    public init(text: String,
                font: String = "SF Pro Display",
                fontSize: Double = 72,
                fontWeight: FontWeight = .regular,
                italic: Bool = false,
                color: Color = .white,
                alignment: TextAlignment = .center,
                lineSpacing: Double = 0,
                kerning: Double = 0) {
        self.text = text
        self.font = font
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.italic = italic
        self.color = color
        self.alignment = alignment
        self.lineSpacing = lineSpacing
        self.kerning = kerning
    }
}

public struct ShapeLayerPayload: Codable, Equatable, Sendable {
    public var fill: Color
    public var stroke: Stroke?
    public init(fill: Color = .white, stroke: Stroke? = nil) {
        self.fill = fill; self.stroke = stroke
    }
}

public struct DeviceBezelPayload: Codable, Equatable, Sendable {
    public var device: String
    public var screenshotAssetId: String?
    /// Override for the programmatic bezel chrome color. Ignored for image-backed bezels —
    /// use `color` instead.
    public var chromeColor: Color?
    /// Color variant of an image-backed bezel (e.g. "Silver", "Deep blue"). nil = device default.
    public var color: String?
    public init(device: String, screenshotAssetId: String? = nil,
                chromeColor: Color? = nil, color: String? = nil) {
        self.device = device
        self.screenshotAssetId = screenshotAssetId
        self.chromeColor = chromeColor
        self.color = color
    }
}

public struct GroupPayload: Equatable, Sendable {
    public var children: [Layer]
    /// When true, the group clips (crops) its children's drawing to the group's frame — the
    /// axis-aligned union of the children's frames, respecting `cornerRadius`/`cornerStyle`.
    /// This trims anything that paints past the box: rotated children, `.fill`-mode images,
    /// overflowing text, drop shadows, and strokes. Defaults to off so existing groups render
    /// exactly as before.
    public var clipsToBounds: Bool
    public init(children: [Layer] = [], clipsToBounds: Bool = false) {
        self.children = children
        self.clipsToBounds = clipsToBounds
    }
}

// MARK: - Layer

public struct Layer: Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: LayerKind
    public var frame: Frame
    public var zIndex: Double
    public var rotation: Double
    public var opacity: Double
    public var visible: Bool
    public var blendMode: BlendMode
    /// Optional drop shadow drawn behind whatever this layer paints (text, shape, image, …).
    /// Applies uniformly across every layer kind except `blur` (which samples instead of
    /// drawing) and `group` (children carry their own shadows).
    public var shadow: Shadow?
    /// Optional rounded-corner radius applied to whatever this layer draws, in canvas pixels.
    /// For `rect`/`gradient`/`blur` the radius is baked into their own path. For other kinds
    /// (image, text, line, polygon, star, group) the renderer clips the layer's drawing to a
    /// rounded-rect mask matching its frame. Has no effect on `ellipse` or `deviceBezel`.
    public var cornerRadius: Double
    /// Shape of the rounded corners — `arc` (default, quarter-circles), `continuous`
    /// (squircle), or `cut` (45° chamfer). Ignored when `cornerRadius == 0`.
    public var cornerStyle: CornerStyle
    /// Which corners the `cornerRadius` rounds. Defaults to all four; a subset rounds only those
    /// corners (the rest stay square). Ignored when `cornerRadius == 0`.
    public var roundedCorners: RectCorners
    /// Optional gradient fill applied to the layer's drawn pixels (via a source-in mask).
    /// Turns any layer into a gradient-filled version of itself — gradient text, gradient
    /// shapes, gradient-tinted images, gradient-tinted grouped composites. No effect on
    /// `blur` or `deviceBezel` (or on standalone `.gradient` kind layers, which are their
    /// own gradient).
    public var gradient: GradientLayerPayload?
    /// Optional fill drawn behind the layer's primary content (solid colour or gradient),
    /// respecting `cornerRadius` and `cornerStyle`. Use for things like a translucent card
    /// background behind text, or a gradient panel behind a group composition.
    public var background: LayerBackground?
    public var payload: LayerPayload

    public init(id: String,
                name: String? = nil,
                kind: LayerKind,
                frame: Frame,
                zIndex: Double = 0,
                rotation: Double = 0,
                opacity: Double = 1,
                visible: Bool = true,
                blendMode: BlendMode = .normal,
                shadow: Shadow? = nil,
                cornerRadius: Double = 0,
                cornerStyle: CornerStyle = .continuous,
                roundedCorners: RectCorners = .all,
                gradient: GradientLayerPayload? = nil,
                background: LayerBackground? = nil,
                payload: LayerPayload) {
        self.id = id
        self.name = name ?? id
        self.kind = kind
        self.frame = frame
        self.zIndex = zIndex
        self.rotation = rotation
        self.opacity = opacity
        self.visible = visible
        self.blendMode = blendMode
        self.shadow = shadow
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.roundedCorners = roundedCorners
        self.gradient = gradient
        self.background = background
        self.payload = payload
    }
}

// MARK: - Codable

extension Layer: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, type, frame, zIndex, rotation, opacity, visible, blendMode, shadow
        // layer-level gradient fill (nested object — distinct from the `.gradient` LayerKind keys)
        case gradient
        // layer-level background fill (nested object — distinct from canvas/preview backgrounds)
        case background
        // corner-radius shaping
        case cornerStyle, roundedCorners
        // image
        case assetId, contentMode
        // text
        case text, font, fontSize, fontWeight, italic, color, alignment, lineSpacing, kerning
        // shape
        case fill, stroke, cornerRadius
        // bezel
        case device, screenshotAssetId, chromeColor
        // group
        case children, clipsToBounds
        // gradient (standalone kind — flat fields)
        case gradientType, stops, start, end
        // blur
        case radius, tint
        // line
        case width, startArrow, endArrow, arrowSize
        // polygon / star
        case sides, points, innerRadius
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decode(String.self, forKey: .id)
        let typeStr = try c.decode(String.self, forKey: .type)
        guard let kindV = LayerKind(rawValue: typeStr) else {
            throw EditorError.decoding("unknown layer type: \(typeStr)")
        }
        kind  = kindV
        name  = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        frame = try c.decode(Frame.self, forKey: .frame)
        zIndex   = try c.decodeIfPresent(Double.self,    forKey: .zIndex)   ?? 0
        rotation = try c.decodeIfPresent(Double.self,    forKey: .rotation) ?? 0
        opacity  = try c.decodeIfPresent(Double.self,    forKey: .opacity)  ?? 1
        visible  = try c.decodeIfPresent(Bool.self,      forKey: .visible)  ?? true
        blendMode = try c.decodeIfPresent(BlendMode.self, forKey: .blendMode) ?? .normal
        shadow    = try c.decodeIfPresent(Shadow.self,    forKey: .shadow)
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
        // Default to .continuous so new and existing documents that don't explicitly set a
        // corner style use the modern iOS-style squircle, matching what most designs expect.
        cornerStyle  = try c.decodeIfPresent(CornerStyle.self, forKey: .cornerStyle) ?? .continuous
        // Absent key → all corners rounded (matches the pre-feature behaviour). An explicit
        // (possibly empty) array selects exactly those corners.
        if let cornerNames = try c.decodeIfPresent([String].self, forKey: .roundedCorners) {
            roundedCorners = RectCorners(names: cornerNames)
        } else {
            roundedCorners = .all
        }
        // Only decode the nested layer-level gradient for non-`.gradient` kinds — the standalone
        // gradient kind keeps its own flat keys (gradientType/stops/start/end).
        if kindV == .gradient {
            gradient = nil
        } else {
            gradient = try c.decodeIfPresent(GradientLayerPayload.self, forKey: .gradient)
        }
        background = try c.decodeIfPresent(LayerBackground.self, forKey: .background)

        switch kindV {
        case .image:
            payload = .image(.init(
                assetId: try c.decode(String.self, forKey: .assetId),
                contentMode: try c.decodeIfPresent(ContentMode.self, forKey: .contentMode) ?? .fit))
        case .text:
            payload = .text(.init(
                text: try c.decode(String.self, forKey: .text),
                font: try c.decodeIfPresent(String.self, forKey: .font) ?? "SF Pro Display",
                fontSize: try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 72,
                fontWeight: try c.decodeIfPresent(FontWeight.self, forKey: .fontWeight) ?? .regular,
                italic: try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false,
                color: try c.decodeIfPresent(Color.self, forKey: .color) ?? .white,
                alignment: try c.decodeIfPresent(TextAlignment.self, forKey: .alignment) ?? .center,
                lineSpacing: try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 0,
                kerning: try c.decodeIfPresent(Double.self, forKey: .kerning) ?? 0))
        case .rect:
            payload = .rect(.init(
                fill: try c.decodeIfPresent(Color.self, forKey: .fill) ?? .white,
                stroke: try c.decodeIfPresent(Stroke.self, forKey: .stroke)))
        case .ellipse:
            payload = .ellipse(.init(
                fill: try c.decodeIfPresent(Color.self, forKey: .fill) ?? .white,
                stroke: try c.decodeIfPresent(Stroke.self, forKey: .stroke)))
        case .deviceBezel:
            payload = .deviceBezel(.init(
                device: try c.decode(String.self, forKey: .device),
                screenshotAssetId: try c.decodeIfPresent(String.self, forKey: .screenshotAssetId),
                chromeColor: try c.decodeIfPresent(Color.self, forKey: .chromeColor)))
        case .group:
            payload = .group(.init(
                children: try c.decodeIfPresent([Layer].self, forKey: .children) ?? [],
                clipsToBounds: try c.decodeIfPresent(Bool.self, forKey: .clipsToBounds) ?? false))
        case .gradient:
            let start = try c.decodeIfPresent([Double].self, forKey: .start) ?? [0, 0]
            let end   = try c.decodeIfPresent([Double].self, forKey: .end)   ?? [0, 1]
            guard start.count == 2, end.count == 2 else {
                throw EditorError.decoding("gradient start/end expect [x, y]")
            }
            payload = .gradient(.init(
                type: try c.decodeIfPresent(GradientType.self, forKey: .gradientType) ?? .linear,
                stops: try c.decodeIfPresent([GradientStop].self, forKey: .stops) ?? [
                    .init(color: .black, at: 0), .init(color: .white, at: 1)
                ],
                startX: start[0], startY: start[1],
                endX: end[0], endY: end[1]))
        case .blur:
            // BlurLayerPayload's own Codable reads radius/tint/stops/gradientType/start/end
            // from the same flat layer container — keys can't collide with other kinds here
            // because the `type` field already discriminated us into the blur branch.
            payload = .blur(try BlurLayerPayload(from: decoder))
        case .line:
            let start = try c.decodeIfPresent([Double].self, forKey: .start) ?? [0, 0.5]
            let end   = try c.decodeIfPresent([Double].self, forKey: .end)   ?? [1, 0.5]
            guard start.count == 2, end.count == 2 else {
                throw EditorError.decoding("line start/end expect [x, y]")
            }
            payload = .line(.init(
                color: try c.decodeIfPresent(Color.self, forKey: .color) ?? .white,
                width: try c.decodeIfPresent(Double.self, forKey: .width) ?? 6,
                startX: start[0], startY: start[1],
                endX: end[0], endY: end[1],
                startArrow: try c.decodeIfPresent(Bool.self, forKey: .startArrow) ?? false,
                endArrow: try c.decodeIfPresent(Bool.self, forKey: .endArrow) ?? false,
                arrowSize: try c.decodeIfPresent(Double.self, forKey: .arrowSize) ?? 4))
        case .polygon:
            payload = .polygon(.init(
                sides: try c.decodeIfPresent(Int.self, forKey: .sides) ?? 6,
                fill: try c.decodeIfPresent(Color.self, forKey: .fill) ?? .white,
                stroke: try c.decodeIfPresent(Stroke.self, forKey: .stroke)))
        case .star:
            payload = .star(.init(
                points: try c.decodeIfPresent(Int.self, forKey: .points) ?? 5,
                innerRadius: try c.decodeIfPresent(Double.self, forKey: .innerRadius) ?? 0.4,
                fill: try c.decodeIfPresent(Color.self, forKey: .fill) ?? .white,
                stroke: try c.decodeIfPresent(Stroke.self, forKey: .stroke)))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        if name != id { try c.encode(name, forKey: .name) }
        try c.encode(kind.rawValue, forKey: .type)
        try c.encode(frame, forKey: .frame)
        if zIndex != 0 { try c.encode(zIndex, forKey: .zIndex) }
        if rotation != 0 { try c.encode(rotation, forKey: .rotation) }
        if opacity != 1 { try c.encode(opacity, forKey: .opacity) }
        if !visible { try c.encode(visible, forKey: .visible) }
        if blendMode != .normal { try c.encode(blendMode, forKey: .blendMode) }
        try c.encodeIfPresent(shadow, forKey: .shadow)
        if cornerRadius != 0 { try c.encode(cornerRadius, forKey: .cornerRadius) }
        // Omit cornerStyle when it's the default (`.continuous`); always emit `.arc` or `.cut`.
        if cornerStyle != .continuous { try c.encode(cornerStyle, forKey: .cornerStyle) }
        // Omit roundedCorners when all four are rounded (the default); otherwise list the subset.
        if roundedCorners != .all { try c.encode(roundedCorners.names, forKey: .roundedCorners) }
        // Skip the nested gradient field on .gradient kind layers — they already encode their
        // gradient via the flat `gradientType`/`stops`/`start`/`end` keys.
        if kind != .gradient { try c.encodeIfPresent(gradient, forKey: .gradient) }
        try c.encodeIfPresent(background, forKey: .background)

        switch payload {
        case .image(let p):
            try c.encode(p.assetId, forKey: .assetId)
            if p.contentMode != .fit { try c.encode(p.contentMode, forKey: .contentMode) }
        case .text(let p):
            try c.encode(p.text, forKey: .text)
            try c.encode(p.font, forKey: .font)
            try c.encode(p.fontSize, forKey: .fontSize)
            try c.encode(p.fontWeight, forKey: .fontWeight)
            if p.italic { try c.encode(p.italic, forKey: .italic) }
            try c.encode(p.color, forKey: .color)
            try c.encode(p.alignment, forKey: .alignment)
            if p.lineSpacing != 0 { try c.encode(p.lineSpacing, forKey: .lineSpacing) }
            if p.kerning != 0 { try c.encode(p.kerning, forKey: .kerning) }
        case .rect(let p):
            try c.encode(p.fill, forKey: .fill)
            try c.encodeIfPresent(p.stroke, forKey: .stroke)
        case .ellipse(let p):
            try c.encode(p.fill, forKey: .fill)
            try c.encodeIfPresent(p.stroke, forKey: .stroke)
        case .deviceBezel(let p):
            try c.encode(p.device, forKey: .device)
            try c.encodeIfPresent(p.screenshotAssetId, forKey: .screenshotAssetId)
            try c.encodeIfPresent(p.chromeColor, forKey: .chromeColor)
        case .group(let p):
            try c.encode(p.children, forKey: .children)
            if p.clipsToBounds { try c.encode(p.clipsToBounds, forKey: .clipsToBounds) }
        case .gradient(let p):
            if p.type != .linear { try c.encode(p.type, forKey: .gradientType) }
            try c.encode(p.stops, forKey: .stops)
            try c.encode([p.startX, p.startY], forKey: .start)
            try c.encode([p.endX, p.endY], forKey: .end)
        case .blur(let p):
            // Delegate to BlurLayerPayload.encode so radius/tint/stops/gradientType/start/end
            // all land at the same flat layer level.
            try p.encode(to: encoder)
        case .line(let p):
            try c.encode(p.color, forKey: .color)
            try c.encode(p.width, forKey: .width)
            try c.encode([p.startX, p.startY], forKey: .start)
            try c.encode([p.endX, p.endY], forKey: .end)
            if p.startArrow { try c.encode(p.startArrow, forKey: .startArrow) }
            if p.endArrow { try c.encode(p.endArrow, forKey: .endArrow) }
            if p.arrowSize != 4 { try c.encode(p.arrowSize, forKey: .arrowSize) }
        case .polygon(let p):
            try c.encode(p.sides, forKey: .sides)
            try c.encode(p.fill, forKey: .fill)
            try c.encodeIfPresent(p.stroke, forKey: .stroke)
        case .star(let p):
            try c.encode(p.points, forKey: .points)
            try c.encode(p.innerRadius, forKey: .innerRadius)
            try c.encode(p.fill, forKey: .fill)
            try c.encodeIfPresent(p.stroke, forKey: .stroke)
        }
    }
}
