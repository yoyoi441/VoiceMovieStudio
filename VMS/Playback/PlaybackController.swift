import AVFoundation
import Observation
import VMSCore

/// Drives preview playback. When the project has audio clips, an `AVPlayer` built from
/// the same `AudioCompositionBuilder` mix `VideoExporter` uses is the clock — its
/// periodic time observer is what advances the on-screen playhead, so what you hear and
/// what you see never drift apart. Text/character-only projects have nothing for
/// `AVPlayer` to play through, so a plain repeating timer stands in for the clock instead.
@Observable
@MainActor
final class PlaybackController {
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var fallbackTask: Task<Void, Never>?
    private var playbackGeneration = UUID()

    func play(
        timeline: Timeline,
        assetsDirectory: URL,
        startTime: TimeInterval,
        frameRate: Double = 30,
        onTick: @escaping @MainActor (TimeInterval) -> Void,
        onFinished: @escaping @MainActor () -> Void
    ) async {
        stop()
        let generation = playbackGeneration
        let previewFPS = frameRate.isFinite ? min(60, max(1, frameRate)) : 30

        let composition = AVMutableComposition()
        let audio = try? await AudioCompositionBuilder.build(into: composition, timeline: timeline, assetsDirectory: assetsDirectory)
        guard generation == playbackGeneration, !Task.isCancelled else { return }

        guard let audio, audio.hasAudio else {
            startFallbackTimer(duration: timeline.duration, startTime: startTime, frameRate: previewFPS, onTick: onTick, onFinished: onFinished)
            return
        }

        // Storyboard cards may continue after the last generated speech.
        let timelineEnd = CMTime(seconds: timeline.duration, preferredTimescale: 600)
        if composition.duration < timelineEnd {
            composition.insertEmptyTimeRange(CMTimeRange(start: composition.duration, duration: timelineEnd - composition.duration))
        }
        let item = AVPlayerItem(asset: composition)
        item.audioMix = audio.audioMix
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        await newPlayer.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        guard generation == playbackGeneration, !Task.isCancelled else { return }

        // Both callbacks below fire on the main queue/thread (guaranteed by `queue: .main`),
        // so `assumeIsolated` is a safe, synchronous hop into these @MainActor closures —
        // the block types AVFoundation/Foundation expect here are plain, non-isolated
        // `@Sendable` closures, which can't call a @MainActor function without one.
        let interval = CMTime(seconds: 1.0 / previewFPS, preferredTimescale: 60000)
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            MainActor.assumeIsolated { onTick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onFinished() }
        }

        newPlayer.play()
    }

    func pause() {
        playbackGeneration = UUID()
        player?.pause()
        fallbackTask?.cancel()
        fallbackTask = nil
    }

    func stop() {
        pause()
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
        timeObserverToken = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player = nil
    }

    private func startFallbackTimer(
        duration: TimeInterval,
        startTime: TimeInterval,
        frameRate: Double,
        onTick: @escaping @MainActor (TimeInterval) -> Void,
        onFinished: @escaping @MainActor () -> Void
    ) {
        fallbackTask = Task { @MainActor in
            let clock = ContinuousClock()
            let started = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1 / frameRate))
                guard !Task.isCancelled else { return }
                let elapsed = started.duration(to: clock.now).components
                let current = startTime + Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                if current >= duration {
                    onFinished()
                    return
                }
                onTick(current)
            }
        }
    }
}
