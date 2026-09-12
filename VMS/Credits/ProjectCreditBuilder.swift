import Foundation
import VMSCore

struct ProjectCreditEntry: Identifiable {
    var id: String
    var category: String
    var credit: CreditMetadata
}

enum ProjectCreditBuilder {
    static func usedEntries(project: Project) -> [ProjectCreditEntry] {
        let clips = project.scenes.flatMap(\.timeline.tracks).flatMap(\.clips)
        let usedCharacterIDs = Set(clips.compactMap { clip -> UUID? in
            if case .character(let data) = clip.content { return data.characterID }
            return nil
        })
        let usedFileNames = Set(clips.compactMap { clip -> String? in
            switch clip.content {
            case .audio(let data): return data.fileName
            case .image(let data): return data.fileName
            case .video(let data): return data.fileName
            default: return nil
            }
        })

        var entries = project.characters.filter { usedCharacterIDs.contains($0.id) }.map {
            ProjectCreditEntry(id: "character:\($0.id)", category: "キャラクター", credit: normalized($0.credit, fallback: $0.name))
        }
        entries += project.mediaAssets.filter { usedFileNames.contains($0.fileName) }.map {
            ProjectCreditEntry(id: "asset:\($0.id)", category: category($0.kind), credit: normalized($0.credit, fallback: $0.originalName))
        }
        var seen = Set<String>()
        return entries.filter {
            let key = [$0.credit.title, $0.credit.creator, $0.credit.sourceURL, $0.credit.licenseName].joined(separator: "|").lowercased()
            return seen.insert(key).inserted
        }
    }

    static func descriptionText(project: Project) -> String {
        let entries = usedEntries(project: project)
        guard !entries.isEmpty else { return "使用素材は登録されていません。" }
        var lines = ["【使用素材・クレジット】"]
        for entry in entries {
            var line = "・[\(entry.category)] \(entry.credit.title)"
            if !entry.credit.creator.isEmpty { line += " / \(entry.credit.creator)" }
            if !entry.credit.licenseName.isEmpty { line += " / \(entry.credit.licenseName)" }
            lines.append(line)
            if !entry.credit.sourceURL.isEmpty { lines.append("  \(entry.credit.sourceURL)") }
            if !entry.credit.licenseURL.isEmpty { lines.append("  利用条件: \(entry.credit.licenseURL)") }
            if !entry.credit.note.isEmpty { lines.append("  \(entry.credit.note)") }
        }
        return lines.joined(separator: "\n")
    }

    private static func normalized(_ credit: CreditMetadata, fallback: String) -> CreditMetadata {
        var value = credit
        if value.title.isEmpty { value.title = fallback }
        return value
    }
    private static func category(_ kind: MediaAssetKind) -> String {
        switch kind { case .video: return "動画"; case .audio: return "音声"; case .image: return "画像" }
    }
}
