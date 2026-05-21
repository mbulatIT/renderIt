import Foundation
import AppKit

public enum FontCatalog {
    /// All installed font family names, sorted alphabetically.
    public static func availableFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }
}
