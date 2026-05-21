import Foundation
import AppKit
import AIImageEditorCore

/// Custom pasteboard type for layers (JSON-encoded Layer).
enum LayerClipboard {
    static let pasteboardType = NSPasteboard.PasteboardType("io.tuist.AIImageEditor.layer")

    static func copy(_ layer: Layer) {
        guard let data = try? JSONEncoder().encode(layer) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: pasteboardType)
        // Also expose readable JSON for cross-app inspection.
        if let text = String(data: data, encoding: .utf8) {
            pb.setString(text, forType: .string)
        }
    }

    static func paste() -> Layer? {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: pasteboardType),
           let layer = try? JSONDecoder().decode(Layer.self, from: data) {
            return layer
        }
        if let text = pb.string(forType: .string),
           let data = text.data(using: .utf8),
           let layer = try? JSONDecoder().decode(Layer.self, from: data) {
            return layer
        }
        return nil
    }

    static var hasLayer: Bool {
        let pb = NSPasteboard.general
        if pb.data(forType: pasteboardType) != nil { return true }
        if let text = pb.string(forType: .string),
           let data = text.data(using: .utf8),
           (try? JSONDecoder().decode(Layer.self, from: data)) != nil {
            return true
        }
        return false
    }
}
