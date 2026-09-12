import AppKit
import AVFoundation
import UniformTypeIdentifiers
import VMSCore

enum VideoAssetImporter {
    @MainActor
    static func promptAndImport(into store: ProjectStore, addToTimeline: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        let insertionTime = store.playhead
        Task { @MainActor in
            do {
                var cursor = insertionTime
                for sourceURL in panel.urls {
                    let asset = try await importAsset(from: sourceURL, into: store.assetsDirectory)
                    store.registerMediaAsset(asset)
                    if addToTimeline {
                        store.addClip(
                            content: .video(VideoClipData(assetID: asset.id, fileName: asset.fileName)),
                            duration: max(0.1, asset.duration),
                            at: cursor
                        )
                        cursor += asset.duration
                    }
                }
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }

    static func importAsset(from sourceURL: URL, into assetsDirectory: URL) async throws -> MediaAsset {
        let fileName = try AssetImporter.importFile(from: sourceURL, into: assetsDirectory, prefix: "video")
        let destinationURL = assetsDirectory.appendingPathComponent(fileName)
        let movie = AVURLAsset(url: destinationURL)
        let duration = try await movie.load(.duration).seconds
        let thumbnailName = try await makeThumbnail(movie: movie, baseName: fileName, in: assetsDirectory)
        return MediaAsset(
            kind: .video,
            fileName: fileName,
            originalName: sourceURL.lastPathComponent,
            duration: max(0, duration),
            thumbnailFileName: thumbnailName
        )
    }

    private static func makeThumbnail(movie: AVAsset, baseName: String, in directory: URL) async throws -> String? {
        let generator = AVAssetImageGenerator(asset: movie)
        generator.appliesPreferredTrackTransform = true
        guard let result = try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: result.image)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else { return nil }
        let name = "thumb_\(UUID().uuidString).jpg"
        try jpeg.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }
}
