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
