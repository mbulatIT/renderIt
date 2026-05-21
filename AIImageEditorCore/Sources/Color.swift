import Foundation
import CoreGraphics

/// Simple RGBA color in 0...1 space, hex round-trippable.
public struct Color: Codable, Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let white = Color(r: 1, g: 1, b: 1)
    public static let black = Color(r: 0, g: 0, b: 0)
    public static let clear = Color(r: 0, g: 0, b: 0, a: 0)

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    // MARK: - Hex

    public init(hex: String) throws {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "transparent" {
            self = .clear
            return
        }
        var str = trimmed
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6 || str.count == 8 else {
            throw EditorError.invalidColor(hex)
        }
        let scanner = Scanner(string: str)
        var raw: UInt64 = 0
        guard scanner.scanHexInt64(&raw) else { throw EditorError.invalidColor(hex) }
        if str.count == 6 {
            r = Double((raw >> 16) & 0xFF) / 255.0
            g = Double((raw >> 8)  & 0xFF) / 255.0
            b = Double( raw        & 0xFF) / 255.0
            a = 1.0
        } else {
            r = Double((raw >> 24) & 0xFF) / 255.0
            g = Double((raw >> 16) & 0xFF) / 255.0
            b = Double((raw >> 8)  & 0xFF) / 255.0
            a = Double( raw        & 0xFF) / 255.0
        }
    }

    public var hex: String {
        let rr = Int((r * 255).rounded()).clamped(0, 255)
        let gg = Int((g * 255).rounded()).clamped(0, 255)
        let bb = Int((b * 255).rounded()).clamped(0, 255)
        let aa = Int((a * 255).rounded()).clamped(0, 255)
        if aa == 255 {
            return String(format: "#%02X%02X%02X", rr, gg, bb)
        } else {
            return String(format: "#%02X%02X%02X%02X", rr, gg, bb, aa)
        }
    }

    // MARK: - Codable (string form)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        try self.init(hex: str)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

private extension Comparable {
    func clamped(_ low: Self, _ high: Self) -> Self {
        min(max(self, low), high)
    }
}
