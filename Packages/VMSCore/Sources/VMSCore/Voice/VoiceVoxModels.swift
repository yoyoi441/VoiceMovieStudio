import Foundation

// Wire models for the VOICEVOX Engine REST API (default http://127.0.0.1:50021).
//
// VOICEVOX's JSON uses a mixed naming convention (a real quirk of the API, not a typo
// here): `accent_phrases` and the fields inside each mora/accent phrase are snake_case,
// but the top-level scale/length fields on `AudioQuery` (speedScale, prePhonemeLength,
// etc.) are camelCase. A single blanket `.convertToSnakeCase`/`.convertFromSnakeCase`
// strategy can't represent that, so every type below spells out its own `CodingKeys`.

struct VoiceVoxSpeakerResponse: Decodable {
    struct Style: Decodable {
        var name: String
        var id: Int
        var type: String?
    }
    var name: String
    var styles: [Style]
}

struct VoiceVoxMora: Codable {
    var text: String
    var consonant: String?
    var consonantLength: Double?
    var vowel: String
    var vowelLength: Double
    var pitch: Double

    enum CodingKeys: String, CodingKey {
        case text
        case consonant
        case consonantLength = "consonant_length"
        case vowel
        case vowelLength = "vowel_length"
        case pitch
    }
}

struct VoiceVoxAccentPhrase: Codable {
    var moras: [VoiceVoxMora]
    var accent: Int
    var pauseMora: VoiceVoxMora?
    var isInterrogative: Bool?

    enum CodingKeys: String, CodingKey {
        case moras
        case accent
        case pauseMora = "pause_mora"
        case isInterrogative = "is_interrogative"
    }
}

/// Mirrors the full `AudioQuery` object VOICEVOX returns from `/audio_query` and expects
/// back (optionally edited) on `/synthesis`. Kept as a passthrough blob (rather than only
/// pulling out the fields we use) so unrecognized/future fields survive the round trip.
struct VoiceVoxAudioQuery: Codable {
    var accentPhrases: [VoiceVoxAccentPhrase]
    var speedScale: Double
    var pitchScale: Double
    var intonationScale: Double
    var volumeScale: Double
    var prePhonemeLength: Double
    var postPhonemeLength: Double
    var outputSamplingRate: Int
    var outputStereo: Bool
    var kana: String?

    enum CodingKeys: String, CodingKey {
        case accentPhrases = "accent_phrases"
        case speedScale
        case pitchScale
        case intonationScale
        case volumeScale
        case prePhonemeLength
        case postPhonemeLength
        case outputSamplingRate
        case outputStereo
        case kana
    }
}

extension VoiceVoxAudioQuery {
    /// Flattens accent phrases into per-mora timings, in seconds from the start of the
    /// synthesized clip (including the leading `prePhonemeLength` silence).
    func moraTimings() -> [MoraTiming] {
        var timings: [MoraTiming] = []
        let rate = speedScale.isFinite && speedScale > 0 ? speedScale : 1
        var cursor = prePhonemeLength / rate

        func append(_ mora: VoiceVoxMora, isPause: Bool) {
            let duration = ((mora.consonantLength ?? 0) + mora.vowelLength) / rate
            timings.append(
                MoraTiming(
                    text: mora.text,
                    startTime: cursor,
                    duration: duration,
                    isPause: isPause,
                    vowel: isPause ? nil : mora.vowel.lowercased()
                )
            )
            cursor += duration
        }

        for phrase in accentPhrases {
            for mora in phrase.moras {
                append(mora, isPause: false)
            }
            if let pause = phrase.pauseMora {
                append(pause, isPause: true)
            }
        }
        return timings
    }

    /// Total duration in seconds, matching what `/synthesis` will render.
    func totalDuration() -> TimeInterval {
        let moraSum = accentPhrases.reduce(0.0) { partial, phrase in
            let phraseSum = phrase.moras.reduce(0.0) { $0 + ($1.consonantLength ?? 0) + $1.vowelLength }
            let pauseSum = phrase.pauseMora.map { ($0.consonantLength ?? 0) + $0.vowelLength } ?? 0
            return partial + phraseSum + pauseSum
        }
        let rate = speedScale.isFinite && speedScale > 0 ? speedScale : 1
        return (prePhonemeLength + moraSum + postPhonemeLength) / rate
    }
}
