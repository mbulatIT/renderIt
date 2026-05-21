import Foundation

public enum EditorError: Error, LocalizedError, Equatable {
    case invalidColor(String)
    case invalidFrame(String)
    case unknownPreset(String)
    case unknownBezel(String)
    case assetNotFound(String)
    case layerNotFound(String)
    case duplicateLayerId(String)
    case duplicateAssetId(String)
    case fileIO(String)
    case decoding(String)
    case encoding(String)
    case usage(String)
    case unsupported(String)
    case renderFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidColor(let s):     return "invalid color: '\(s)' (expected #RRGGBB or #RRGGBBAA)"
        case .invalidFrame(let s):     return "invalid frame: '\(s)' (expected 'x,y,w,h')"
        case .unknownPreset(let s):    return "unknown preset: '\(s)'. Run `presets` to list."
        case .unknownBezel(let s):     return "unknown device bezel: '\(s)'. Run `bezels` to list."
        case .assetNotFound(let id):   return "asset not found: '\(id)'"
        case .layerNotFound(let id):   return "layer not found: '\(id)'"
        case .duplicateLayerId(let id):return "duplicate layer id: '\(id)'"
        case .duplicateAssetId(let id):return "duplicate asset id: '\(id)'"
        case .fileIO(let s):           return "file I/O error: \(s)"
        case .decoding(let s):         return "decoding error: \(s)"
        case .encoding(let s):         return "encoding error: \(s)"
        case .usage(let s):            return "usage: \(s)"
        case .unsupported(let s):      return "unsupported: \(s)"
        case .renderFailed(let s):     return "render failed: \(s)"
        }
    }
}
