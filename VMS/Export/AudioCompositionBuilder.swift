import AVFoundation
import VMSCore

/// Lays every audio clip in the project onto one composition audio track at its own
/// `startTime`, with an `AVAudioMix` for fade in/out volume ramps. Shared by
/// `VideoExporter` (muxed alongside the rendered video track) and `PlaybackController`
/// (played directly for live preview) so both hear exactly the same mix.
enum AudioCompositionBuilder {
    struct Result {
        var track: AVMutableCompositionTrack?
        var audioMix: AVAudioMix?
        var hasAudio: Bool
    }

    static func build(into composition: AVMutableComposition, timeline: Timeline, assetsDirectory: URL) async throws -> Result {
        let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var audioClips: [Clip] = []
        for track in timeline.tracks {
            for clip in track.clips {
                switch clip.content {
                case .audio:
                    audioClips.append(clip)
                case .video(let data) where !data.isMuted:
                    audioClips.append(clip)
                default:
                    break
                }
            }
        }

        for clip in audioClips {
            let fileName: String
            let sourceStart: TimeInterval
            switch clip.content {
            case .audio(let data):
                fileName = data.fileName
                sourceStart = 0
            case .video(let data):
                fileName = data.fileName
                sourceStart = data.sourceStartTime
            default:
                continue
            }
            let fileURL = assetsDirectory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let audioAsset = AVURLAsset(url: fileURL)
            guard let audioAssetTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else { continue }
            let assetDuration = try await audioAsset.load(.duration)
            let clipDuration = CMTime(seconds: clip.duration, preferredTimescale: 600)
            let sourceStartTime = CMTime(seconds: sourceStart, preferredTimescale: 600)
            let availableDuration = max(.zero, assetDuration - sourceStartTime)
            let insertDuration = min(availableDuration, clipDuration)
            let startTime = CMTime(seconds: clip.startTime, preferredTimescale: 600)
            try compositionAudioTrack?.insertTimeRange(
                CMTimeRange(start: sourceStartTime, duration: insertDuration), of: audioAssetTrack, at: startTime
            )
        }

        let audioMix = compositionAudioTrack.flatMap { buildAudioMix(for: $0, audioClips: audioClips) }
        return Result(track: compositionAudioTrack, audioMix: audioMix, hasAudio: !audioClips.isEmpty)
    }

    /// Volume ramps for each audio clip's fade in/out (`ClipEffects.fadeInDuration` /
    /// `fadeOutDuration` mean a volume fade for audio, an opacity fade for visuals).
    /// Regions with no ramp default to full volume, so only fading clips need an entry.
    private static func buildAudioMix(for compositionTrack: AVCompositionTrack, audioClips: [Clip]) -> AVAudioMix? {
        let params = AVMutableAudioMixInputParameters(track: compositionTrack)
        var hasRamp = false

        for clip in audioClips {
            let clipStart = clip.startTime
            let clipEnd = clip.startTime + clip.duration
            let baseVolume: Float
            if case .video(let data) = clip.content {
                baseVolume = Float(min(max(data.volume, 0), 2))
                params.setVolume(baseVolume, at: CMTime(seconds: clipStart, preferredTimescale: 600))
                hasRamp = true
            } else {
                baseVolume = 1
            }
            if clip.effects.fadeInDuration > 0 {
                let end = min(clipStart + clip.effects.fadeInDuration, clipEnd)
                let range = CMTimeRange(
                    start: CMTime(seconds: clipStart, preferredTimescale: 600),
                    end: CMTime(seconds: end, preferredTimescale: 600)
                )
                params.setVolumeRamp(fromStartVolume: 0, toEndVolume: baseVolume, timeRange: range)
                hasRamp = true
            }
            if clip.effects.fadeOutDuration > 0 {
                let start = max(clipEnd - clip.effects.fadeOutDuration, clipStart)
                let range = CMTimeRange(
                    start: CMTime(seconds: start, preferredTimescale: 600),
                    end: CMTime(seconds: clipEnd, preferredTimescale: 600)
                )
                params.setVolumeRamp(fromStartVolume: baseVolume, toEndVolume: 0, timeRange: range)
                hasRamp = true
            }
        }

        guard hasRamp else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        return mix
    }
}
