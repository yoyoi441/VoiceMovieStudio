import Foundation

public struct BulkClipMatch: Hashable, Sendable {
    public var clipIDs: Set<UUID>
    public var characterClipIDs: Set<UUID>
    public var audioClipIDs: Set<UUID>
    public var subtitleClipIDs: Set<UUID>

    public init(
        clipIDs: Set<UUID> = [],
        characterClipIDs: Set<UUID> = [],
        audioClipIDs: Set<UUID> = [],
        subtitleClipIDs: Set<UUID> = []
    ) {
        self.clipIDs = clipIDs
        self.characterClipIDs = characterClipIDs
        self.audioClipIDs = audioClipIDs
        self.subtitleClipIDs = subtitleClipIDs
    }
}

/// Finds dialogue bundles without relying on track names or track order. A generated
/// voice, its linked subtitle, and every character linked to that voice are treated as
/// one unit so selection and replacement cannot silently split them apart.
public enum BulkClipMatcher {
    public static func matching(
        in timeline: Timeline,
        sourceCharacterID: UUID?,
        phrase: String
    ) -> BulkClipMatch {
        let clips = timeline.tracks.flatMap(\.clips)
        let byID = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        let query = phrase.trimmingCharacters(in: .whitespacesAndNewlines)

        let audioClips: [UUID: AudioClipData] = Dictionary(uniqueKeysWithValues: clips.compactMap { clip in
            guard case .audio(let data) = clip.content else { return nil }
            return (clip.id, data)
        })
        let charactersByAudio = Dictionary(grouping: clips.compactMap { clip -> (UUID, Clip, CharacterClipData)? in
            guard case .character(let data) = clip.content, let audioID = data.linkedAudioClipID else { return nil }
            return (audioID, clip, data)
        }, by: { $0.0 })

        var result = BulkClipMatch()
        func textMatches(_ text: String?) -> Bool {
            query.isEmpty || text?.localizedCaseInsensitiveContains(query) == true
        }
        func include(character clip: Clip) {
            result.clipIDs.insert(clip.id)
            result.characterClipIDs.insert(clip.id)
        }
        func include(audioID: UUID, data: AudioClipData) {
            result.clipIDs.insert(audioID)
            result.audioClipIDs.insert(audioID)
            if let subtitleID = data.linkedSubtitleClipID, byID[subtitleID] != nil {
                result.clipIDs.insert(subtitleID)
                result.subtitleClipIDs.insert(subtitleID)
            }
        }

        // Character-led bundles are the only safe way to apply a character condition to
        // audio and subtitles because those clips intentionally do not duplicate a character ID.
        for clip in clips {
            guard case .character(let data) = clip.content,
                  sourceCharacterID == nil || data.characterID == sourceCharacterID else { continue }
            guard let audioID = data.linkedAudioClipID, let audio = audioClips[audioID] else {
                if query.isEmpty { include(character: clip) }
                continue
            }
            let subtitleText: String? = audio.linkedSubtitleClipID.flatMap { id in
                guard let subtitle = byID[id], case .text(let text) = subtitle.content else { return nil }
                return text.text
            }
            guard textMatches(audio.sourceText) || textMatches(subtitleText) else { continue }
            include(character: clip)
            include(audioID: audioID, data: audio)
        }

        // With no character condition, standalone speech and subtitle items are also searchable.
        if sourceCharacterID == nil {
            for clip in clips {
                switch clip.content {
                case .audio(let data) where textMatches(data.sourceText):
                    include(audioID: clip.id, data: data)
                    for linked in charactersByAudio[clip.id] ?? [] { include(character: linked.1) }
                case .text(let data) where textMatches(data.text):
                    result.clipIDs.insert(clip.id)
                    result.subtitleClipIDs.insert(clip.id)
                case .character where query.isEmpty:
                    include(character: clip)
                default:
                    break
                }
            }
        }

        return result
    }
}
