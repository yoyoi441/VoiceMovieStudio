import Foundation

/// Bundles the three clips that come out of a single TTS synthesis: the audio itself,
/// an auto-generated subtitle, and (if a character was supplied) a lip-synced character
/// clip — providing a "type text, get voice + subtitle + talking character" flow.
public struct TTSImportResult: Sendable {
    public var audioClip: Clip
    public var textClip: Clip
    public var characterClip: Clip?
}

public enum TTSImportError: Error, LocalizedError {
    case failedToWriteAudio(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .failedToWriteAudio(let underlying):
            return "音声ファイルの書き出しに失敗しました: \(underlying.localizedDescription)"
        }
    }
}

public enum TTSImportService {
    /// Synthesizes `text`, writes the resulting WAV into `assetsDirectory`, and builds
    /// ready-to-insert clips starting at `startTime`. Does not mutate the project —
    /// the caller is responsible for appending the returned clips to tracks.
    public static func importSpeech(
        text: String,
        speakerID: Int,
        characterID: UUID?,
        startTime: TimeInterval,
        engine: VoiceEngine,
        assetsDirectory: URL,
        settings: VoiceSettings = VoiceSettings(),
        mouthSpeed: Double = 1.0
    ) async throws -> TTSImportResult {
        let speech = try await engine.synthesize(text: text, speakerID: speakerID, settings: settings)

        let fileName = "voice_\(UUID().uuidString).wav"
        let fileURL = assetsDirectory.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
            try speech.audioData.write(to: fileURL)
        } catch {
            throw TTSImportError.failedToWriteAudio(underlying: error)
        }

        var audioClip = Clip(
            startTime: startTime,
            duration: speech.duration,
            content: .audio(
                AudioClipData(
                    fileName: fileName,
                    sourceText: text,
                    moraTimings: speech.moraTimings,
                    speakerID: speakerID,
                    voiceSettings: settings
                )
            )
        )

        let textClip = Clip(
            startTime: startTime,
            duration: speech.duration,
            content: .text(TextClipData(text: text))
        )

        if case .audio(var data) = audioClip.content {
            data.linkedSubtitleClipID = textClip.id
            audioClip.content = .audio(data)
        }

        let characterClip = characterID.map { id in
            Clip(
                startTime: startTime,
                duration: speech.duration,
                content: .character(
                    CharacterClipData(
                        characterID: id,
                        linkedAudioClipID: audioClip.id,
                        mouthKeyframes: LipSyncGenerator.keyframes(from: speech.moraTimings, speed: mouthSpeed)
                    )
                )
            )
        }

        return TTSImportResult(audioClip: audioClip, textClip: textClip, characterClip: characterClip)
    }
}
