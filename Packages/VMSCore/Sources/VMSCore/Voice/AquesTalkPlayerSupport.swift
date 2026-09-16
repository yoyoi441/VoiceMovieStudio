import Foundation

public enum AquesTalkPlayerSupport {
    public static let providerID = "AquesTalk Player"
    public static let bundleIdentifier = "a-quest.AquesTalkPlayer"
    public static let officialPageURL = "https://www.a-quest.com/products/aquestalkplayer.html"
    public static let manualURL = "https://www.a-quest.com/products/aquestalkplayer_mac_man.html"
    public static let licenseStoreURL = "https://store.a-quest.com/categories/618932"

    public static let commercialUseNotice =
        "個人かつ非営利の場合に限り無償です。収益化、業務、法人・団体での利用にはAQUESTの使用ライセンスが必要です。"

    public static func commandArguments(text: String, presetName: String, wavPath: String) -> [String] {
        var arguments = ["-T", text]
        let preset = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preset.isEmpty { arguments += ["-P", preset] }
        arguments += ["-W", wavPath]
        return arguments
    }

    /// Keeps the order shown by AquesTalk Player while removing menu separators,
    /// blank rows and duplicate names exposed by the accessibility menu.
    public static func normalizedPresetNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.compactMap { raw in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != "-", seen.insert(name).inserted else { return nil }
            return name
        }
    }
}
