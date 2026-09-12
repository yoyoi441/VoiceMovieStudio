import AppKit
import AVFoundation
import VMSCore

struct AnalyzedVideoMaterial: Sendable {
    struct Frame: Sendable {
        var time: TimeInterval
        var jpegData: Data
    }
    var asset: MediaAsset
    var frames: [Frame]
}

enum VideoMaterialAnalyzer {
    static func analyze(_ asset: MediaAsset, assetsDirectory: URL) async -> AnalyzedVideoMaterial {
        let url = assetsDirectory.appendingPathComponent(asset.fileName)
        let movie = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: movie)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 768, height: 768)
        let duration = max(0.1, asset.duration)
        let sampleTimes = [duration * 0.1, duration * 0.5, duration * 0.9]
        var frames: [AnalyzedVideoMaterial.Frame] = []
        for seconds in sampleTimes {
            guard let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) else { continue }
            let bitmap = NSBitmapImageRep(cgImage: result.image)
            guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else { continue }
            frames.append(.init(time: seconds, jpegData: data))
        }
        return AnalyzedVideoMaterial(asset: asset, frames: frames)
    }
}
