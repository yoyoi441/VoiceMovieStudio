import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum DroppedMaterialKind: String {
    case characterProfile
    case characterArtwork
    case characterArchive
    case video
    case audio
    case image
    case unsupported
}

struct MaterialClassification {
    var url: URL
    var kind: DroppedMaterialKind
    var reason: String
}

enum MaterialFileClassifier {
    static func classify(_ url: URL) -> MaterialClassification {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            if containsProfileJSON(url) { return .init(url: url, kind: .characterProfile, reason: "設定JSONを含むフォルダ") }
            if childFiles(url).contains(where: { $0.pathExtension.lowercased() == "psd" }) {
                return .init(url: url, kind: .characterArtwork, reason: "PSD立ち絵を含むフォルダ")
            }
            if containsCharacterParts(url) { return .init(url: url, kind: .characterArtwork, reason: "複数の立ち絵パーツを含むフォルダ") }
            return .init(url: url, kind: .unsupported, reason: "対応する素材を確認できないフォルダ")
        }

        if url.pathExtension.lowercased() == "json", isCharacterProfile(url) {
            return .init(url: url, kind: .characterProfile, reason: "キャラクター項目を含むJSON")
        }
        if url.pathExtension.lowercased() == "psd" {
            return .init(url: url, kind: .characterArtwork, reason: "レイヤー付きキャラクターファイル")
        }
        if url.pathExtension.lowercased() == "zip" {
            return .init(url: url, kind: .characterArchive, reason: "素材ZIPを展開して内容を判定")
        }
        let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
            return .init(url: url, kind: .video, reason: "動画として読み取り可能")
        }
        if type?.conforms(to: .audio) == true {
            return .init(url: url, kind: .audio, reason: "音声として読み取り可能")
        }
        if type?.conforms(to: .image) == true, NSImage(contentsOf: url) != nil {
            return .init(url: url, kind: .image, reason: "画像として読み取り可能")
        }
        return .init(url: url, kind: .unsupported, reason: "未対応のファイル形式")
    }

    private static func isCharacterProfile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return containsCharacterObject(object)
    }

    private static func containsCharacterObject(_ value: Any) -> Bool {
        if let array = value as? [Any] { return array.contains(where: containsCharacterObject) }
        guard let dictionary = value as? [String: Any] else { return false }
        let keys = Set(dictionary.keys.map { $0.lowercased() })
        let type = dictionary["$type"] as? String ?? ""
        if type.localizedCaseInsensitiveContains("Character") || type.localizedCaseInsensitiveContains("VoiceItem") ||
            keys.contains("charactername") || (keys.contains("name") && !keys.isDisjoint(with: ["voice", "speakerid", "voicetype", "tachie", "tachiefilepath"])) { return true }
        return dictionary.values.contains(where: containsCharacterObject)
    }

    private static func containsProfileJSON(_ directory: URL) -> Bool {
        childFiles(directory).contains { $0.pathExtension.lowercased() == "json" && isCharacterProfile($0) }
    }

    private static func containsCharacterParts(_ directory: URL) -> Bool {
        let images = childFiles(directory).filter { ["png", "jpg", "jpeg", "webp", "psd"].contains($0.pathExtension.lowercased()) }
        guard images.count >= 2 else { return false }
        let partWords = ["口", "目", "眉", "顔", "体", "mouth", "eye", "face", "body"]
        return images.contains { file in partWords.contains { file.lastPathComponent.localizedCaseInsensitiveContains($0) } }
    }

    static func childFiles(_ directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }
    }
}
