import AppKit
import AVFoundation
import Observation

/// Extracts movie frames on demand and keeps a bounded frame cache. The synchronous
/// `image(...)` accessor is consumed by `CompositeFrameView`; callers first await
/// `prepare(...)`, both for preview playback and frame-by-frame export.
@Observable
@MainActor
final class VideoFrameProvider {
    private(set) var assetsDirectory: URL
    private var cache: [FrameKey: NSImage] = [:]
    private var order: [FrameKey] = []
    private let maximumFrames = 180

    private struct FrameKey: Hashable {
        var fileName: String
        var frame: Int
    }

    init(assetsDirectory: URL) {
        self.assetsDirectory = assetsDirectory
    }

    func updateAssetsDirectory(_ url: URL) {
        guard url != assetsDirectory else { return }
        assetsDirectory = url
        cache.removeAll()
        order.removeAll()
    }

    func prepare(fileName: String, sourceTime: TimeInterval, frameRate: Double) async {
        let key = key(fileName: fileName, sourceTime: sourceTime, frameRate: frameRate)
        guard cache[key] == nil else { return }

        let url = assetsDirectory.appendingPathComponent(fileName)
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1 / max(frameRate, 1), preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore

        guard let result = try? await generator.image(at: CMTime(seconds: max(0, sourceTime), preferredTimescale: 600)) else {
            return
        }
        cache[key] = NSImage(cgImage: result.image, size: .zero)
        order.append(key)
        if order.count > maximumFrames {
            let overflow = order.count - maximumFrames
            let removed = Array(order.prefix(overflow))
            order.removeFirst(overflow)
            for key in removed { cache.removeValue(forKey: key) }
        }
    }

    func image(fileName: String, sourceTime: TimeInterval, frameRate: Double) -> NSImage? {
        cache[key(fileName: fileName, sourceTime: sourceTime, frameRate: frameRate)]
    }

    private func key(fileName: String, sourceTime: TimeInterval, frameRate: Double) -> FrameKey {
        FrameKey(fileName: fileName, frame: Int((max(0, sourceTime) * max(frameRate, 1)).rounded()))
    }
}
