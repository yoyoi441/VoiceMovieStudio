import AVFoundation
import CoreGraphics
import Observation
import SwiftUI
import VMSCore

/// Renders the project to an .mp4 file in two passes:
///  1. Draw every output frame with `CompositeFrameView` (the same view the live preview
///     uses) via `ImageRenderer`, and write them to a silent .mov with `AVAssetWriter`.
///  2. Build an `AVMutableComposition` that lays that rendered video track alongside all
///     of the project's audio clips (placed at their own `startTime`s), and export it to
///     the final .mp4 with `AVAssetExportSession`.
///
/// Two passes rather than feeding video+audio into one `AVAssetWriter` by hand because it
/// lets AVFoundation's own composition/export machinery handle audio mixing and muxing,
/// which is much less error-prone than hand-synchronizing two writer inputs.
@Observable
@MainActor
final class VideoExporter {
    enum VideoExportError: Error, LocalizedError {
        case emptyTimeline
        case frameRenderingFailed
        case missingVideoTrack
        case exportSessionCreationFailed
        case exportFailed(underlying: Error?)

        var errorDescription: String? {
            switch self {
            case .emptyTimeline:
                return "タイムラインにクリップがありません。"
            case .frameRenderingFailed:
                return "フレームの描画に失敗しました。"
            case .missingVideoTrack:
                return "書き出した映像トラックの読み込みに失敗しました。"
            case .exportSessionCreationFailed:
                return "書き出しセッションの作成に失敗しました。"
            case .exportFailed(let underlying):
                return "書き出しに失敗しました: \(underlying?.localizedDescription ?? "不明なエラー")"
            }
        }
    }

    private(set) var progress: Double = 0
    private(set) var isExporting = false

    func export(
        project: Project,
        timeline: Timeline,
        assetsDirectory: URL,
        imageProvider: CharacterImageProvider,
        videoFrameProvider: VideoFrameProvider,
        to outputURL: URL
    ) async throws {
        guard timeline.duration > 0 else { throw VideoExportError.emptyTimeline }

        isExporting = true
        progress = 0
        defer { isExporting = false }

        let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        try await renderVideoOnly(project: project, timeline: timeline, imageProvider: imageProvider, videoFrameProvider: videoFrameProvider, to: tempVideoURL) { [weak self] value in
            self?.progress = value * 0.8
        }
        let (composition, audioMix) = try await buildComposition(timeline: timeline, assetsDirectory: assetsDirectory, videoOnlyURL: tempVideoURL)
        try await exportComposition(composition, audioMix: audioMix, to: outputURL) { [weak self] value in
            self?.progress = 0.8 + value * 0.2
        }
        progress = 1
    }

    // MARK: - Pass 1: render frames

    private func renderVideoOnly(
        project: Project,
        timeline: Timeline,
        imageProvider: CharacterImageProvider,
        videoFrameProvider: VideoFrameProvider,
        to url: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        let width = Int(project.resolution.width)
        let height = Int(project.resolution.height)
        let fps = project.frameRate
        let duration = timeline.duration
        let frameCount = max(1, Int((duration * fps).rounded(.up)))

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: pixelBufferAttributes)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            let time = Double(frameIndex) / fps
            for clip in timeline.tracks.flatMap(\.clips) where clip.contains(time: time) {
                guard case .video(let data) = clip.content else { continue }
                await videoFrameProvider.prepare(
                    fileName: data.fileName,
                    sourceTime: data.sourceStartTime + max(0, time - clip.startTime),
                    frameRate: fps
                )
            }
            let frameView = CompositeFrameView(
                project: project,
                timeline: timeline,
                time: time,
                imageProvider: imageProvider,
                videoFrameProvider: videoFrameProvider
            )
            let renderer = ImageRenderer(content: frameView)
            renderer.scale = 1
            guard let cgImage = renderer.cgImage else {
                writer.cancelWriting()
                throw VideoExportError.frameRenderingFailed
            }
            guard let pool = adaptor.pixelBufferPool else {
                writer.cancelWriting()
                throw VideoExportError.frameRenderingFailed
            }
            var pixelBufferOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBufferOut)
            guard let pixelBuffer = pixelBufferOut else {
                writer.cancelWriting()
                throw VideoExportError.frameRenderingFailed
            }
            Self.draw(cgImage, into: pixelBuffer, width: width, height: height)

            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps))
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)

            progress(Double(frameIndex + 1) / Double(frameCount))
            await Task.yield()
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
    }

    private static func draw(_ cgImage: CGImage, into pixelBuffer: CVPixelBuffer, width: Int, height: Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    // MARK: - Pass 2: composition + export

    private func buildComposition(
        timeline: Timeline,
        assetsDirectory: URL,
        videoOnlyURL: URL
    ) async throws -> (AVMutableComposition, AVAudioMix?) {
        let composition = AVMutableComposition()

        let videoAsset = AVURLAsset(url: videoOnlyURL)
        guard let videoAssetTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw VideoExportError.missingVideoTrack
        }
        let videoDuration = try await videoAsset.load(.duration)
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try compositionVideoTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoAssetTrack, at: .zero)

        let audio = try await AudioCompositionBuilder.build(into: composition, timeline: timeline, assetsDirectory: assetsDirectory)
        return (composition, audio.audioMix)
    }

    private func exportComposition(
        _ composition: AVMutableComposition,
        audioMix: AVAudioMix?,
        to outputURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoExportError.exportSessionCreationFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.audioMix = audioMix

        let progressPoller = Task { [weak session] in
            while let session, !Task.isCancelled {
                progress(Double(session.progress))
                if session.status == .completed || session.status == .failed || session.status == .cancelled {
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { progressPoller.cancel() }

        await withCheckedContinuation { continuation in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        switch session.status {
        case .completed:
            return
        case .failed:
            throw VideoExportError.exportFailed(underlying: session.error)
        case .cancelled:
            throw VideoExportError.exportFailed(underlying: session.error)
        default:
            throw VideoExportError.exportFailed(underlying: session.error)
        }
    }
}
