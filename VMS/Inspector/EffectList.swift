import SwiftUI
import VMSCore

/// §7-4: add/remove/duplicate/reorder/enable-toggle for a clip's `effectsList`, plus the
/// selected effect's detail editor. Visual effects run in list order; text decorations
/// form the source text before the visual stack is applied.
struct EffectList: View {
    @Environment(ProjectStore.self) private var store
    let clip: Clip
    /// Text-only kinds (outline/shadow/gradient) only show in the "add" menu for text clips.
    let isText: Bool

    @State private var selectedEffectID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Menu {
                    ForEach(availableTemplates, id: \.self) { template in
                        Button(template.displayName + (EffectKind.defaultInstance(for: template).isImplemented ? "" : "（未対応）")) { addEffect(template) }
                            .disabled(!EffectKind.defaultInstance(for: template).isImplemented || effectsList.count >= 64)
                    }
                } label: {
                    IconCatalog.resolve(.duplicate).font(.system(size: 10))
                    Text("追加").font(.caption2)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("エフェクト追加")

                Button { removeSelected() } label: {
                    IconCatalog.resolve(.delete).font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(selectedEffectID == nil)
                .help("削除")

                Button { duplicateSelected() } label: {
                    IconCatalog.resolve(.duplicate).font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(selectedEffectID == nil)
                .help("複製")
                .disabled(effectsList.count >= 64)

                Button { moveSelected(by: -1) } label: {
                    IconCatalog.resolve(.moveUp).font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(!canMove(by: -1))
                .help("上へ移動")

                Button { moveSelected(by: 1) } label: {
                    IconCatalog.resolve(.moveDown).font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(!canMove(by: 1))
                .help("下へ移動")

                Spacer()

                Menu {
                    Button("プリセットとして保存(未実装)") {}
                        .disabled(true)
                } label: {
                    IconCatalog.resolve(.more).font(.system(size: 10))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("その他")
            }

            if effectsList.isEmpty {
                Text("エフェクトはありません").font(.caption2).foregroundColor(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(effectsList) { effect in
                        effectRow(effect)
                    }
                }
            }

            if let selected = effectsList.first(where: { $0.id == selectedEffectID }) {
                Divider()
                EffectDetailEditor(clip: clip, effect: selected)
            }
            if effectsList.contains(where: {
                guard $0.isEnabled, case .visual(let v) = $0.kind else { return false }
                return [.move, .shake, .spin, .pulse, .verticalFlip].contains(v.type)
            }) {
                Text("変形効果が有効な間は直接ドラッグを停止します。基準位置は共通のX/Yで調整してください。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if effectsList.count > 64 {
                Text("効果は最大64件まで描画します。余分な効果を削除してください。")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .disabled(clip.isLocked || store.currentTimeline.tracks.contains { $0.isLocked && $0.clips.contains { $0.id == clip.id } })
    }

    private var effectsList: [Effect] { clip.effects.effectsList }

    private var availableTemplates: [EffectKindTemplate] {
        EffectKindTemplate.allCases.filter { isText || !$0.isTextOnly }
    }

    private func effectRow(_ effect: Effect) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { effect.isEnabled },
                set: { newValue in
                    store.beginUndoableChange()
                    updateEffect(effect.id) { $0.isEnabled = newValue }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text(effect.kind.displayName)
                .font(.caption)
                .foregroundColor(effect.kind.isImplemented ? .primary : .secondary)
            if !effect.kind.isImplemented {
                Text("(未対応)").font(.caption2).foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(selectedEffectID == effect.id ? Theme.selectionFill : Color.clear)
        .cornerRadius(3)
        .contentShape(Rectangle())
        .onTapGesture { selectedEffectID = effect.id }
    }

    private func addEffect(_ template: EffectKindTemplate) {
        store.beginUndoableChange()
        var updated = clip
        let effect = Effect(kind: .defaultInstance(for: template))
        updated.effects.effectsList.append(effect)
        store.updateClip(updated)
        selectedEffectID = effect.id
    }

    private func removeSelected() {
        guard let id = selectedEffectID else { return }
        store.beginUndoableChange()
        var updated = clip
        updated.effects.effectsList.removeAll { $0.id == id }
        store.updateClip(updated)
        selectedEffectID = nil
    }

    private func duplicateSelected() {
        guard let id = selectedEffectID, let index = effectsList.firstIndex(where: { $0.id == id }) else { return }
        store.beginUndoableChange()
        var updated = clip
        var copy = effectsList[index]
        copy.id = UUID()
        updated.effects.effectsList.insert(copy, at: index + 1)
        store.updateClip(updated)
        selectedEffectID = copy.id
    }

    private func canMove(by offset: Int) -> Bool {
        guard let id = selectedEffectID, let index = effectsList.firstIndex(where: { $0.id == id }) else { return false }
        let target = index + offset
        return target >= 0 && target < effectsList.count
    }

    private func moveSelected(by offset: Int) {
        guard let id = selectedEffectID, let index = effectsList.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard target >= 0 && target < effectsList.count else { return }
        store.beginUndoableChange()
        var updated = clip
        updated.effects.effectsList.move(fromOffsets: IndexSet(integer: index), toOffset: target > index ? target + 1 : target)
        store.updateClip(updated)
    }

    private func updateEffect(_ id: UUID, _ mutate: (inout Effect) -> Void) {
        var updated = clip
        guard let index = updated.effects.effectsList.firstIndex(where: { $0.id == id }) else { return }
        mutate(&updated.effects.effectsList[index])
        store.updateClip(updated)
    }
}

/// The selected effect's own parameters — only shown for kinds with something to edit.
private struct EffectDetailEditor: View {
    @Environment(ProjectStore.self) private var store
    let clip: Clip
    let effect: Effect

    var body: some View {
        switch effect.kind {
        case .blur:
            NumericPropertyControl(
                label: "半径",
                value: doubleBinding(
                    get: { if case .blur(let radius) = $0 { radius } else { 0 } },
                    set: { $0 = .blur(radius: max(0, $1)) }
                ),
                range: 0...50
            )
        case .outline:
            VStack(alignment: .leading, spacing: 6) {
                NumericPropertyControl(
                    label: "太さ",
                    value: doubleBinding(
                        get: { if case .outline(let o) = $0 { o.width } else { 0 } },
                        set: { if case .outline(var o) = $0 { o.width = max(0, $1); $0 = .outline(o) } }
                    ),
                    range: 0...20
                )
                ColorPropertyControl(label: "色", value: colorBinding(
                    get: { if case .outline(let o) = $0.kind { o.color } else { nil } },
                    set: { if case .outline(var o) = $0.kind { o.color = $1; $0.kind = .outline(o) } }
                ))
            }
        case .shadow:
            VStack(alignment: .leading, spacing: 6) {
                NumericPropertyControl(
                    label: "ぼかし",
                    value: doubleBinding(
                        get: { if case .shadow(let s) = $0 { s.radius } else { 0 } },
                        set: { if case .shadow(var s) = $0 { s.radius = max(0, $1); $0 = .shadow(s) } }
                    ),
                    range: 0...30
                )
                ColorPropertyControl(label: "色", value: colorBinding(
                    get: { if case .shadow(let s) = $0.kind { s.color } else { nil } },
                    set: { if case .shadow(var s) = $0.kind { s.color = $1; $0.kind = .shadow(s) } }
                ))
            }
        case .gradient(let gradient):
            GradientEditor(clip: clip, effectID: effect.id, gradient: gradient)
        case .visual(let visual):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visual.type.parameters) { parameter in
                    NumericPropertyControl(label: parameter.label, value: doubleBinding(
                        get: { if case .visual(let value) = $0 { value.value(parameter.id) } else { parameter.defaultValue } },
                        set: { if case .visual(var value) = $0 { value.setValue(parameter.id, $1); $0 = .visual(value) } }
                    ), range: parameter.range, step: parameter.step, decimalPlaces: parameter.step < 1 ? 2 : 0,
                    unit: parameter.unit, resetValue: parameter.defaultValue)
                }
                if visual.type == .move {
                    Picker("動き方", selection: Binding(get: { visual.easing }, set: { value in
                        store.beginUndoableChange()
                        var updated = clip
                        if let i = updated.effects.effectsList.firstIndex(where: { $0.id == effect.id }),
                           case .visual(var settings) = updated.effects.effectsList[i].kind {
                            settings.easing = value
                            updated.effects.effectsList[i].kind = .visual(settings)
                            store.updateClip(updated)
                        }
                    })) {
                        ForEach(VisualEasing.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Text("X/Yは元の位置から画面幅・高さに対する移動量です。再生して動きを確認してください。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if visual.type == .blink {
                    Text("点滅が苦手な方への配慮として、速さ・濃度は控えめにしてください。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if visual.type == .crop {
                    Text("画面端から切り抜きます。左右または上下の合計が100%以上になると非表示です。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .glow:
            NumericPropertyControl(label: "半径", value: doubleBinding(
                get: { if case .glow(let radius) = $0 { radius } else { 8 } },
                set: { $0 = .glow(radius: min(50, max(0, $1))) }
            ), range: 0...50, unit: "px")
        case .monochrome:
            Text("彩度をなくして白黒にします。").font(.caption2).foregroundStyle(.secondary)
        case .mosaic:
            NumericPropertyControl(label: "ブロック幅", value: doubleBinding(
                get: { if case .mosaic(let size) = $0 { size } else { 8 } },
                set: { $0 = .mosaic(blockSize: min(200, max(1, $1))) }
            ), range: 1...200, unit: "px")
            Text("横1920pxを基準にした幅です。").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func doubleBinding(
        get: @escaping (EffectKind) -> Double,
        set: @escaping (inout EffectKind, Double) -> Void
    ) -> Binding<Double?> {
        Binding(
            get: { get(effect.kind) },
            set: { newValue in
                guard let newValue, newValue.isFinite else { return }
                var updated = clip
                guard let index = updated.effects.effectsList.firstIndex(where: { $0.id == effect.id }) else { return }
                set(&updated.effects.effectsList[index].kind, newValue)
                store.updateClip(updated)
            }
        )
    }

    private func colorBinding(
        get: @escaping (Effect) -> CodableColor?,
        set: @escaping (inout Effect, CodableColor) -> Void
    ) -> Binding<CodableColor?> {
        Binding(
            get: { get(effect) },
            set: { newValue in
                guard let newValue else { return }
                store.beginUndoableChange()
                var updated = clip
                guard let index = updated.effects.effectsList.firstIndex(where: { $0.id == effect.id }) else { return }
                set(&updated.effects.effectsList[index], newValue)
                store.updateClip(updated)
            }
        )
    }
}
