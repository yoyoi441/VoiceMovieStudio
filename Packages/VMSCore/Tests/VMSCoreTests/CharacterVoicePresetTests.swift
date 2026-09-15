import Foundation
import Testing
@testable import VMSCore

@Test func characterVoicePresetRoundTripsAndAppliesProductAndSpeaker() throws {
    let source = Character(name: "素材", baseImageFileName: "base.png",
        defaultSpeakerID: 99,
        defaultVoiceSettings: VoiceSettings(
            volume: 1.2, pitch: 1.1, speed: 0.9, intonation: 1.4,
            styleWeights: ["喜び": 0.75, "怒り": 0.1]
        ), voiceProvider: "A.I.VOICE2", voiceLibrary: "話者A", voiceStyle: "喜び")
    let voice = CharacterVoicePreset(character: source)
    var preset = CharacterPreset(name: "音声付き", baseImageFileName: "base.png",
        mouthImageFileNames: [:], eyeImageFileNames: [:], defaultExpressionID: nil, layerVisibility: [:])
    preset.voice = voice
    let restored = try JSONDecoder().decode(CharacterPreset.self, from: JSONEncoder().encode(preset))
    var target = Character(name: "別素材", baseImageFileName: "other.png")
    restored.voice?.apply(to: &target)
    #expect(target.voiceProvider == "A.I.VOICE2")
    #expect(target.voiceLibrary == "話者A")
    #expect(target.voiceStyle == "喜び")
    #expect(target.defaultSpeakerID == nil)
    #expect(target.defaultVoiceSettings.intonation == 1.4)
    #expect(target.defaultVoiceSettings.styleWeights?["喜び"] == 0.75)
    #expect(target.baseImageFileName == "other.png")
}

@Test func legacyCharacterPresetsDoNotOverwriteVoiceSettings() throws {
    let preset = CharacterPreset(name: "旧形式", baseImageFileName: "base.png",
        mouthImageFileNames: [:], eyeImageFileNames: [:], defaultExpressionID: nil, layerVisibility: [:])
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preset)) as! [String: Any]
    json.removeValue(forKey: "voice")
    let restored = try JSONDecoder().decode(CharacterPreset.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(restored.voice == nil)
}

@Test func voiceAssignmentRequiresExactSpeakerAndStyleAndProvider() {
    let candidates = [
        VoiceSpeaker(id: 1, name: "A", styleName: "通常"),
        VoiceSpeaker(id: 2, name: "A", styleName: "喜び")
    ]
    var character = Character(name: "絵", baseImageFileName: "", defaultSpeakerID: 1,
        voiceProvider: "VOICEVOX", voiceLibrary: "A", voiceStyle: "喜び")
    #expect(CharacterVoicePreset(character: character).resolveVoiceVox(in: candidates)?.id == 2)
    character.voiceStyle = "未対応"
    #expect(CharacterVoicePreset(character: character).resolveVoiceVox(in: candidates) == nil)
    character.voiceProvider = "A.I.VOICE2"
    character.voiceStyle = "通常"
    #expect(CharacterVoicePreset(character: character).resolveVoiceVox(in: candidates) == nil)
    character.voiceProvider = ""
    character.voiceLibrary = ""
    #expect(CharacterVoicePreset(character: character).resolveVoiceVox(in: candidates)?.id == 1)
}

@Test func sofTalkPresetRoundTripsWithoutInventingSpeakerID() throws {
    let source = Character(
        name: "霊夢", baseImageFileName: "reimu.png", defaultSpeakerID: 123,
        defaultVoiceSettings: .sofTalkDefault,
        voiceProvider: SofTalkSupport.providerID,
        voiceLibrary: SofTalkSupport.BuiltInProfile.reimu.rawValue,
        voiceStyle: SofTalkSupport.BuiltInProfile.reimu.displayName
    )
    let encoded = try JSONEncoder().encode(CharacterVoicePreset(character: source))
    let restored = try JSONDecoder().decode(CharacterVoicePreset.self, from: encoded)
    var target = Character(name: "対象", baseImageFileName: "target.png")
    restored.apply(to: &target)

    #expect(target.voiceProvider == SofTalkSupport.providerID)
    #expect(target.voiceLibrary == "reimu")
    #expect(target.voiceStyle == "ゆっくり霊夢")
    #expect(target.defaultSpeakerID == nil)
}

@Test func sofTalkSettingsAreFiniteAndClamped() {
    let settings = VoiceSettings(
        volume: .infinity, pan: -4, pitch: 9, speed: 0,
        intonation: .nan, preSilence: -1, postSilence: 99,
        styleWeights: ["推測した感情": 1]
    ).validatedForSofTalk()
    #expect(settings.volume == 1)
    #expect(settings.pan == -1)
    #expect(settings.pitch == 2)
    #expect(settings.speed == 0.5)
    #expect(settings.intonation == 1)
    #expect(settings.preSilence == 0)
    #expect(settings.postSilence == 5)
    #expect(settings.styleWeights == nil)
}
