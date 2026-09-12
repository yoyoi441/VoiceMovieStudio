import AppKit
import Foundation

/// End-to-end smoke test for the PSD animation composition used by character previews.
/// It verifies that mouth/eye category folders are removed from the neutral base and
/// that two real animation states produce different complete character frames.
@main struct PSDAnimationPartsSmoke {
    typealias Layer = PSDLayerExtractor.ExtractedLayer

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw failure("usage: test input.psd output-directory")
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let layers = try PSDLayerExtractor.extract(from: input, into: output)

        let neutralFiles = visibleFiles(
            layers, excludingCategoryNames: ["口", "目"]
        ).reversed()
        let mouthClosed = try requireLayer(named: "んー", in: layers)
        let mouthOpen = try requireLayer(named: "わあー", in: layers)
        let eyeOpen = try requireLayer(named: "目セット", in: layers)
        let eyeClosed = try requireLayer(named: "目閉じ", in: layers)

        let neutralFileName = "neutral-without-mouth-eyes.png"
        let neutral = try composite(Array(neutralFiles), in: output)
        try save(neutral, to: output.appendingPathComponent(neutralFileName))
        let closedFrame = try composite(
            [neutralFileName] + drawOrderFiles(for: mouthClosed) + drawOrderFiles(for: eyeOpen),
            in: output
        )
        let openFrame = try composite(
            [neutralFileName] + drawOrderFiles(for: mouthOpen) + drawOrderFiles(for: eyeClosed),
            in: output
        )
        let embedded = try requireImage(at: input)

        try save(closedFrame, to: output.appendingPathComponent("mouth-closed-eyes-open.png"))
        try save(openFrame, to: output.appendingPathComponent("mouth-open-eyes-closed.png"))

        let removedPixelCount = differentPixelCount(embedded, neutral)
        let animatedPixelCount = differentPixelCount(closedFrame, openFrame)
        print("Embedded-to-neutral changed pixels: \(removedPixelCount)")
        print("Animation-state changed pixels: \(animatedPixelCount)")
        precondition(removedPixelCount > 100, "Neutral base still matches the embedded PSD composite")
        precondition(animatedPixelCount > 100, "Mouth/eye states did not produce a visible change")
        let report = """
        PASS: neutral base excludes PSD mouth/eye categories
        PASS: actual mouth/eye states differ by \(animatedPixelCount) pixels
        Embedded-to-neutral changed pixels: \(removedPixelCount)
        """
        try report.write(
            to: output.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8
        )
        FileHandle.standardOutput.write(Data((report + "\n" + output.path + "\n").utf8))
    }

    static func cleaned(_ name: String) -> String {
        name.trimmingCharacters(in: CharacterSet(charactersIn: "!*#@ \t"))
    }

    static func requireLayer(named name: String, in nodes: [Layer]) throws -> Layer {
        for node in nodes {
            if cleaned(node.name) == name { return node }
            if let found = try? requireLayer(named: name, in: node.children) { return found }
        }
        throw failure("PSDレイヤー「\(name)」が見つかりません。")
    }

    static func visibleFiles(
        _ nodes: [Layer],
        parentVisible: Bool = true,
        excludingCategoryNames excluded: Set<String> = []
    ) -> [String] {
        nodes.flatMap { node -> [String] in
            if node.isFolder, excluded.contains(cleaned(node.name)) { return [] }
            let visible = parentVisible && node.isVisible
            if node.isFolder {
                return visibleFiles(
                    node.children, parentVisible: visible,
                    excludingCategoryNames: excluded
                )
            }
            return visible ? [node.fileName].compactMap { $0 } : []
        }
    }

    static func drawOrderFiles(for layer: Layer) -> [String] {
        if let fileName = layer.fileName { return [fileName] }
        return Array(visibleFiles(layer.children).reversed())
    }

    static func composite(_ filesInDrawOrder: [String], in directory: URL) throws -> NSImage {
        guard let firstName = filesInDrawOrder.first else { throw failure("合成対象が空です。") }
        let first = try requireImage(at: directory.appendingPathComponent(firstName))
        guard let firstCG = first.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = bitmapContext(width: firstCG.width, height: firstCG.height) else {
            throw failure("合成用ビットマップを作成できません。")
        }
        let rect = CGRect(x: 0, y: 0, width: firstCG.width, height: firstCG.height)
        context.clear(rect)
        context.interpolationQuality = .high
        context.setBlendMode(.normal)
        for file in filesInDrawOrder {
            let image = try requireImage(at: directory.appendingPathComponent(file))
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw failure("レイヤー画像を描画できません：\(file)")
            }
            context.setBlendMode(.normal)
            context.draw(cgImage, in: rect)
        }
        guard let result = context.makeImage() else { throw failure("合成画像を確定できません。") }
        return NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height))
    }

    static func requireImage(at url: URL) throws -> NSImage {
        guard let image = NSImage(contentsOf: url) else {
            throw failure("画像を読み込めません：\(url.lastPathComponent)")
        }
        return image
    }

    static func save(_ image: NSImage, to url: URL) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bitmap = Optional(NSBitmapImageRep(cgImage: cgImage)),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw failure("検査画像を保存できません。")
        }
        try png.write(to: url, options: .atomic)
    }

    static func differentPixelCount(_ lhs: NSImage, _ rhs: NSImage) -> Int {
        guard let left = rgba(lhs), let right = rgba(rhs), left.count == right.count else {
            return Int.max
        }
        var count = 0
        for offset in stride(from: 0, to: left.count, by: 4) {
            if left[offset] != right[offset]
                || left[offset + 1] != right[offset + 1]
                || left[offset + 2] != right[offset + 2]
                || left[offset + 3] != right[offset + 3] {
                count += 1
            }
        }
        return count
    }

    static func rgba(_ image: NSImage) -> [UInt8]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = bitmapContext(width: cgImage.width, height: cgImage.height) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let data = context.data else { return nil }
        return Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self), count: cgImage.width * cgImage.height * 4
        ))
    }

    static func bitmapContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "VoiceMovieStudio.PSDAnimationSmoke", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
