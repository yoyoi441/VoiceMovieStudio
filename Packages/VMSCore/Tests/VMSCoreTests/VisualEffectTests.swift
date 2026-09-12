import Foundation
import Testing
@testable import VMSCore

@Test func drawOrderHonorsFrontAndOptInZWithoutReorderingTimeline() {
    var back = Clip(startTime: 0, duration: 3, content: .image(ImageClipData(fileName: "back.png")))
    var front = back; front.id = UUID()
    front.effects.showInFront = true
    var z = back; z.id = UUID(); z.effects.useZOrder = true; z.effects.zPosition = 10
    back.effects.zPosition = 100 // Ignored without opt-in.
    let timeline = Timeline(tracks: [Track(name: "素材", clips: [front, z, back])])
    #expect(timeline.visibleClipsInDrawOrder(at: 1).map(\.id) == [back.id, z.id, front.id])
    #expect(timeline.tracks[0].clips.map(\.id) == [front.id, z.id, back.id])
    #expect(timeline.visibleClipsInDrawOrder(at: 4).isEmpty)
    var hidden = timeline; hidden.tracks[0].isVisible = false
    #expect(hidden.visibleClipsInDrawOrder(at: 1).isEmpty)
}

@Test func basicEffectParametersClampAndHaveFiniteDefaults() {
    for type in VisualEffectType.allCases {
        var effect = VisualEffect(type)
        for parameter in type.parameters {
            #expect(effect.value(parameter.id) == parameter.defaultValue)
            effect.setValue(parameter.id, .infinity)
            #expect(effect.value(parameter.id).isFinite)
            effect.setValue(parameter.id, -1e100)
            #expect(effect.value(parameter.id) == parameter.range.lowerBound)
            effect.setValue(parameter.id, 1e100)
            #expect(effect.value(parameter.id) == parameter.range.upperBound)
        }
        for time in [-10.0, 0, 0.3, 100, .nan, .infinity] {
            let sample = effect.sample(at: time)
            let finite = [sample.x, sample.y, sample.scale, sample.opacity, sample.rotation, sample.pixelX, sample.pixelY].allSatisfy { $0.isFinite }
            #expect(finite)
            #expect(sample.scale > 0)
            #expect((0...1).contains(sample.opacity))
        }
    }
}

@Test func movementEasingAndShakeAreTimeBased() {
    var move = VisualEffect(.move)
    move.setValue("fromX", -20)
    move.setValue("toX", 20)
    move.setValue("toScale", 200)
    #expect(move.sample(at: 0).x == -0.2)
    #expect(move.sample(at: 0.5).x == 0)
    #expect(move.sample(at: 2).x == 0.2)
    #expect(move.sample(at: 0.5).scale == 1.5)
    let smooth = move.sample(at: 0.25).x
    move.easing = .linear
    #expect(move.sample(at: 0.25).x > smooth)
    let shake = VisualEffect(.shake)
    #expect(shake.sample(at: 0).pixelX == 0)
    #expect(shake.sample(at: 0.03) != shake.sample(at: 0))
    // The sampler is stateless: seeking out of order produces identical results.
    let expected = shake.sample(at: 0.3)
    _ = shake.sample(at: 100)
    #expect(shake.sample(at: 0.3) == expected)
    #expect(abs(expected.pixelX) <= shake.value("x"))
    #expect(abs(expected.pixelY) <= shake.value("y"))
}

@Test func effectsPersistOrderingEnabledStateAndLegacyOffset() throws {
    var clip = Clip(startTime: 0, duration: 3, content: .image(ImageClipData(fileName: "image.png")))
    clip.effects.effectsList = EffectKindTemplate.allCases.map { Effect(kind: .defaultInstance(for: $0)) }
    clip.effects.effectsList[0].isEnabled = false
    clip.effects.effectsList.reverse()
    let restored = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip))
    #expect(restored == clip)
    var effect = Effect(kind: .visual(VisualEffect(.shake)))
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(effect)) as? [String: Any])
    json.removeValue(forKey: "timeOffset")
    #expect(try JSONDecoder().decode(Effect.self, from: JSONSerialization.data(withJSONObject: json)).timeOffset == nil)
    effect.timeOffset = 0.7
    guard case .visual(let visual) = effect.kind else { Issue.record("visual missing"); return }
    #expect(visual.sample(at: 0.3 + (effect.timeOffset ?? 0)) == visual.sample(at: 1))
    #expect(EffectKind.defaultInstance(for: .monochrome).isImplemented)
    #expect(EffectKind.defaultInstance(for: .glow).isImplemented)
    #expect(EffectKind.defaultInstance(for: .mosaic).isImplemented)
}
