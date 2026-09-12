import Foundation

/// One "mora" (roughly, one kana beat) of synthesized speech, with timing in seconds
/// relative to the start of the audio clip. Used to drive auto lip-sync keyframes and
/// auto-generated subtitle timing.
public struct MoraTiming: Codable, Hashable, Sendable {
    public var text: String
    public var startTime: TimeInterval
    public var duration: TimeInterval
    /// True for pauses/silence (no mouth movement).
    public var isPause: Bool
    /// Vowel sound ("a", "i", "u", "e", "o"), when known — used to pick a mouth shape
    /// for auto lip-sync. Nil for pauses.
    public var vowel: String?

    public init(text: String, startTime: TimeInterval, duration: TimeInterval, isPause: Bool = false, vowel: String? = nil) {
        self.text = text
        self.startTime = startTime
        self.duration = duration
        self.isPause = isPause
        self.vowel = vowel
    }
}

public struct SynthesizedSpeech: Sendable {
    /// WAV audio data, ready to write to disk.
    public var audioData: Data
    public var moraTimings: [MoraTiming]
    public var duration: TimeInterval

    public init(audioData: Data, moraTimings: [MoraTiming], duration: TimeInterval) {
        self.audioData = audioData
        self.moraTimings = moraTimings
        self.duration = duration
    }
}

public struct VoiceSpeaker: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var styleName: String

    public init(id: Int, name: String, styleName: String) {
        self.id = id
        self.name = name
        self.styleName = styleName
    }
}

/// Abstraction over a local/remote text-to-speech engine. VOICEVOX is the first
/// implementation because it ships an official macOS build and exposes per-mora timing
/// over a local HTTP API. ExternalVoiceImport handles product-exported audio separately;
/// it does not claim API synthesis support for file-based providers.
public protocol VoiceEngine: Sendable {
    func availableSpeakers() async throws -> [VoiceSpeaker]
    func synthesize(text: String, speakerID: Int, settings: VoiceSettings) async throws -> SynthesizedSpeech
}

public extension VoiceEngine {
    /// Convenience for callers that don't need to customize synthesis parameters.
    func synthesize(text: String, speakerID: Int) async throws -> SynthesizedSpeech {
        try await synthesize(text: text, speakerID: speakerID, settings: VoiceSettings())
    }
}

public enum VoiceEngineError: Error, LocalizedError {
    case engineUnreachable(underlying: Error)
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .engineUnreachable:
            return "音声合成エンジンに接続できませんでした。VOICEVOXアプリ/エンジンが起動しているか確認してください。"
        case .unexpectedResponse(let detail):
            return "音声合成エンジンから予期しない応答がありました: \(detail)"
        }
    }
}
