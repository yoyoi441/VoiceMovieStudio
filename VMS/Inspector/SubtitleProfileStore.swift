import Foundation
import Observation
import VMSCore

struct SubtitleProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var fontName: String
    var fontSize: Double
    var color: CodableColor
    var outlineColor: CodableColor
    var outlineWidth: Double
    var isBold: Bool
    var position: CodablePoint

    static let commentary = SubtitleProfile(
        id: UUID(uuidString: "5B4C9341-30BC-4602-9C30-C1F3124A9FB7")!,
        name: "実況字幕",
        fontName: "HiraginoSans-W6",
        fontSize: 64,
        color: .white,
        outlineColor: .black,
        outlineWidth: 5,
        isBold: true,
        position: CodablePoint(x: 0, y: 0.76)
    )
}

@MainActor @Observable
final class SubtitleProfileStore {
    static let shared = SubtitleProfileStore()
    private(set) var profiles: [SubtitleProfile]
    private let key = "subtitle.profiles.v1"

    private init() {
        profiles = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([SubtitleProfile].self, from: $0) } ?? [.commentary]
        if !profiles.contains(where: { $0.id == SubtitleProfile.commentary.id }) {
            profiles.insert(.commentary, at: 0)
        }
    }

    func save(name: String, from data: TextClipData, effects: ClipEffects) {
        let outline = effects.effectsList.compactMap { effect -> TextOutlineEffect? in
            guard effect.isEnabled, case .outline(let value) = effect.kind else { return nil }
            return value
        }.first ?? TextOutlineEffect()
        profiles.append(SubtitleProfile(id: UUID(), name: name, fontName: data.fontName, fontSize: data.fontSize, color: data.color, outlineColor: outline.color, outlineWidth: outline.width, isBold: data.isBold, position: data.position))
        persist()
    }

    func remove(_ id: UUID) {
        guard id != SubtitleProfile.commentary.id else { return }
        profiles.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: key) }
    }
}

extension ProjectStore {
    func applySubtitleProfile(_ profile: SubtitleProfile) {
        beginUndoableChange()
        var timeline = currentTimeline
        for trackIndex in timeline.tracks.indices {
            for clipIndex in timeline.tracks[trackIndex].clips.indices {
                guard selectedClipIDs.contains(timeline.tracks[trackIndex].clips[clipIndex].id),
                      case .text(var data) = timeline.tracks[trackIndex].clips[clipIndex].content else { continue }
                data.fontName = profile.fontName
                data.fontSize = profile.fontSize
                data.color = profile.color
                data.decorationColor = profile.outlineColor
                data.isBold = profile.isBold
                data.alignment = .center
                data.position = profile.position
                timeline.tracks[trackIndex].clips[clipIndex].content = .text(data)
                var effects = timeline.tracks[trackIndex].clips[clipIndex].effects
                effects.effectsList.removeAll { if case .outline = $0.kind { return true }; return false }
                effects.effectsList.append(Effect(kind: .outline(TextOutlineEffect(color: profile.outlineColor, width: profile.outlineWidth))))
                timeline.tracks[trackIndex].clips[clipIndex].effects = effects
            }
        }
        currentTimeline = timeline
    }
}
