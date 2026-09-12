import AVFoundation
import Foundation
import Testing
@testable import VMSCore

@Test func aIVoice2SettingsUseDocumentedRangesAndFilterStyles() throws {
    let settings = VoiceSettings(
        volume: 3, pitch: 0, speed: 8, intonation: -1,
        styleWeights: ["喜び": 2, "怒り": -1, "未対応": 0.5]
    ).validatedForAIVoice2(availableStyleNames: ["喜び", "怒り"])
    #expect(settings.volume == 2)
    #expect(settings.pitch == 0.5)
    #expect(settings.speed == 4)
    #expect(settings.intonation == 0)
    #expect(settings.styleWeights == ["喜び": 1, "怒り": 0])

    let oldJSON = Data(#"{"volume":1,"pan":0,"pitch":0,"speed":1,"intonation":1,"preSilence":0.1,"postSilence":0.1}"#.utf8)
    #expect(try JSONDecoder().decode(VoiceSettings.self, from: oldJSON).styleWeights == nil)
}

@Test func voiceVoxSettingsClampInvalidNumbers() {
    let invalid = VoiceSettings(volume: .infinity, pitch: -.infinity, speed: 0, intonation: .nan)
    let safe = invalid.validatedForVoiceVox()
    #expect(safe.volume == 1)
    #expect(safe.pitch == 0)
    #expect(safe.speed == 0.5)
    #expect(safe.intonation == 1)
}

@Test func voiceVoxSpeedChangesMouthAndClipTiming() {
    let mora = VoiceVoxMora(text: "ア", consonant: nil, consonantLength: nil,
                           vowel: "a", vowelLength: 0.8, pitch: 5)
    let query = VoiceVoxAudioQuery(
        accentPhrases: [VoiceVoxAccentPhrase(moras: [mora], accent: 1)],
        speedScale: 2, pitchScale: 0, intonationScale: 1, volumeScale: 1,
        prePhonemeLength: 0.1, postPhonemeLength: 0.1, outputSamplingRate: 24000, outputStereo: false)
    #expect(query.moraTimings()[0].startTime == 0.05)
    #expect(query.moraTimings()[0].duration == 0.4)
    #expect(query.totalDuration() == 0.5)
}

@Test func speechRegenerationKeepsOldAudioAndSynchronizesLinkedClips() throws {
    let subtitle = Clip(startTime: 0, duration: 1, content: .text(TextClipData(text: "テスト")))
    var audioData = AudioClipData(fileName: "old.wav", sourceText: "テスト", speakerID: 1)
    audioData.linkedSubtitleClipID = subtitle.id
    let original = Clip(startTime: 0, duration: 1, content: .audio(audioData))
    let character = Clip(startTime: 0, duration: 1, content: .character(
        CharacterClipData(characterID: UUID(), linkedAudioClipID: original.id)))
    let timeline = Timeline(tracks: [Track(name: "1", clips: [original]),
                                     Track(name: "2", clips: [subtitle]),
                                     Track(name: "3", clips: [character])])
    let speech = SynthesizedSpeech(audioData: Data([1]), moraTimings: [
        MoraTiming(text: "ア", startTime: 0, duration: 2, vowel: "a")
    ], duration: 2)
    let updated = try SpeechRegeneration.replacing(original: original, in: timeline,
        speech: speech, fileName: "new.wav", mouthSpeeds: [:])
    #expect(timeline.tracks[0].clips[0] == original)
    #expect(updated.tracks.flatMap(\.clips).allSatisfy { $0.duration == 2 })
    if case .audio(let data) = updated.tracks[0].clips[0].content {
        #expect(data.fileName == "new.wav")
    } else { Issue.record("Audio missing") }
    if case .character(let data) = updated.tracks[2].clips[0].content {
        #expect(data.mouthShape(at: 1) == .open)
    } else { Issue.record("Character missing") }
    var locked = timeline
    locked.tracks[2].isLocked = true
    #expect(throws: SpeechRegeneration.Failure.self) {
        try SpeechRegeneration.replacing(original: original, in: locked,
            speech: speech, fileName: "new.wav", mouthSpeeds: [:])
    }
    #expect(throws: SpeechRegeneration.Failure.self) {
        try SpeechRegeneration.replacing(original: original, in: Timeline(),
            speech: speech, fileName: "new.wav", mouthSpeeds: [:])
    }
}

@Test func aIVoice2RegenerationRequiresMatchingProviderAndUsesAmplitudeMouthFrames() throws {
    var audioData = AudioClipData(
        fileName: "old.wav", sourceText: "テスト",
        voiceLibrary: "話者A", voiceStyle: "喜び",
        voiceSettings: .aIVoice2Default
    )
    audioData.voiceProvider = "A.I.VOICE2"
    let original = Clip(startTime: 1, duration: 1, content: .audio(audioData))
    let character = Clip(startTime: 1, duration: 1, content: .character(
        CharacterClipData(characterID: UUID(), linkedAudioClipID: original.id)
    ))
    let timeline = Timeline(tracks: [Track(name: "音声", clips: [original]),
                                     Track(name: "立ち絵", clips: [character])])
    let mouth = [MouthKeyframe(time: 0, shape: .closed), MouthKeyframe(time: 0.1, shape: .open)]
    let speech = SynthesizedSpeech(audioData: Data([1]), moraTimings: [], duration: 2)
    let updated = try SpeechRegeneration.replacing(
        original: original, in: timeline, speech: speech, fileName: "new.wav",
        mouthSpeeds: [:], expectedProvider: "A.I.VOICE2", amplitudeMouthKeyframes: mouth
    )
    if case .audio(let data) = updated.tracks[0].clips[0].content {
        #expect(data.voiceProvider == "A.I.VOICE2")
        #expect(data.voiceLibrary == "話者A")
        #expect(data.fileName == "new.wav")
    } else { Issue.record("Audio missing") }
    if case .character(let data) = updated.tracks[1].clips[0].content {
        #expect(data.mouthKeyframes == mouth)
    } else { Issue.record("Character missing") }
    #expect(throws: SpeechRegeneration.Failure.self) {
        try SpeechRegeneration.replacing(
            original: original, in: timeline, speech: speech, fileName: "wrong.wav",
            mouthSpeeds: [:]
        )
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["VMS_TEST_VOICEVOX"] == "1"))
func installedVoiceVoxActuallyChangesIntonationAndStyle() async throws {
    let client = VoiceVoxClient()
    let speakers = try await client.availableSpeakers()
    let speaker = try #require(speakers.first { base in
        speakers.filter { $0.name == base.name }.count > 1
    })
    let alternate = try #require(speakers.first { $0.name == speaker.name && $0.id != speaker.id })
    let calm = try await client.synthesize(text: "ご視聴ありがとうございました。",
        speakerID: speaker.id, settings: VoiceSettings(speed: 1.5, intonation: 0.2))
    let expressive = try await client.synthesize(text: "ご視聴ありがとうございました。",
        speakerID: speaker.id, settings: VoiceSettings(speed: 1.5, intonation: 1.8))
    let other = try await client.synthesize(text: "ご視聴ありがとうございました。",
        speakerID: alternate.id, settings: VoiceSettings(speed: 1.5, intonation: 1.8))
    #expect(calm.audioData != expressive.audioData)
    #expect(other.audioData != expressive.audioData)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
    try expressive.audioData.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let file = try AVAudioFile(forReading: url)
    let actual = Double(file.length) / file.processingFormat.sampleRate
    #expect(abs(expressive.duration - actual) < 0.1)
    #expect(expressive.moraTimings.allSatisfy { $0.startTime + $0.duration <= actual + 0.1 })
}
