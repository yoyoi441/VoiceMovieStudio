import Foundation

/// Persists favorite/recently-used font family names across launches (`UserDefaults`,
/// same pattern as `PropertySection`'s expand/collapse state) so `FontPickerView`'s
/// "お気に入り"/"最近使った" tabs have something to show beyond the full system list.
enum FontUsageStore {
    private static let favoritesKey = "FontPicker.favorites"
    private static let recentsKey = "FontPicker.recents"
    private static let maxRecents = 12

    static var favorites: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: favoritesKey) }
    }

    static var recents: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: recentsKey) }
    }

    static func toggleFavorite(_ name: String) {
        var current = favorites
        if current.contains(name) {
            current.remove(name)
        } else {
            current.insert(name)
        }
        favorites = current
    }

    static func recordUsed(_ name: String) {
        var current = recents.filter { $0 != name }
        current.insert(name, at: 0)
        if current.count > maxRecents {
            current.removeLast(current.count - maxRecents)
        }
        recents = current
    }
}
