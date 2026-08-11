import Foundation
import AIImageEditorCore

/// Helpers that turn Args into typed values.
enum Parse {
    static func frame(args: Args, canvas: Canvas?, defaultSize: (Double, Double)? = nil) throws -> Frame {
        if let f = args.string("frame") {
            return try Frame.parse(f)
        }
        // Build from --at / --size
        var size: (Double, Double) = defaultSize ?? (320, 120)
        if let s = args.string("size") {
            let parts = s.split(whereSeparator: { ",x ".contains($0) }).compactMap { Double($0) }
            guard parts.count == 2 else { throw EditorError.usage("--size expects 'w,h'") }
            size = (parts[0], parts[1])
        }
        let anchor = AnchorPosition(token: args.string("at") ?? "center") ?? .center
        guard let canvas else { throw EditorError.usage("--frame or --at requires a canvas") }
        return anchor.frame(layerSize: size, canvas: canvas)
    }

    static func color(args: Args, key: String, default fallback: Color) -> Color {
        if let s = args.string(key) {
            return (try? Color(hex: s)) ?? fallback
        }
        return fallback
    }

    static func optionalColor(args: Args, key: String) throws -> Color? {
        guard let s = args.string(key) else { return nil }
        return try Color(hex: s)
    }

    static func position(args: Args, canvas: Canvas, layerSize: (Double, Double)) throws -> (Double, Double) {
        if let t = args.string("to") {
            let parts = t.split(whereSeparator: { ",x ".contains($0) }).compactMap { Double($0) }
            guard parts.count == 2 else { throw EditorError.usage("--to expects 'x,y'") }
            return (parts[0], parts[1])
        }
        if let atToken = args.string("at"), let anchor = AnchorPosition(token: atToken) {
            let f = anchor.frame(layerSize: layerSize, canvas: canvas)
            return (f.x, f.y)
        }
        if let dx = try args.double("dx"), let dy = try args.double("dy") {
            return (dx, dy) // caller adds to current
        }
        throw EditorError.usage("expected --to / --at / --dx --dy")
    }

    static func weight(args: Args, key: String = "font-weight", default fallback: FontWeight = .regular) -> FontWeight {
        if let s = args.string(key)?.lowercased() {
            return FontWeight(rawValue: s) ?? fallback
        }
        return fallback
    }

    static func alignment(args: Args, key: String = "align", default fallback: TextAlignment = .center) -> TextAlignment {
        if let s = args.string(key)?.lowercased() {
            return TextAlignment(rawValue: s) ?? fallback
        }
        return fallback
    }

    static func contentMode(args: Args, key: String = "content-mode", default fallback: ContentMode = .fit) -> ContentMode {
        if let s = args.string(key)?.lowercased() {
            return ContentMode(rawValue: s) ?? fallback
        }
        return fallback
    }

    /// Build a `GradientLayerPayload` from CLI flags.
    /// `--stops "color@pos,color@pos,..."` (e.g. `"#000@0,#FFF@1"`)
    /// `--type linear|radial` (default `linear`)
    /// `--start "x,y"`, `--end "x,y"` — normalized 0..1 (defaults: `0,0` → `0,1` top-to-bottom)
    /// `--corner-radius N`
    static func gradientPayload(args: Args) throws -> GradientLayerPayload {
        let type: GradientType
        if let s = args.string("type")?.lowercased() {
            guard let t = GradientType(rawValue: s) else {
                throw EditorError.usage("--type expects linear or radial")
            }
            type = t
        } else {
            type = .linear
        }
        let stops: [GradientStop]
        if let raw = args.string("stops") {
            let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var parsed: [GradientStop] = []
            for (i, part) in parts.enumerated() {
                let bits = part.split(separator: "@").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let first = bits.first, !first.isEmpty else {
                    throw EditorError.usage("--stops entry missing color: '\(part)'")
                }
                let color = try Color(hex: first)
                let pos: Double
                if bits.count >= 2, let p = Double(bits[1]) { pos = p }
                else if parts.count == 1 { pos = 0 }
                else { pos = Double(i) / Double(parts.count - 1) }
                parsed.append(.init(color: color, at: pos))
            }
            guard !parsed.isEmpty else { throw EditorError.usage("--stops must contain at least one entry") }
            stops = parsed
        } else {
            stops = [.init(color: .black, at: 0), .init(color: .white, at: 1)]
        }
        let (sx, sy) = try point(args: args, key: "start") ?? (0, 0)
        let (ex, ey) = try point(args: args, key: "end") ?? (0, 1)
        return GradientLayerPayload(type: type, stops: stops,
                                    startX: sx, startY: sy,
                                    endX: ex, endY: ey)
    }

    private static func point(args: Args, key: String) throws -> (Double, Double)? {
        guard let s = args.string(key) else { return nil }
        let parts = s.split(whereSeparator: { ",x ".contains($0) }).compactMap { Double($0) }
        guard parts.count == 2 else { throw EditorError.usage("--\(key) expects 'x,y'") }
        return (parts[0], parts[1])
    }

    /// Public version of `point` — used by shape commands for `--start`/`--end` (normalized 0..1).
    static func normalizedPoint(args: Args, key: String) throws -> (Double, Double)? {
        try point(args: args, key: key)
    }

    /// Parse `--stops "radius@pos,radius@pos,..."` for the blur layer's variable-radius
    /// gradient (positions normalized 0…1; radius in canvas pixels). Returns nil if `--stops`
    /// wasn't provided; throws on malformed entries. Entries may omit `@pos`, in which case
    /// positions are spread evenly along 0…1.
    static func blurStops(args: Args) throws -> [BlurStop]? {
        guard let raw = args.string("stops") else { return nil }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else {
            throw EditorError.usage("--stops must contain at least one entry")
        }
        var stops: [BlurStop] = []
        for (i, part) in parts.enumerated() {
            let bits = part.split(separator: "@").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = bits.first, let r = Double(first), r >= 0 else {
                throw EditorError.usage("--stops entry missing or invalid radius: '\(part)'")
            }
            let pos: Double
            if bits.count >= 2, let p = Double(bits[1]) { pos = p }
            else if parts.count == 1 { pos = 0 }
            else { pos = Double(i) / Double(parts.count - 1) }
            stops.append(.init(radius: r, at: pos))
        }
        return stops
    }

    /// Parse a `--stroke "color,width"` flag.
    static func stroke(args: Args) throws -> Stroke? {
        guard let s = args.string("stroke") else { return nil }
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let c = try? Color(hex: parts[0]), let w = Double(parts[1]) else {
            throw EditorError.usage("--stroke expects 'color,width'")
        }
        return Stroke(color: c, width: w)
    }

    static func shadow(args: Args) -> Shadow? {
        guard let s = args.string("shadow") else { return nil }
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4,
              let color = try? Color(hex: parts[0]),
              let dx = Double(parts[1]), let dy = Double(parts[2]), let blur = Double(parts[3]) else {
            return nil
        }
        return Shadow(color: color, offsetX: dx, offsetY: dy, blur: blur)
    }
}
