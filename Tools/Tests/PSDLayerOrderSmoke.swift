import AppKit
import Foundation

@main struct PSDLayerOrderSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "PSDLayerOrderSmoke", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "usage: test input.psd output-directory"])
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let firstDirectory = output.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = output.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let first = try PSDLayerExtractor.extract(from: input, into: firstDirectory)
        let second = try PSDLayerExtractor.extract(from: input, into: secondDirectory)

        func signature(_ nodes: [PSDLayerExtractor.ExtractedLayer], depth: Int = 0) -> [String] {
            nodes.flatMap { node in
                [String(repeating: "  ", count: depth) + (node.isFolder ? "📁 " : "🖼 ")
                    + (node.isVisible ? "表示 " : "非表示 ") + node.name]
                    + signature(node.children, depth: depth + 1)
            }
        }
        let firstSignature = signature(first)
        precondition(firstSignature == signature(second), "Two imports produced different hierarchy/order")
        precondition(first.count > 1, "PSD root hierarchy unexpectedly collapsed")
        try firstSignature.joined(separator: "\n").write(
            to: output.appendingPathComponent("layer-order.txt"), atomically: true, encoding: .utf8)

        func visible(_ nodes: [PSDLayerExtractor.ExtractedLayer], parentVisible: Bool = true) -> [String] {
            nodes.flatMap { node -> [String] in
                let isVisible = parentVisible && node.isVisible
                if node.isFolder { return visible(node.children, parentVisible: isVisible) }
                return isVisible ? [node.fileName].compactMap { $0 } : []
            }
        }
        guard let original = NSImage(contentsOf: input),
              let firstFile = visible(first).first,
              let layerImage = NSImage(contentsOf: firstDirectory.appendingPathComponent(firstFile)) else {
            throw NSError(domain: "PSDLayerOrderSmoke", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "PSD or extracted layers cannot be rendered"])
        }
        let composite = NSImage(size: layerImage.size)
        composite.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        for file in visible(first).reversed() {
            NSImage(contentsOf: firstDirectory.appendingPathComponent(file))?.draw(
                in: NSRect(origin: .zero, size: layerImage.size), from: .zero,
                operation: .sourceOver, fraction: 1)
        }
        composite.unlockFocus()
        func save(_ image: NSImage, name: String) throws {
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "PSDLayerOrderSmoke", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "PNG creation failed"])
            }
            try png.write(to: output.appendingPathComponent(name), options: .atomic)
        }
        try save(original, name: "embedded-composite.png")
        try save(composite, name: "layer-composite.png")
        print("PASS: stable native hierarchy/order; root=\(first.count), visible=\(visible(first).count), total=\(firstSignature.count)")
        print(output.path)
    }
}
