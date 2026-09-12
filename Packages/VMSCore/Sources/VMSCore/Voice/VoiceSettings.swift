import Foundation

/// §7-7. Provider-agnostic synthesis parameters — deliberately shaped so any `VoiceEngine`
/// can interpret them (not VOICEVOX-specific field names), even though `VoiceVoxClient` is
/// the only implementation wiring them into real synthesis today via `AudioQuery`'s
/// `speedScale`/`pitchScale`/`intonationScale`/`volumeScale`.
public struct VoiceSettings: Codable, Hashable, Sendable {
    /// Playback volume multiplier (1 = 100%).
    public var volume: Double
    /// Stereo pan, -1 (left) ... 1 (right).
    public var pan: Double
    /// Pitch shift. Engine-defined scale; VOICEVOX's usable range is roughly -0.15...0.15.
    public var pitch: Double
    /// Speaking rate multiplier (1 = normal speed).
    public var speed: Double
    /// Pitch-contour exaggeration (1 = engine default).
    public var intonation: Double
    public var preSilence: TimeInterval
    public var postSilence: TimeInterval
    /// Product-defined style strengths (for example a supported joy/anger style).
    /// Optional storage keeps projects created before style mixing was added readable.
    public var styleWeights: [String: Double]? = nil

    public init(
        volume: Double = 1,
        pan: Double = 0,
        pitch: Double = 0,
        speed: Double = 1,
        intonation: Double = 1,
        preSilence: TimeInterval = 0.1,
        postSilence: TimeInterval = 0.1,
        styleWeights: [String: Double]? = nil
    ) {
        self.volume = volume
        self.pan = pan
        self.pitch = pitch
        self.speed = speed
        self.intonation = intonation
        self.preSilence = preSilence
        self.postSilence = postSilence
        self.styleWeights = styleWeights
    }
}
