import Foundation
import CoreGraphics

/// Top-left origin rectangle in document/canvas coordinate space (pixels).
public struct Frame: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        self.init(x: x, y: y, w: w, h: h)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    public var center: (Double, Double) { (x + w / 2, y + h / 2) }

    /// Parse "x,y,w,h" with arbitrary whitespace.
    public static func parse(_ string: String) throws -> Frame {
        let parts = string.split(whereSeparator: { ",\t ".contains($0) }).map { String($0) }
        guard parts.count == 4, let x = Double(parts[0]), let y = Double(parts[1]),
              let w = Double(parts[2]), let h = Double(parts[3])
        else { throw EditorError.invalidFrame(string) }
        return Frame(x: x, y: y, w: w, h: h)
    }

    // MARK: - Codable as [x, y, w, h]
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
        w = try c.decode(Double.self)
        h = try c.decode(Double.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x); try c.encode(y); try c.encode(w); try c.encode(h)
    }
}

/// Symbolic positioning relative to canvas.
public enum AnchorPosition: String, Codable, CaseIterable, Sendable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight

    public init?(token: String) {
        let t = token.lowercased().replacingOccurrences(of: "_", with: "-")
        switch t {
        case "top-left", "topleft":           self = .topLeft
        case "top", "top-center", "topcenter":self = .topCenter
        case "top-right", "topright":         self = .topRight
        case "left", "center-left":           self = .centerLeft
        case "center", "middle":              self = .center
        case "right", "center-right":         self = .centerRight
        case "bottom-left", "bottomleft":     self = .bottomLeft
        case "bottom", "bottom-center":       self = .bottomCenter
        case "bottom-right", "bottomright":   self = .bottomRight
        default: return nil
        }
    }

    /// Compute a frame for a layer of given size, snapped to the canvas with a small margin.
    public func frame(layerSize: (Double, Double), canvas: Canvas, margin: Double? = nil) -> Frame {
        let (w, h) = layerSize
        let mX = margin ?? Double(canvas.width) * 0.04
        let mY = margin ?? Double(canvas.height) * 0.04
        let cw = Double(canvas.width), ch = Double(canvas.height)
        var x: Double = (cw - w) / 2
        var y: Double = (ch - h) / 2
        switch self {
        case .topLeft:      x = mX;          y = mY
        case .topCenter:    x = (cw - w) / 2; y = mY
        case .topRight:     x = cw - w - mX; y = mY
        case .centerLeft:   x = mX;          y = (ch - h) / 2
        case .center:       x = (cw - w) / 2; y = (ch - h) / 2
        case .centerRight:  x = cw - w - mX; y = (ch - h) / 2
        case .bottomLeft:   x = mX;          y = ch - h - mY
        case .bottomCenter: x = (cw - w) / 2; y = ch - h - mY
        case .bottomRight:  x = cw - w - mX; y = ch - h - mY
        }
        return Frame(x: x, y: y, w: w, h: h)
    }
}
