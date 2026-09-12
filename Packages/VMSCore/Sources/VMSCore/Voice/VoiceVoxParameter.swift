import Foundation

/// VMS editing ranges for VOICEVOX. Other products must define their own units/ranges.
public enum VoiceVoxParameter: String, CaseIterable, Identifiable, Sendable {
    case intonation, speed, pitch, volume, preSilence, postSilence
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .intonation: "抑揚"
        case .speed: "話速"
        case .pitch: "声の高さ"
        case .volume: "音量"
        case .preSilence: "開始無音"
        case .postSilence: "終了無音"
        }
    }
    public var range: ClosedRange<Double> {
        switch self {
        case .speed: 0.5...2
        case .pitch: -0.15...0.15
        default: 0...2
        }
    }
    public var defaultValue: Double {
        switch self {
        case .pitch: 0
        case .preSilence, .postSilence: 0.1
        default: 1
        }
    }
    public var keyPath: WritableKeyPath<VoiceSettings, Double> {
        switch self {
        case .intonation: \.intonation
        case .speed: \.speed
        case .pitch: \.pitch
        case .volume: \.volume
        case .preSilence: \.preSilence
        case .postSilence: \.postSilence
        }
    }
    public func clamp(_ value: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : defaultValue
    }
}

public extension VoiceSettings {
    func validatedForVoiceVox() -> VoiceSettings {
        var copy = self
        for parameter in VoiceVoxParameter.allCases {
            copy[keyPath: parameter.keyPath] = parameter.clamp(copy[keyPath: parameter.keyPath])
        }
        return copy
    }
}
