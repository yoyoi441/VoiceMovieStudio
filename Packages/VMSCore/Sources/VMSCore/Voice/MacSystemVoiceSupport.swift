import Foundation

/// Voice synthesis that is available directly on macOS through AVSpeechSynthesizer.
/// Character-oriented presets choose an installed Japanese system voice at runtime;
/// projects persist the resolved voice identifier so the assignment stays explicit.
public enum MacSystemVoiceSupport {
    public static let providerID = "macOS音声"

    public enum BuiltInProfile: String, CaseIterable, Codable, Identifiable, Sendable {
        case reimu
        case marisa

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .reimu: "霊夢向け"
            case .marisa: "魔理沙向け"
            }
        }

        /// Ordered voice-name preferences. The app only selects names that are actually
        /// installed and always lets the user review or replace the result.
        public var preferredVoiceNames: [String] {
            switch self {
            case .reimu: ["Kyoko", "Sandy", "Flo", "Shelley"]
            case .marisa: ["Reed", "Eddy", "Rocko", "Grandpa"]
            }
        }

        public var defaultSettings: VoiceSettings {
            switch self {
            case .reimu:
                VoiceSettings(volume: 1, pitch: 1.12, speed: 0.92, intonation: 1)
            case .marisa:
                VoiceSettings(volume: 1, pitch: 0.94, speed: 1.05, intonation: 1)
            }
        }
    }
}

public extension VoiceSettings {
    static var macSystemDefault: VoiceSettings {
        VoiceSettings(volume: 1, pitch: 1, speed: 1, intonation: 1)
    }

    func validatedForMacSystemVoice() -> VoiceSettings {
        var result = self
        result.volume = Self.clampMacVoice(result.volume, to: 0...1, fallback: 1)
        result.pan = Self.clampMacVoice(result.pan, to: -1...1, fallback: 0)
        result.pitch = Self.clampMacVoice(result.pitch, to: 0.5...2, fallback: 1)
        result.speed = Self.clampMacVoice(result.speed, to: 0.5...2, fallback: 1)
        // AVSpeechSynthesizer has no independent intonation control.
        result.intonation = 1
        result.preSilence = Self.clampMacVoice(result.preSilence, to: 0...5, fallback: 0.1)
        result.postSilence = Self.clampMacVoice(result.postSilence, to: 0...5, fallback: 0.1)
        result.styleWeights = nil
        return result
    }

    private static func clampMacVoice(
        _ value: Double,
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
