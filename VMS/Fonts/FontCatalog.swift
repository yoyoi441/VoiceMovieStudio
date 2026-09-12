import AppKit

/// Every font family installed on this Mac — sourced from `NSFontManager`, which is the
/// same catalog Font Book and every other native app's font panel draws from (System,
/// bundled, and any user-installed fonts), not a fixed/curated list baked into the app.
enum FontCatalog {
    static var allFamilyNames: [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
