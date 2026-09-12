import AVFoundation
import Foundation
import Testing
@testable import VMSCore

@Test func externalVoiceImportPreservesProviderAndAssets() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let wav = root.appendingPathComponent("test.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    do {
        let file = try AVAudioFile(forWriting: wav, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000)!
        buffer.frameLength = 24000
        for i in 0..<24000 {
            buffer.floatChannelData![0][i] = i < 12000 ? 0 : Float(sin(Double(i) * 0.1) * 0.4)
        }
        try file.write(from: buffer)
    }
    let characterID = UUID()
    let assets = root.appendingPathComponent("Assets")
    let result = try await ExternalVoiceImport.importFile(
        url: wav, text: "テスト", provider: "A.I.VOICE2", characterID: characterID,
        startTime: 3, assetsDirectory: assets, mouthSpeed: 2)
    #expect(abs(result.audioClip.duration - 1) < 0.001)
    #expect(result.audioClip.startTime == 3)
    guard case .audio(let audio) = result.audioClip.content,
          let clip = result.characterClip, case .character(let character) = clip.content else {
        Issue.record("Missing generated clips"); return
    }
    #expect(audio.speakerID == nil)
    #expect(audio.voiceProvider == "A.I.VOICE2")
    #expect(try Data(contentsOf: assets.appendingPathComponent(audio.fileName)) == Data(contentsOf: wav))
    #expect(character.linkedAudioClipID == result.audioClip.id)
    #expect(character.mouthShape(at: 0.25) == .closed)
    #expect(character.mouthKeyframes.contains { $0.time >= 0.5 && $0.shape == .open })
    #expect(character.mouthKeyframes.last?.shape == .closed)
    let restored = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(result.audioClip))
    #expect(restored == result.audioClip)
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(audio)) as! [String: Any]
    legacy.removeValue(forKey: "voiceProvider")
    let old = try JSONDecoder().decode(AudioClipData.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(old.voiceProvider == nil)
    var project = Project.demo()
    project.scenes[0].timeline.tracks[0].clips = [result.audioClip, result.textClip, clip]
    let package = root.appendingPathComponent("Voice.VMS")
    try ProjectPackage.write(project: project, assetsDirectory: assets, to: package)
    let (reopened, savedAssets) = try ProjectPackage.read(from: package)
    #expect(reopened.scenes[0].timeline.tracks[0].clips == [result.audioClip, result.textClip, clip])
    #expect(try Data(contentsOf: savedAssets.appendingPathComponent(audio.fileName)) == Data(contentsOf: wav))
    let normal = try ExternalVoiceImport.analyze(url: wav, mouthSpeed: 0.5)
    let fast = try ExternalVoiceImport.analyze(url: wav, mouthSpeed: 2)
    #expect(fast.mouthKeyframes.count > normal.mouthKeyframes.count)
    let withoutCharacter = try await ExternalVoiceImport.importFile(
        url: wav, text: "字幕のみ", provider: "A.I.VOICE", characterID: nil,
        startTime: 0, assetsDirectory: assets)
    #expect(withoutCharacter.characterClip == nil)
}

@Test func externalVoiceRejectsInvalidFiles() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
    try Data("not audio".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: (any Error).self) { try ExternalVoiceImport.analyze(url: url) }
}
