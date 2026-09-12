import AppKit
import Foundation
import UniformTypeIdentifiers
import VMSCore

struct ProfileImportReport {
    var characters: [Character]
    var filesRead: Int
    var warnings: [String]
}

enum CharacterProfileImporter {
    @MainActor
    static func prompt() throws -> ProfileImportReport? {
        let panel = NSOpenPanel()
        panel.title = "キャラクタープロファイルまたは設定フォルダを選択"
        panel.prompt = "読み込む"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK else { return nil }
        return try importURLs(panel.urls)
    }

    static func importURLs(_ roots: [URL]) throws -> ProfileImportReport {
        var files: [URL] = []
        for root in roots {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let url = enumerator?.nextObject() as? URL {
                    if url.pathExtension.lowercased() == "json" { files.append(url) }
                }
            } else if root.pathExtension.lowercased() == "json" {
                files.append(root)
            }
        }

        var imported: [Character] = []
        var warnings: [String] = []
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let root = try JSONSerialization.jsonObject(with: data)
                let dictionaries = characterDictionaries(in: root)
                for dictionary in dictionaries {
                    guard let name = string(dictionary, ["Name", "CharacterName", "DisplayName"]), !name.isEmpty else { continue }
                    let raw = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
                    let rawString = String(data: raw, encoding: .utf8)
                    let volume = number(dictionary, ["Volume", "VoiceVolume"]).map(normalizePercent) ?? 1
                    let pan = number(dictionary, ["Pan"]).map { max(-1, min(1, abs($0) > 1 ? $0 / 100 : $0)) } ?? 0
                    let speed = number(dictionary, ["Speed", "VoiceSpeed", "PlaybackRate"]).map(normalizePercent) ?? 1
                    let pitch = number(dictionary, ["Pitch", "VoicePitch"]).map { abs($0) > 1 ? $0 / 100 : $0 } ?? 0
                    let intonation = number(dictionary, ["Intonation", "VoiceIntonation"]).map(normalizePercent) ?? 1
                    imported.append(Character(
                        name: name,
                        groupName: string(dictionary, ["GroupName", "Group"]) ?? "",
                        tachieKind: tachieKind(dictionary),
                        baseImageFileName: "",
                        defaultSpeakerID: integer(dictionary, ["SpeakerID", "StyleID", "VoiceID"]),
                        defaultVoiceSettings: VoiceSettings(volume: volume, pan: pan, pitch: pitch, speed: speed, intonation: intonation),
                        importedSource: "external-profile",
                        importedSourceID: string(dictionary, ["ID", "Id", "CharacterID"]),
                        importedRawJSON: rawString,
                        shortcut: string(dictionary, ["Shortcut", "HotKey"]) ?? "",
                        preferredLayer: integer(dictionary, ["Layer", "DefaultLayer"]) ?? 0,
                        voiceProvider: string(dictionary, ["VoiceProvider", "VoiceEngine", "VoiceType"]) ?? "",
                        voiceLibrary: string(dictionary, ["VoiceLibrary", "SpeakerName", "VoiceName"]) ?? "",
                        voiceStyle: string(dictionary, ["Style", "StyleName"]) ?? "",
                        usageTerms: string(dictionary, ["Terms", "UsageTerms", "Description"]) ?? "",
                        credit: CreditMetadata(
                            title: string(dictionary, ["MaterialName", "Title"]) ?? name,
                            creator: string(dictionary, ["Creator", "Author", "Artist"]) ?? "",
                            sourceURL: string(dictionary, ["SourceURL", "DistributionURL", "Url"]) ?? "",
                            licenseName: string(dictionary, ["License", "LicenseName"]) ?? "",
                            licenseURL: string(dictionary, ["LicenseURL", "TermsURL"]) ?? "",
                            note: string(dictionary, ["Credit", "Attribution"]) ?? ""
                        )
                    ))
                }
            } catch {
                warnings.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Profile collections can repeat one character in multiple setting files.
        var seen = Set<String>()
        imported = imported.filter {
            let key = ($0.importedSourceID?.isEmpty == false ? $0.importedSourceID! : $0.name).lowercased()
            return seen.insert(key).inserted
        }
        if imported.isEmpty { warnings.append("認識できるキャラクター設定が見つかりませんでした。") }
        return ProfileImportReport(characters: imported, filesRead: files.count, warnings: warnings)
    }

    private static func characterDictionaries(in value: Any) -> [[String: Any]] {
        if let array = value as? [Any] { return array.flatMap(characterDictionaries) }
        guard let dictionary = value as? [String: Any] else { return [] }
        let type = string(dictionary, ["$type"]) ?? ""
        let keys = Set(dictionary.keys.map { $0.lowercased() })
        let looksLikeCharacter = type.localizedCaseInsensitiveContains("VoiceItem") ||
            type.localizedCaseInsensitiveContains("Character") ||
            keys.contains("charactername") ||
            (keys.contains("name") && !keys.isDisjoint(with: ["voice", "voiceid", "speakerid", "voicetype", "tachie", "tachiefilepath"]))
        var result = looksLikeCharacter ? [dictionary] : []
        result += dictionary.values.flatMap(characterDictionaries)
        return result
    }

    private static func rawValue(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any], let values = dictionary["Values"] as? [[String: Any]], let first = values.first, let v = first["Value"] { return v }
        return value
    }
    private static func string(_ d: [String: Any], _ keys: [String]) -> String? {
        for key in keys { if let value = d[key] { return rawValue(value) as? String } }
        return nil
    }
    private static func number(_ d: [String: Any], _ keys: [String]) -> Double? {
        for key in keys { if let n = rawValue(d[key] as Any) as? NSNumber { return n.doubleValue } }
        return nil
    }
    private static func integer(_ d: [String: Any], _ keys: [String]) -> Int? { number(d, keys).map(Int.init) }
    private static func normalizePercent(_ value: Double) -> Double { value > 5 ? value / 100 : value }
    private static func tachieKind(_ d: [String: Any]) -> TachieKind {
        let value = string(d, ["TachieType", "TachieKind", "StandingPictureType"])?.lowercased() ?? ""
        if value.contains("psd") { return .psd }
        if value.contains("動") || value.contains("animated") { return .animated }
        if value.contains("none") || value.contains("表示しない") { return .none }
        return .simple
    }
}
