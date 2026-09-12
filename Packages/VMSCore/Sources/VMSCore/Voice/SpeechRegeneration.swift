import Foundation

/// Pure replacement plan. Audio files are immutable, so Undo restores the previous sound too.
public enum SpeechRegeneration {
    public enum Failure: Error, LocalizedError {
        case targetChanged, locked, invalid
        public var errorDescription: String? {
            switch self {
            case .targetChanged: "合成中に対象が変更されたため反映しませんでした。"
            case .locked: "音声または連動アイテムがロックされています。"
            case .invalid: "合成結果が無効です。"
            }
        }
    }

    public static func replacing(original: Clip, in timeline: Timeline, speech: SynthesizedSpeech,
                                 fileName: String, mouthSpeeds: [UUID: Double],
                                 expectedProvider: String? = nil,
                                 amplitudeMouthKeyframes: [MouthKeyframe]? = nil) throws -> Timeline {
        guard speech.duration.isFinite, speech.duration > 0,
              case .audio(let originalData) = original.content,
              originalData.voiceProvider == expectedProvider else { throw Failure.invalid }
        guard timeline.tracks.flatMap(\.clips).contains(original) else { throw Failure.targetChanged }
        var result = timeline
        for t in result.tracks.indices {
            for c in result.tracks[t].clips.indices {
                var clip = result.tracks[t].clips[c]
                let linkedCharacter: Bool
                if case .character(let data) = clip.content {
                    linkedCharacter = data.linkedAudioClipID == original.id
                } else { linkedCharacter = false }
                let linkedSubtitle = clip.id == originalData.linkedSubtitleClipID
                guard clip.id == original.id || linkedCharacter || linkedSubtitle else { continue }
                guard !result.tracks[t].isLocked, !clip.isLocked else { throw Failure.locked }
                if clip.id == original.id {
                    var data = originalData
                    data.fileName = fileName
                    data.moraTimings = speech.moraTimings
                    data.voiceSettings = expectedProvider == nil
                        ? data.voiceSettings.validatedForVoiceVox()
                        : data.voiceSettings
                    clip.content = .audio(data)
                } else if case .character(var data) = clip.content {
                    data.mouthKeyframes = amplitudeMouthKeyframes ?? LipSyncGenerator.keyframes(
                        from: speech.moraTimings, speed: mouthSpeeds[data.characterID] ?? 1)
                    clip.content = .character(data)
                }
                clip.duration = speech.duration
                result.tracks[t].clips[c] = clip
            }
        }
        return result
    }
}
