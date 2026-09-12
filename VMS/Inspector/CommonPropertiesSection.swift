import SwiftUI
import VMSCore

/// §7-2 "共通項目": X/Y/Z, opacity, scale, rotation, blend mode, fade in/out, flip,
/// show-in-front, z-order, clipping, notes, and the effect list — shown for every clip
/// type (position controls hide themselves for audio, which has no on-canvas position).
/// Every control here is one of the shared property-control types (§7-1) bound through
/// `ProjectStore`'s mixed-value helpers, so it already supports multi-selection and
/// per-gesture undo for free.
struct CommonPropertiesSection: View {
    @Environment(ProjectStore.self) private var store
    let clip: Clip

    private var isText: Bool {
        if case .text = clip.content { return true }
        return false
    }

    private var hasPosition: Bool {
        switch clip.content {
        case .text, .character, .image, .video: return true
        case .audio: return false
        }
    }

    var body: some View {
        PropertySection("共通") {
            if hasPosition {
                NumericPropertyControl(label: "X", value: positionBinding(\.x), range: -1...1, decimalPlaces: 2, resetValue: 0)
                NumericPropertyControl(label: "Y", value: positionBinding(\.y), range: -1...1, decimalPlaces: 2, resetValue: 0)
            }
            NumericPropertyControl(label: "Z", value: effectsNumeric(\.zPosition, { $0.zPosition = $1 }), range: -100...100, resetValue: 0)

            if !isAudio {
                NumericPropertyControl(label: "不透明度", value: effectsNumeric(\.opacity, { $0.opacity = $1 }), range: 0...1, decimalPlaces: 2, unit: "%", resetValue: 1)
                NumericPropertyControl(label: "拡大率", value: effectsNumeric(\.scale, { $0.scale = $1 }), range: 0.1...3, decimalPlaces: 2, unit: "×", resetValue: 1)
                NumericPropertyControl(label: "回転角", value: effectsNumeric(\.rotationDegrees, { $0.rotationDegrees = $1 }), range: -180...180, unit: "°", resetValue: 0)
                SelectPropertyControl(
                    label: "合成モード",
                    value: store.mixedBinding(get: { $0.effects.blendMode }, set: { $0.effects.blendMode = $1 }),
                    options: BlendModeOption.allCases.map { ($0, $0.displayName) }
                )
            }

            NumericPropertyControl(
                label: isAudio ? "音量フェードイン" : "フェードイン",
                value: effectsNumeric(\.fadeInDuration, { $0.fadeInDuration = max(0, $1) }),
                range: 0...min(clip.duration, 10),
                decimalPlaces: 1, unit: "秒"
            )
            NumericPropertyControl(
                label: isAudio ? "音量フェードアウト" : "フェードアウト",
                value: effectsNumeric(\.fadeOutDuration, { $0.fadeOutDuration = max(0, $1) }),
                range: 0...min(clip.duration, 10),
                decimalPlaces: 1, unit: "秒"
            )

            if !isAudio {
                TogglePropertyControl(label: "左右反転", value: store.mixedBinding(get: { $0.effects.flipHorizontal }, set: { $0.effects.flipHorizontal = $1 }))
                TogglePropertyControl(label: "手前に表示", value: store.mixedBinding(get: { $0.effects.showInFront }, set: { $0.effects.showInFront = $1 }))
                TogglePropertyControl(label: "Z値順に表示", value: store.mixedBinding(get: { $0.effects.useZOrder }, set: { $0.effects.useZOrder = $1 }))
                TogglePropertyControl(label: "クリッピング", value: store.mixedBinding(get: { $0.effects.clipToAbove }, set: { $0.effects.clipToAbove = $1 }))
            }

            notesField

            if !isAudio {
                Divider()
                Text("エフェクト一覧（主選択アイテム）").font(Theme.labelFont).bold()
                EffectList(clip: clip, isText: isText)
            }
        }
    }

    private var isAudio: Bool {
        if case .audio = clip.content { return true }
        return false
    }

    private var notesField: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("備考").font(Theme.labelFont).foregroundColor(.secondary).frame(width: 64, alignment: .leading)
            TextField(
                "",
                text: Binding(
                    get: { clip.effects.notes },
                    set: { newValue in
                        var updated = clip
                        updated.effects.notes = newValue
                        store.updateClip(updated)
                    }
                ),
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...3)
        }
    }

    private func effectsNumeric(
        _ keyPath: KeyPath<ClipEffects, Double>,
        _ set: @escaping (inout ClipEffects, Double) -> Void
    ) -> Binding<Double?> {
        store.numericBinding(
            get: { $0.effects[keyPath: keyPath] },
            set: { clip, newValue in set(&clip.effects, newValue) }
        )
    }

    private func positionBinding(_ axis: WritableKeyPath<CodablePoint, Double>) -> Binding<Double?> {
        store.numericBinding(
            get: { clip in Self.position(of: clip)?[keyPath: axis] ?? 0 },
            set: { clip, newValue in
                var point = Self.position(of: clip) ?? CodablePoint(x: 0, y: 0)
                point[keyPath: axis] = min(max(newValue, -1), 1)
                Self.setPosition(point, on: &clip)
            }
        )
    }

    private static func position(of clip: Clip) -> CodablePoint? {
        switch clip.content {
        case .text(let data): return data.position
        case .character(let data): return data.position
        case .image(let data): return data.position
        case .video(let data): return data.position
        case .audio: return nil
        }
    }

    private static func setPosition(_ point: CodablePoint, on clip: inout Clip) {
        switch clip.content {
        case .text(var data):
            data.position = point
            clip.content = .text(data)
        case .character(var data):
            data.position = point
            clip.content = .character(data)
        case .image(var data):
            data.position = point
            clip.content = .image(data)
        case .video(var data):
            data.position = point
            clip.content = .video(data)
        case .audio:
            break
        }
    }
}
