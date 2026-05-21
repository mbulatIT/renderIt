import Foundation
import AIImageEditorCore

/// Tiny helpers shared between the inspector and canvas drag-and-drop handlers.
enum ProjectAssetHelper {
    /// Pick a stable, unique asset id derived from a file's basename.
    /// If the file is already registered under any id, reuses that one.
    static func autoAssetId(in doc: Document, path: String) -> String {
        // Reuse an existing asset that already points at the same file.
        if let existing = doc.assets.first(where: { $0.value.path == path })?.key {
            return existing
        }
        let stem = (path as NSString).lastPathComponent.replacingOccurrences(of: " ", with: "_")
        var base = (stem as NSString).deletingPathExtension
        if base.isEmpty { base = "asset" }
        if doc.assets[base] == nil { return base }
        var i = 2
        while doc.assets["\(base)-\(i)"] != nil { i += 1 }
        return "\(base)-\(i)"
    }
}
