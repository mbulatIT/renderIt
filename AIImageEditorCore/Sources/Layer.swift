import Foundation

public enum BlendMode: String, Codable, CaseIterable, Sendable {
    case normal, multiply, screen, overlay, softLight, hardLight, darken, lighten
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
}

public enum LayerPayload: Equatable, Sendable {
    case image(ImageLayerPayload)
    case text(TextLayerPayload)
    case rect(ShapeLayerPayload)
    case ellipse(ShapeLayerPayload)
    case deviceBezel(DeviceBezelPayload)
    case group(GroupPayload)
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
    public var shadow: Shadow?

    public init(text: String,
                font: String = "SF Pro Display",
                fontSize: Double = 72,
                fontWeight: FontWeight = .regular,
                italic: Bool = false,
                color: Color = .white,
                alignment: TextAlignment = .center,
                lineSpacing: Double = 0,
                kerning: Double = 0,
                shadow: Shadow? = nil) {
        self.text = text
        self.font = font
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.italic = italic
        self.color = color
        self.alignment = alignment
        self.lineSpacing = lineSpacing
        self.kerning = kerning
        self.shadow = shadow
    }
}

public struct ShapeLayerPayload: Codable, Equatable, Sendable {
    public var fill: Color
    public var stroke: Stroke?
    public var cornerRadius: Double
    public init(fill: Color = .white, stroke: Stroke? = nil, cornerRadius: Double = 0) {
        self.fill = fill; self.stroke = stroke; self.cornerRadius = cornerRadius
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
    public init(children: [Layer] = []) { self.children = children }
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
        self.payload = payload
    }
}

// MARK: - Codable

extension Layer: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, type, frame, zIndex, rotation, opacity, visible, blendMode
        // image
        case assetId, contentMode
        // text
        case text, font, fontSize, fontWeight, italic, color, alignment, lineSpacing, kerning, shadow
        // shape
        case fill, stroke, cornerRadius
        // bezel
        case device, screenshotAssetId, chromeColor
        // group
        case children
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
                kerning: try c.decodeIfPresent(Double.self, forKey: .kerning) ?? 0,
                shadow: try c.decodeIfPresent(Shadow.self, forKey: .shadow)))
        case .rect:
            payload = .rect(.init(
                fill: try c.decodeIfPresent(Color.self, forKey: .fill) ?? .white,
                stroke: try c.decodeIfPresent(Stroke.self, forKey: .stroke),
                cornerRadius: try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0))
        case .ellipse:
            payload = .ellipse(.init(
                fill: try c.decodeIfPresent(Color.self, forKey: .fill) ?? .white,
                stroke: try c.decodeIfPresent(Stroke.self, forKey: .stroke),
                cornerRadius: 0))
        case .deviceBezel:
            payload = .deviceBezel(.init(
                device: try c.decode(String.self, forKey: .device),
                screenshotAssetId: try c.decodeIfPresent(String.self, forKey: .screenshotAssetId),
                chromeColor: try c.decodeIfPresent(Color.self, forKey: .chromeColor)))
        case .group:
            payload = .group(.init(children: try c.decodeIfPresent([Layer].self, forKey: .children) ?? []))
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
            try c.encodeIfPresent(p.shadow, forKey: .shadow)
        case .rect(let p):
            try c.encode(p.fill, forKey: .fill)
            try c.encodeIfPresent(p.stroke, forKey: .stroke)
            if p.cornerRadius != 0 { try c.encode(p.cornerRadius, forKey: .cornerRadius) }
        case .ellipse(let p):
            try c.encode(p.fill, forKey: .fill)
            try c.encodeIfPresent(p.stroke, forKey: .stroke)
        case .deviceBezel(let p):
            try c.encode(p.device, forKey: .device)
            try c.encodeIfPresent(p.screenshotAssetId, forKey: .screenshotAssetId)
            try c.encodeIfPresent(p.chromeColor, forKey: .chromeColor)
        case .group(let p):
            try c.encode(p.children, forKey: .children)
        }
    }
}
