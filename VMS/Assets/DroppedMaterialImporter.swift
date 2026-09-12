import AppKit
import AVFoundation
import Foundation
import VMSCore

@MainActor
enum DroppedMaterialImporter {
    static func importURLs(_ urls: [URL], into store: ProjectStore) async {
        var cursor = store.playhead
        var messages: [String] = []
        for classification in urls.map(MaterialFileClassifier.classify) {
            do {
                switch classification.kind {
                case .characterProfile:
                    let report = try CharacterProfileImporter.importURLs([classification.url])
                    store.beginUndoableChange()
                    store.project.characters.append(contentsOf: report.characters)
                    messages.append("プロファイル \(report.characters.count)件")
                case .characterArtwork:
                    let count = try importCharacterArtwork(classification.url, store: store)
                    messages.append("キャラクター \(count)件")
                case .characterArchive:
                    let extractedDirectory = try await extractArchive(classification.url)
                    defer { try? FileManager.default.removeItem(at: extractedDirectory) }
                    let extracted = MaterialFileClassifier.classify(extractedDirectory)
                    switch extracted.kind {
                    case .characterProfile:
                        let report = try CharacterProfileImporter.importURLs([extractedDirectory])
                        store.beginUndoableChange()
                        store.project.characters.append(contentsOf: report.characters)
                        messages.append("ZIPからプロファイル \(report.characters.count)件")
                    case .characterArtwork:
                        let count = try importCharacterArtwork(extractedDirectory, store: store)
                        messages.append("ZIPからキャラクター \(count)件")
                    default:
                        messages.append("未対応: \(classification.url.lastPathComponent)（ZIP内に対応する立ち絵素材がありません）")
                    }
                case .video:
                    var asset = try await VideoAssetImporter.importAsset(from: classification.url, into: store.assetsDirectory)
                    asset.credit = CreditMetadataDetector.detect(for: classification.url)
                    store.registerMediaAsset(asset)
                    store.addClip(content: .video(VideoClipData(assetID: asset.id, fileName: asset.fileName)), duration: max(0.1, asset.duration), at: cursor)
                    cursor += max(0.1, asset.duration)
                    messages.append("動画 1件")
                case .audio:
                    let fileName = try AssetImporter.importFile(from: classification.url, into: store.assetsDirectory, prefix: "audio")
                    let duration = (try? await AVURLAsset(url: store.assetsDirectory.appendingPathComponent(fileName)).load(.duration).seconds) ?? 3
                    store.registerMediaAsset(MediaAsset(kind: .audio, fileName: fileName, originalName: classification.url.lastPathComponent, duration: duration, credit: CreditMetadataDetector.detect(for: classification.url)))
                    store.addClip(content: .audio(AudioClipData(fileName: fileName)), duration: max(0.1, duration), at: cursor)
                    cursor += max(0.1, duration)
                    messages.append("音声 1件")
                case .image:
                    let fileName = try AssetImporter.importFile(from: classification.url, into: store.assetsDirectory, prefix: "image")
                    store.registerMediaAsset(MediaAsset(kind: .image, fileName: fileName, originalName: classification.url.lastPathComponent, credit: CreditMetadataDetector.detect(for: classification.url)))
                    store.addClip(content: .image(ImageClipData(fileName: fileName)), duration: 3, at: cursor)
                    cursor += 3
                    messages.append("画像 1件")
                case .unsupported:
                    messages.append("未対応: \(classification.url.lastPathComponent)（\(classification.reason)）")
                }
            } catch {
                messages.append("失敗: \(classification.url.lastPathComponent)（\(error.localizedDescription)）")
            }
        }
        store.materialImportMessage = messages.joined(separator: "、")
    }

    private static func importCharacterArtwork(_ source: URL, store: ProjectStore) throws -> Int {
        let candidates = source.hasDirectoryPath ? MaterialFileClassifier.childFiles(source) : [source]
        let psdFiles = candidates.filter { $0.pathExtension.lowercased() == "psd" }
        if !psdFiles.isEmpty {
            store.beginUndoableChange()
            for psd in psdFiles.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                let previewFileName = try importPSDPreview(from: psd, into: store.assetsDirectory)
                let originalFileName = try AssetImporter.importFile(from: psd, into: store.assetsDirectory, prefix: "character_source")
                let layers = layerNodes(try PSDLayerExtractor.extract(from: psd, into: store.assetsDirectory))
                store.project.characters.append(Character(
                    name: psd.deletingPathExtension().lastPathComponent,
                    tachieKind: .psd,
                    baseImageFileName: previewFileName,
                    layerTree: layers,
                    importedSource: originalFileName,
                    credit: CreditMetadataDetector.detect(for: psd)
                ))
            }
            return psdFiles.count
        }

        guard let base = candidates.first(where: { ["png", "webp", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }) else { return 0 }
        let fileName = try AssetImporter.importFile(from: base, into: store.assetsDirectory, prefix: "character")
        var mouth: [MouthShape: String] = [:]
        for file in candidates where ["png", "jpg", "jpeg", "webp"].contains(file.pathExtension.lowercased()) {
            let lower = file.deletingPathExtension().lastPathComponent.lowercased()
            let shape: MouthShape? = lower.contains("口閉") || lower.contains("mouth_close") ? .closed : lower.contains("口小") || lower.contains("mouth_small") ? .small : lower.contains("口開") || lower.contains("mouth_open") ? .open : nil
            if let shape { mouth[shape] = try AssetImporter.importFile(from: file, into: store.assetsDirectory, prefix: "mouth") }
        }
        store.beginUndoableChange()
        store.project.characters.append(Character(name: source.deletingPathExtension().lastPathComponent, tachieKind: .animated, baseImageFileName: fileName, mouthImageFileNames: mouth, credit: CreditMetadataDetector.detect(for: source)))
        return 1
    }

    static func layerNodes(_ layers: [PSDLayerExtractor.ExtractedLayer]) -> [TachieLayerNode] {
        layers.enumerated().map { sourceOrder, layer in layerNode(layer, sourceOrder: sourceOrder) }
    }

    static func layerNode(_ layer: PSDLayerExtractor.ExtractedLayer, sourceOrder: Int) -> TachieLayerNode {
        TachieLayerNode(name: layer.name, isVisible: layer.isVisible, isFolder: layer.isFolder,
                        children: layerNodes(layer.children), imageFileName: layer.fileName,
                        sourceOrder: sourceOrder)
    }

    static func importPSDPreview(from source: URL, into assetsDirectory: URL) throws -> String {
        guard let image = NSImage(contentsOf: source),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "VoiceMovieStudio.PSD", code: 1, userInfo: [NSLocalizedDescriptionKey: "PSDの合成済み画像を読み取れませんでした。"])
        }
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        let fileName = "character_\(UUID().uuidString).png"
        let transparentPNG = removeEdgeConnectedWhiteBackground(from: bitmap) ?? png
        try transparentPNG.write(to: assetsDirectory.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }

    private static func removeEdgeConnectedWhiteBackground(from source: NSBitmapImageRep) -> Data? {
        let width = source.pixelsWide
        let height = source.pixelsHigh
        guard width > 0, height > 0,
              let rgba = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: .alphaNonpremultiplied,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
              ), let data = rgba.bitmapData else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rgba)
        source.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        var queue: [Int32] = []
        queue.reserveCapacity(width * 2 + height * 2)
        var visited = [Bool](repeating: false, count: width * height)
        func isBackground(_ index: Int) -> Bool {
            let offset = index * 4
            return data[offset] >= 245 && data[offset + 1] >= 245 && data[offset + 2] >= 245
        }
        func enqueue(_ index: Int) {
            guard !visited[index], isBackground(index) else { return }
            visited[index] = true
            queue.append(Int32(index))
        }
        for x in 0..<width { enqueue(x); enqueue((height - 1) * width + x) }
        for y in 0..<height { enqueue(y * width); enqueue(y * width + width - 1) }

        var cursor = 0
        while cursor < queue.count {
            let index = Int(queue[cursor])
            cursor += 1
            data[index * 4 + 3] = 0
            let x = index % width
            let y = index / width
            if x > 0 { enqueue(index - 1) }
            if x + 1 < width { enqueue(index + 1) }
            if y > 0 { enqueue(index - width) }
            if y + 1 < height { enqueue(index + width) }
        }
        return rgba.representation(using: .png, properties: [:])
    }

    nonisolated private static func extractArchive(_ source: URL) async throws -> URL {
        try await Task.detached {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("VMSArchive-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", source.path, destination.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: destination)
                throw NSError(domain: "VoiceMovieStudio.Archive", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ZIPを展開できませんでした。"])
            }
            return destination
        }.value
    }
}
