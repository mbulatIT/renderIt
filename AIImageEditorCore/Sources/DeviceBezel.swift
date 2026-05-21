import Foundation
import CoreGraphics

public struct DeviceBezel: Sendable {
    public enum Family: String, Sendable { case iphone, iphoneLegacy, ipad, mac }

    public enum Source: Sendable {
        /// Programmatic chrome — drawn entirely by CoreGraphics paths.
        case programmatic(chromeColor: Color,
                          cornerRadius: Double,
                          screenRect: @Sendable (CGRect) -> CGRect,
                          decorate: @Sendable (CGContext, CGRect) -> Void)
        /// Image-backed chrome — a single PNG per color variant. The screen rect is
        /// determined automatically by `BezelImageStore` at render time.
        case imageBacked(defaultColor: String)
    }

    public let id: String
    public let title: String
    public let family: Family
    /// Outer width / outer height.
    public let aspect: Double
    public let source: Source
    /// Available color labels (empty if no color variants).
    public let colors: [String]

    /// Legacy convenience: nominal corner radius (used by GUI selection outlines on programmatic
    /// bezels). For image-backed bezels this is informational only — the renderer uses the image's
    /// actual corners.
    public var cornerRadius: Double {
        if case .programmatic(_, let r, _, _) = source { return r }
        return 0.08
    }

    /// Default chrome color (only meaningful for programmatic bezels).
    public var chromeColor: Color {
        if case .programmatic(let c, _, _, _) = source { return c }
        return Color(r: 0.1, g: 0.1, b: 0.1)
    }
}

public enum DeviceBezelCatalog {
    /// All bezels available to the user — programmatic legacy ones plus everything in the
    /// bundled image manifest.
    public static let all: [DeviceBezel] = makeAll()

    public static func find(id: String) -> DeviceBezel? {
        all.first { $0.id == id }
    }

    private static func makeAll() -> [DeviceBezel] {
        var list: [DeviceBezel] = []

        // 1) Bundled image-backed bezels (loaded from BezelImageStore manifest).
        for entry in BezelImageStore.shared.allDevices {
            let colorList: [String] = preferredColorOrder(entry.colorFiles.keys)
            list.append(DeviceBezel(
                id: entry.id,
                title: entry.title,
                family: entry.family,
                aspect: entry.aspect,
                source: .imageBacked(defaultColor: entry.defaultColor),
                colors: colorList))
        }

        // 2) Legacy programmatic bezels (Mac, iPhone SE) — keep these so older projects open cleanly.
        list.append(contentsOf: legacyProgrammatic())

        return list
    }

    /// Sort colors so that designers see them in a sensible order.
    private static func preferredColorOrder(_ colors: some Collection<String>) -> [String] {
        let preferred = ["Silver", "White", "Cloud white", "Light gold", "Sage", "Lavender",
                         "Mist blue", "Sky blue", "Deep blue", "Space grey", "Space black",
                         "Black", "Cosmic orange", "Default"]
        let set = Set(colors)
        var ordered = preferred.filter { set.contains($0) }
        let remaining = set.subtracting(ordered).sorted()
        ordered.append(contentsOf: remaining)
        return ordered
    }

    private static func legacyProgrammatic() -> [DeviceBezel] {
        return [
            DeviceBezel(
                id: "iphoneSE",
                title: "iPhone SE (legacy)",
                family: .iphoneLegacy,
                aspect: 750.0 / 1334.0,
                source: .programmatic(
                    chromeColor: try! Color(hex: "#0F0F11"),
                    cornerRadius: 0.06,
                    screenRect: { outer in
                        let chromeTop = outer.height * 0.085
                        let chromeBottom = outer.height * 0.095
                        let sideInset = outer.width * 0.025
                        return CGRect(x: outer.minX + sideInset,
                                      y: outer.minY + chromeTop,
                                      width: outer.width - sideInset * 2,
                                      height: outer.height - chromeTop - chromeBottom)
                    },
                    decorate: { ctx, outer in
                        // earpiece slot
                        let slot = CGRect(x: outer.midX - outer.width * 0.10,
                                          y: outer.minY + outer.height * 0.035,
                                          width: outer.width * 0.20,
                                          height: outer.height * 0.006)
                        ctx.setFillColor(CGColor(srgbRed: 0.25, green: 0.25, blue: 0.27, alpha: 1))
                        ctx.fill(slot)
                        let btn = outer.width * 0.085
                        let btnRect = CGRect(x: outer.midX - btn / 2,
                                             y: outer.maxY - outer.height * 0.075,
                                             width: btn, height: btn)
                        ctx.setStrokeColor(CGColor(srgbRed: 0.45, green: 0.45, blue: 0.48, alpha: 1))
                        ctx.setLineWidth(max(1, outer.width * 0.005))
                        ctx.strokeEllipse(in: btnRect)
                    }),
                colors: []),

            DeviceBezel(
                id: "macbookPro14",
                title: "MacBook Pro 14\"",
                family: .mac,
                aspect: 3024.0 / 2200.0,
                source: .programmatic(
                    chromeColor: try! Color(hex: "#16161A"),
                    cornerRadius: 0.02,
                    screenRect: { outer in
                        let displayBottom = outer.minY + outer.height * 0.78
                        let inset = outer.width * 0.012
                        return CGRect(x: outer.minX + inset,
                                      y: outer.minY + inset * 1.6,
                                      width: outer.width - inset * 2,
                                      height: displayBottom - outer.minY - inset * 2)
                    },
                    decorate: drawMacBookStand),
                colors: []),

            DeviceBezel(
                id: "macbookPro16",
                title: "MacBook Pro 16\"",
                family: .mac,
                aspect: 3456.0 / 2400.0,
                source: .programmatic(
                    chromeColor: try! Color(hex: "#16161A"),
                    cornerRadius: 0.018,
                    screenRect: { outer in
                        let displayBottom = outer.minY + outer.height * 0.78
                        let inset = outer.width * 0.012
                        return CGRect(x: outer.minX + inset,
                                      y: outer.minY + inset * 1.6,
                                      width: outer.width - inset * 2,
                                      height: displayBottom - outer.minY - inset * 2)
                    },
                    decorate: drawMacBookStand),
                colors: []),
        ]
    }
}

@Sendable
private func drawMacBookStand(ctx: CGContext, outer: CGRect) {
    let baseTop = outer.minY + outer.height * 0.78
    let base = CGRect(x: outer.minX + outer.width * 0.04,
                      y: baseTop,
                      width: outer.width - outer.width * 0.08,
                      height: outer.height * 0.18)
    let baseColor = CGColor(srgbRed: 0.74, green: 0.75, blue: 0.78, alpha: 1)
    let hingeColor = CGColor(srgbRed: 0.30, green: 0.30, blue: 0.33, alpha: 1)
    let hinge = CGRect(x: outer.minX + outer.width * 0.30,
                       y: baseTop - outer.height * 0.005,
                       width: outer.width * 0.40,
                       height: outer.height * 0.012)
    ctx.setFillColor(hingeColor)
    ctx.fill(hinge)
    let basePath = CGPath(roundedRect: base,
                          cornerWidth: outer.width * 0.012,
                          cornerHeight: outer.width * 0.012,
                          transform: nil)
    ctx.setFillColor(baseColor)
    ctx.addPath(basePath)
    ctx.fillPath()
    let notchWidth = outer.width * 0.10
    let notch = CGRect(x: outer.midX - notchWidth / 2,
                       y: base.maxY - outer.height * 0.018,
                       width: notchWidth,
                       height: outer.height * 0.018)
    let notchPath = CGPath(roundedRect: notch,
                           cornerWidth: outer.width * 0.005,
                           cornerHeight: outer.width * 0.005,
                           transform: nil)
    ctx.setFillColor(CGColor(srgbRed: 0.60, green: 0.60, blue: 0.63, alpha: 1))
    ctx.addPath(notchPath)
    ctx.fillPath()
}
