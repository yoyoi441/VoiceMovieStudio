// Compile with the real CompositeFrameView.swift and VMSCore objects. Providers below
// are deterministic fixtures: this checks actual Canvas rendering without user assets.
import AppKit
import SwiftUI
import VMSCore

@MainActor final class CharacterImageProvider {
    let fixture: NSImage
    init() {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<80 { for x in 0..<80 {
            let pixel = bitmap.bitmapData! + y * bitmap.bytesPerRow + x * 4
            pixel[0] = y < 40 ? 255 : 0
            pixel[1] = 0
            pixel[2] = y < 40 ? 0 : 255
            pixel[3] = 255
        } }
        fixture = NSImage(size: NSSize(width: 80, height: 80))
        fixture.addRepresentation(bitmap)
    }
    func image(named: String?) -> NSImage? { fixture }
}
@MainActor final class VideoFrameProvider {
    let fixture = CharacterImageProvider()
    func image(fileName: String, sourceTime: Double, frameRate: Double) -> NSImage? { fixture.fixture }
}

@main struct EffectsRenderSmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let images = CharacterImageProvider(), videos = VideoFrameProvider()
        var project = Project(name: "描画テスト")
        project.resolution = CodableSize(width: 320, height: 180)
        let character = Character(name: "描画テスト", baseImageFileName: "fixture")
        project.characters = [character]
        let directory = URL(fileURLWithPath: "/tmp/vms-effects-render-smoke", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func render(_ name: String, effects: [Effect], time: Double = 0.03,
                    content: ClipContent = .image(ImageClipData(fileName: "fixture"))) throws -> NSBitmapImageRep {
            var clip = Clip(startTime: 0, duration: 3, content: content)
            clip.effects.effectsList = effects
            let renderer = ImageRenderer(content: CompositeFrameView(project: project,
                timeline: Timeline(tracks: [Track(name: "素材", clips: [clip])]), time: time,
                imageProvider: images, videoFrameProvider: videos))
            renderer.scale = 1
            guard let image = renderer.cgImage else { fatalError("Frame render failed: \(name)") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
            return bitmap
        }
        func pixels(_ bitmap: NSBitmapImageRep) -> Data {
            Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        let plain = try render("plain", effects: [])
        for template in EffectKindTemplate.allCases where !template.isTextOnly {
            var effect = Effect(kind: .defaultInstance(for: template))
            if template == .mosaic { effect.kind = .mosaic(blockSize: 150) }
            if case .visual(var v) = effect.kind {
                if v.type == .colorAdjustment { v.setValue("brightness", 30) }
                if v.type == .crop { v.setValue("left", 50) }
                effect.kind = .visual(v)
            }
            let result = try render(template.rawValue, effects: [effect])
            precondition(pixels(plain) != pixels(result), "Effect had no visible result: \(template)")
            effect.isEnabled = false
            let disabled = try render(template.rawValue + "-disabled", effects: [effect])
            precondition(pixels(plain) == pixels(disabled), "Disabled effect changed output")
        }
        let mono = try render("mono-check", effects: [Effect(kind: .monochrome)])
        let pixel = mono.colorAt(x: 150, y: 65)!.usingColorSpace(.deviceRGB)!
        precondition(abs(pixel.redComponent - pixel.greenComponent) < 0.03 && abs(pixel.greenComponent - pixel.blueComponent) < 0.03)
        var crop = VisualEffect(.crop); crop.setValue("left", 50)
        let a = Effect(kind: .blur(radius: 15)), b = Effect(kind: .visual(crop))
        let first = try render("blur-then-crop", effects: [a, b])
        let second = try render("crop-then-blur", effects: [b, a])
        precondition(pixels(first) != pixels(second), "Effect order did not change rendering")
        for (key, value) in [("brightness", 30.0), ("contrast", 50), ("saturation", 0), ("hue", 90)] {
            var adjustment = VisualEffect(.colorAdjustment); adjustment.setValue(key, value)
            let adjusted = try render("color-" + key, effects: [Effect(kind: .visual(adjustment))])
            precondition(pixels(plain) != pixels(adjusted), "Color control ignored: \(key)")
        }
        let kinds: [ClipContent] = [.text(TextClipData(text: "動く字幕")),
            .character(CharacterClipData(characterID: character.id)),
            .video(VideoClipData(assetID: UUID(), fileName: "fixture"))]
        for (index, content) in kinds.enumerated() {
            let original = try render("type-\(index)-original", effects: [], time: 1, content: content)
            let moved = try render("type-\(index)-moved", effects: [Effect(kind: .visual(VisualEffect(.move)))], time: 1, content: content)
            precondition(pixels(original) != pixels(moved), "Content did not move: \(index)")
        }
        print("PASS: actual Canvas effect rendering, disabled state, monochrome channels, effect order; PNGs: \(directory.path)")
    }
}
