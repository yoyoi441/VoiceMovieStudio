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

@Test func macSystemVoicePresetRoundTripsWithoutInventingSpeakerID() throws {
    let source = Character(
        name: "霊夢", baseImageFileName: "reimu.png", defaultSpeakerID: 123,
        defaultVoiceSettings: MacSystemVoiceSupport.BuiltInProfile.reimu.defaultSettings,
        voiceProvider: MacSystemVoiceSupport.providerID,
        voiceLibrary: "com.apple.voice.compact.ja-JP.Kyoko",
        voiceStyle: "Kyoko"
    )
    let encoded = try JSONEncoder().encode(CharacterVoicePreset(character: source))
    let restored = try JSONDecoder().decode(CharacterVoicePreset.self, from: encoded)
    var target = Character(name: "対象", baseImageFileName: "target.png")
    restored.apply(to: &target)

    #expect(target.voiceProvider == MacSystemVoiceSupport.providerID)
    #expect(target.voiceLibrary == "com.apple.voice.compact.ja-JP.Kyoko")
    #expect(target.voiceStyle == "Kyoko")
    #expect(target.defaultSpeakerID == nil)
}

@Test func macSystemVoiceSettingsAreFiniteAndClamped() {
    let settings = VoiceSettings(
        volume: .infinity, pan: -4, pitch: 9, speed: 0,
        intonation: .nan, preSilence: -1, postSilence: 99,
        styleWeights: ["推測した感情": 1]
    ).validatedForMacSystemVoice()
    #expect(settings.volume == 1)
    #expect(settings.pan == -1)
    #expect(settings.pitch == 2)
    #expect(settings.speed == 0.5)
    #expect(settings.intonation == 1)
    #expect(settings.preSilence == 0)
    #expect(settings.postSilence == 5)
    #expect(settings.styleWeights == nil)
}

@Test func aquesTalkPlayerCommandUsesDocumentedArgumentsAndOptionalPreset() {
    #expect(AquesTalkPlayerSupport.bundleIdentifier == "a-quest.AquesTalkPlayer")
    #expect(AquesTalkPlayerSupport.commandArguments(
        text: "こんにちは", presetName: "霊夢用", wavPath: "/tmp/test.wav"
    ) == ["-T", "こんにちは", "-P", "霊夢用", "-W", "/tmp/test.wav"])
    #expect(AquesTalkPlayerSupport.commandArguments(
        text: "こんにちは", presetName: "  ", wavPath: "/tmp/test.wav"
    ) == ["-T", "こんにちは", "-W", "/tmp/test.wav"])
}

@Test func aquesTalkPlayerPresetNamesKeepMenuOrderAndRemoveInvalidRows() {
    #expect(AquesTalkPlayerSupport.normalizedPresetNames([
        " デフォルト ", "れいむ", "", "-", "れいむ", "まりさ\n"
    ]) == ["デフォルト", "れいむ", "まりさ"])
}

@Test func aquesTalkPlayerPresetRoundTripsWithoutStoringLicenseKey() throws {
    let source = Character(
        name: "霊夢", baseImageFileName: "reimu.png", defaultSpeakerID: 7,
        voiceProvider: AquesTalkPlayerSupport.providerID,
        voiceLibrary: "霊夢用",
        voiceStyle: ""
    )
    let data = try JSONEncoder().encode(CharacterVoicePreset(character: source))
    let encoded = String(decoding: data, as: UTF8.self)
    #expect(!encoded.localizedCaseInsensitiveContains("license"))
    let restored = try JSONDecoder().decode(CharacterVoicePreset.self, from: data)
    var target = Character(name: "対象", baseImageFileName: "target.png")
    restored.apply(to: &target)
    #expect(target.voiceProvider == AquesTalkPlayerSupport.providerID)
    #expect(target.voiceLibrary == "霊夢用")
    #expect(target.defaultSpeakerID == nil)
}

@Test func macSystemCharacterProfilesHaveDistinctDefaults() {
    let reimu = MacSystemVoiceSupport.BuiltInProfile.reimu
    let marisa = MacSystemVoiceSupport.BuiltInProfile.marisa
    #expect(reimu.displayName == "霊夢向け")
    #expect(marisa.displayName == "魔理沙向け")
    #expect(reimu.preferredVoiceNames.first == "Kyoko")
    #expect(marisa.preferredVoiceNames.first == "Reed")
    #expect(reimu.defaultSettings != marisa.defaultSettings)
}
