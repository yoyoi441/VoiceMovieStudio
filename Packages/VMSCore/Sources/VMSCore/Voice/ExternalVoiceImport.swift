import AVFoundation
import Foundation

public enum ExternalVoiceError: Error, LocalizedError {
    case invalidAudio
    public var errorDescription: String? {
        "WAV音声を読み込めません。30分・512MB以内の有効な音声ファイルを選択してください。"
    }
}

/// File-based integration: neither claims phoneme recognition nor uses another synthesizer.
public enum ExternalVoiceImport {
    public struct Analysis: Sendable {
        public var duration: Double
        public var mouthKeyframes: [MouthKeyframe]
    }

    public static func analyze(url: URL, mouthSpeed: Double = 1) throws -> Analysis {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard url.pathExtension.lowercased() == "wav", size > 0, size <= 512 * 1024 * 1024 else {
            throw ExternalVoiceError.invalidAudio
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 12) ?? Data()
        guard header.count == 12, header.prefix(4) == Data("RIFF".utf8),
              header.suffix(4) == Data("WAVE".utf8) else { throw ExternalVoiceError.invalidAudio }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate
        guard duration.isFinite, duration > 0, duration <= 1800,
              format.channelCount > 0, format.sampleRate > 0 else { throw ExternalVoiceError.invalidAudio }
        let capacity = AVAudioFrameCount(max(1, format.sampleRate * 0.04))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw ExternalVoiceError.invalidAudio
        }
        let speed = mouthSpeed.isFinite ? min(3, max(0.5, mouthSpeed)) : 1
        var keys = [MouthKeyframe(time: 0, shape: .closed)]
        while file.framePosition < file.length {
            try Task.checkCancellation()
            let time = Double(file.framePosition) / format.sampleRate
            try file.read(into: buffer, frameCount: capacity)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
                throw ExternalVoiceError.invalidAudio
            }
            var energy = 0.0
            for channel in 0..<Int(format.channelCount) {
                for sample in 0..<Int(buffer.frameLength) {
                    let value = Double(channels[channel][sample])
                    if value.isFinite { energy += value * value }
                }
            }
            let rms = sqrt(energy / Double(buffer.frameLength) / Double(format.channelCount))
            let shape: MouthShape
            if rms < 0.008 { shape = .closed }
            else { shape = Int(time * 10 * speed) % 2 == 0 ? .open : .small }
            if keys.last?.shape != shape { keys.append(MouthKeyframe(time: time, shape: shape)) }
        }
        keys.append(MouthKeyframe(time: duration, shape: .closed))
        return Analysis(duration: duration, mouthKeyframes: keys)
    }

    public static func importFile(url: URL, text: String, provider: String,
                                  characterID: UUID?, startTime: Double, assetsDirectory: URL,
                                  mouthSpeed: Double = 1) async throws -> TTSImportResult {
        let analysis = try analyze(url: url, mouthSpeed: mouthSpeed)
        let engine = ImportedEngine(speech: SynthesizedSpeech(
            audioData: try Data(contentsOf: url), moraTimings: [], duration: analysis.duration))
        var result = try await TTSImportService.importSpeech(
            text: text, speakerID: 0, characterID: characterID, startTime: startTime,
            engine: engine, assetsDirectory: assetsDirectory)
        if case .audio(var audio) = result.audioClip.content {
            audio.speakerID = nil
            audio.voiceProvider = provider
            result.audioClip.content = .audio(audio)
        }
        if var clip = result.characterClip, case .character(var character) = clip.content {
            character.mouthKeyframes = analysis.mouthKeyframes
            clip.content = .character(character)
            result.characterClip = clip
        }
        return result
    }

    private struct ImportedEngine: VoiceEngine {
        let speech: SynthesizedSpeech
        func availableSpeakers() async throws -> [VoiceSpeaker] { [] }
        func synthesize(text: String, speakerID: Int, settings: VoiceSettings) async throws -> SynthesizedSpeech { speech }
    }
}
