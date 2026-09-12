import Foundation

/// Saved voice assignment. Names are exact product names, never inferred from artwork names.
public struct CharacterVoicePreset: Codable, Hashable, Sendable {
    public var provider: String
    public var speakerName: String
    public var styleName: String
    public var speakerID: Int?
    public var settings: VoiceSettings

    public init(character: Character) {
        provider = character.voiceProvider.isEmpty && character.defaultSpeakerID != nil ? "VOICEVOX" : character.voiceProvider
        speakerName = character.voiceLibrary
        styleName = character.voiceStyle
        speakerID = character.defaultSpeakerID
        settings = character.defaultVoiceSettings
    }

    public func apply(to character: inout Character) {
        character.voiceProvider = provider
        character.voiceLibrary = speakerName
        character.voiceStyle = styleName
        character.defaultSpeakerID = provider == "VOICEVOX" ? speakerID : nil
        character.defaultVoiceSettings = settings
    }

    public func resolveVoiceVox(in speakers: [VoiceSpeaker]) -> VoiceSpeaker? {
        guard provider == "VOICEVOX" else { return nil }
        if !speakerName.isEmpty {
            let exact = speakers.filter { $0.name == speakerName && $0.styleName == styleName }
            return exact.count == 1 ? exact[0] : nil
        }
        // Only old presets without names may fall back to their persisted engine ID.
        return speakers.first { $0.id == speakerID }
    }
}
