import Foundation

/// Editing ranges documented by A.I.VOICE2 for whole-text voice effects.
public enum AIVoice2Parameter: String, CaseIterable, Identifiable, Sendable {
    case volume, speed, pitch, intonation

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .volume: "音量"
        case .speed: "話速"
        case .pitch: "高さ"
        case .intonation: "抑揚"
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .volume, .intonation: 0...2
        case .speed: 0.5...4
        case .pitch: 0.5...2
        }
    }

    public var defaultValue: Double { 1 }

    public var keyPath: WritableKeyPath<VoiceSettings, Double> {
        switch self {
        case .volume: \.volume
        case .speed: \.speed
        case .pitch: \.pitch
        case .intonation: \.intonation
        }
    }

    public func clamp(_ value: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : defaultValue
    }
}

public extension VoiceSettings {
    static var aIVoice2Default: VoiceSettings {
        VoiceSettings(volume: 1, pitch: 1, speed: 1, intonation: 1)
    }

    func validatedForAIVoice2(availableStyleNames: Set<String>? = nil) -> VoiceSettings {
        var copy = self
        for parameter in AIVoice2Parameter.allCases {
            copy[keyPath: parameter.keyPath] = parameter.clamp(copy[keyPath: parameter.keyPath])
        }
        if let styleWeights {
            copy.styleWeights = styleWeights.reduce(into: [:]) { result, entry in
                let (name, value) = entry
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, availableStyleNames?.contains(trimmed) ?? true else { return }
                let clamped = value.isFinite ? min(1, max(0, value)) : 0
                result[trimmed] = clamped
            }
        }
        return copy
    }
}
