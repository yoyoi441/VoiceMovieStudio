import SwiftUI

/// A keyboard shortcut plus its display form (`⌘C`, `⇧⌘S`, `Delete`), so tooltips can
/// append it without every call site re-deriving the glyphs.
struct KeyboardShortcutSpec {
    let key: KeyEquivalent
    let modifiers: EventModifiers

    init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.key = key
        self.modifiers = modifiers
    }

    var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        symbols += keyDisplay
        return symbols
    }

    private var keyDisplay: String {
        switch key {
        case .delete: return "Delete"
        case .deleteForward: return "⌦"
        case .escape: return "⎋"
        case .return: return "⏎"
        case .space: return "Space"
        case .tab: return "⇥"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        default: return String(key.character).uppercased()
        }
    }
}
