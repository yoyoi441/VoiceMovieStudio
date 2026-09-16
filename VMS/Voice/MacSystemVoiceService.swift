import AVFoundation
import Foundation
import VMSCore

struct MacSystemVoiceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let isEnhanced: Bool

    var displayName: String {
        isEnhanced ? "\(name)（高品質）" : name
    }
}

@MainActor
enum MacSystemVoiceCatalog {
    static var japaneseVoices: [MacSystemVoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("ja") }
            .map {
                MacSystemVoiceOption(
                    id: $0.identifier,
                    name: $0.name,
                    language: $0.language,
                    isEnhanced: $0.quality == .enhanced || $0.quality == .premium
                )
            }
            .sorted {
                if $0.isEnhanced != $1.isEnhanced { return $0.isEnhanced && !$1.isEnhanced }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    static func voice(identifier: String) -> MacSystemVoiceOption? {
        japaneseVoices.first { $0.id == identifier }
    }

    static func voice(for profile: MacSystemVoiceSupport.BuiltInProfile) -> MacSystemVoiceOption? {
        let voices = japaneseVoices
        for preferredName in profile.preferredVoiceNames {
            if let voice = voices.first(where: { $0.name == preferredName }) { return voice }
        }
        return voices.first
    }
}

enum MacSystemVoiceError: Error, LocalizedError {
    case emptyText
    case voiceUnavailable
    case invalidAudioBuffer
    case failedToWrite(Error)
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .emptyText:
            "セリフを入力してください。"
        case .voiceUnavailable:
            "指定したMacの日本語音声が利用できません。音声を選び直してください。"
        case .invalidAudioBuffer:
            "Macの音声合成から正しい音声データを受け取れませんでした。"
        case .failedToWrite(let error):
            "Mac音声の書き出しに失敗しました：\(error.localizedDescription)"
        case .emptyAudio:
            "Macの音声合成結果が空でした。別の音声を選ぶか、セリフを確認してください。"
        }
    }
}

@MainActor
private final class MacSystemVoiceWriter {
    private let synthesizer = AVSpeechSynthesizer()

    func wavData(text: String, voiceIdentifier: String, settings: VoiceSettings) async throws -> Data {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { throw MacSystemVoiceError.emptyText }
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier),
              voice.language.lowercased().hasPrefix("ja") else {
            throw MacSystemVoiceError.voiceUnavailable
        }

        let safe = settings.validatedForMacSystemVoice()
        let utterance = AVSpeechUtterance(string: normalizedText)
        utterance.voice = voice
        utterance.volume = Float(safe.volume)
        utterance.pitchMultiplier = Float(safe.pitch)
        utterance.rate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate,
                AVSpeechUtteranceDefaultSpeechRate * Float(safe.speed))
        )
        utterance.preUtteranceDelay = safe.preSilence
        utterance.postUtteranceDelay = safe.postSilence

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-movie-studio-mac-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let state = MacSystemVoiceWriteState(url: outputURL, continuation: continuation)
            synthesizer.write(utterance) { buffer in
                state.receive(buffer)
            }
        }

        let data = try Data(contentsOf: outputURL)
        guard data.count >= 12,
              data.prefix(4) == Data("RIFF".utf8),
              data.subdata(in: 8..<12) == Data("WAVE".utf8) else {
            throw MacSystemVoiceError.emptyAudio
        }
        return data
    }
}

private final class MacSystemVoiceWriteState: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var continuation: CheckedContinuation<Void, Error>?
    private var file: AVAudioFile?
    private var wroteFrames = false

    init(url: URL, continuation: CheckedContinuation<Void, Error>) {
        self.url = url
        self.continuation = continuation
    }

    func receive(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard continuation != nil else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer else {
            finish(.failure(MacSystemVoiceError.invalidAudioBuffer))
            return
        }
        if pcm.frameLength == 0 {
            finish(wroteFrames ? .success(()) : .failure(MacSystemVoiceError.emptyAudio))
            return
        }
        do {
            if file == nil {
                file = try AVAudioFile(
                    forWriting: url,
                    settings: pcm.format.settings,
                    commonFormat: pcm.format.commonFormat,
                    interleaved: pcm.format.isInterleaved
                )
            }
            try file?.write(from: pcm)
            wroteFrames = true
        } catch {
            finish(.failure(MacSystemVoiceError.failedToWrite(error)))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        file = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}

@MainActor
enum MacSystemVoiceSynthesisService {
    struct SpeechResult: Sendable {
        var speech: SynthesizedSpeech
        var mouthKeyframes: [MouthKeyframe]
    }

    static func speech(
        text: String,
        voiceIdentifier: String,
        settings: VoiceSettings,
        mouthSpeed: Double
    ) async throws -> SpeechResult {
        let safe = settings.validatedForMacSystemVoice()
        let data = try await MacSystemVoiceWriter().wavData(
            text: text, voiceIdentifier: voiceIdentifier, settings: safe
        )
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-movie-studio-mac-analysis-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)
        let analysis = try ExternalVoiceImport.analyze(url: temporaryURL, mouthSpeed: mouthSpeed)
        return SpeechResult(
            speech: SynthesizedSpeech(audioData: data, moraTimings: [], duration: analysis.duration),
            mouthKeyframes: analysis.mouthKeyframes
        )
    }

    static func importSpeech(
        text: String,
        voiceIdentifier: String,
        settings: VoiceSettings,
        character: Character?,
        startTime: Double,
        assetsDirectory: URL
    ) async throws -> TTSImportResult {
        let safe = settings.validatedForMacSystemVoice()
        let data = try await MacSystemVoiceWriter().wavData(
            text: text, voiceIdentifier: voiceIdentifier, settings: safe
        )
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-movie-studio-mac-import-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)
        var result = try await ExternalVoiceImport.importFile(
            url: temporaryURL,
            text: text,
            provider: MacSystemVoiceSupport.providerID,
            characterID: character?.id,
            startTime: startTime,
            assetsDirectory: assetsDirectory,
            mouthSpeed: character?.defaultMouthSpeed ?? 1
        )
        if case .audio(var audio) = result.audioClip.content {
            audio.voiceLibrary = voiceIdentifier
            audio.voiceStyle = MacSystemVoiceCatalog.voice(identifier: voiceIdentifier)?.name ?? "Mac音声"
            audio.voiceSettings = safe
            audio.licenseNotes = character?.usageTerms ?? ""
            result.audioClip.content = .audio(audio)
        }
        if var clip = result.characterClip {
            clip.effects.flipHorizontal = character?.defaultFlipHorizontal ?? false
            result.characterClip = clip
        }
        return result
    }
}
