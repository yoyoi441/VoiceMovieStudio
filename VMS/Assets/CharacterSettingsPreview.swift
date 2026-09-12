import SwiftUI
import VMSCore

/// Uses the same compositor as preview/export to audit full-body and facial parts.
struct CharacterSettingsPreview: View {
    @Environment(ProjectStore.self) private var store
    let character: Character
    var previewHeight: CGFloat = 300
    @State private var useDefault = true
    @State private var animate = false
    @State private var faceZoom = false
    @State private var mouth: MouthShape = .closed
    @State private var expressionID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            SwiftUI.TimelineView(.animation(minimumInterval: 1 / 20, paused: !animate)) { tick in
                let time = animate ? tick.date.timeIntervalSinceReferenceDate : 0
                let shapes: [MouthShape] = [.closed, .small, .open, .small]
                let shape = animate ? shapes[Int(time * 6 * character.defaultMouthSpeed) % shapes.count] : mouth
                var previewCharacter: Character {
                    var value = character
                    value.defaultExpressionID = useDefault ? character.defaultExpressionID : expressionID
                    return value
                }
                var clip: Clip {
                    var value = Clip(startTime: 0, duration: time + 1, content: .character(CharacterClipData(
                        characterID: character.id,
                        position: CodablePoint(x: 0, y: faceZoom ? 1.1 : 0),
                        scale: faceZoom ? 2.7 : 1.25,
                        mouthKeyframes: [MouthKeyframe(time: 0, shape: shape)],
                        expressionID: useDefault ? character.defaultExpressionID : expressionID
                    )))
                    value.effects.flipHorizontal = character.defaultFlipHorizontal
                    return value
                }
                CompositeFrameView(
                    project: Project(name: "設定プレビュー", resolution: CodableSize(width: 540, height: 300), characters: [previewCharacter]),
                    timeline: Timeline(tracks: [Track(name: "プレビュー", clips: [clip])]),
                    time: time,
                    imageProvider: store.imageProvider,
                    videoFrameProvider: store.videoFrameProvider
                )
                .frame(maxWidth: .infinity).clipped()
            }.frame(height: previewHeight)
            Toggle("保存済みデフォルトを表示", isOn: $useDefault).toggleStyle(.switch).font(.caption)
            HStack {
                Toggle("動作確認", isOn: $animate).toggleStyle(.switch)
                Toggle("顔を拡大", isOn: $faceZoom).toggleStyle(.switch)
                Picker("口", selection: $mouth) {
                    Text("通常").tag(MouthShape.closed)
                    Text("小").tag(MouthShape.small)
                    Text("開").tag(MouthShape.open)
                }.disabled(animate)
            }.font(.caption)
            Picker("確認する表情", selection: $expressionID) {
                Text("通常の立ち絵").tag(UUID?.none)
                ForEach(character.expressions) { Text($0.name).tag(Optional($0.id)) }
            }.disabled(useDefault)
            Text("動作確認は口パク・目パチの見本です。音声は再生しません。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { expressionID = character.defaultExpressionID }
        .onChange(of: character.expressions.map(\.id)) { _, ids in
            if let expressionID, !ids.contains(expressionID) { self.expressionID = nil }
        }
    }
}

struct CharacterBlinkControls: View {
    @Environment(ProjectStore.self) private var store
    let character: Character
    var body: some View {
        Toggle("目パチを有効にする", isOn: Binding(get: { character.blinkEnabled }, set: { value in
            guard let index = store.project.characters.firstIndex(where: { $0.id == character.id }) else { return }
            store.beginUndoableChange()
            store.project.characters[index].blinkEnabled = value
        })).toggleStyle(.switch)
        NumericPropertyControl(label: "間隔", value: numeric(\.blinkInterval), range: 0.5...20, step: 0.1, decimalPlaces: 2, unit: "秒", resetValue: 3.2)
            .disabled(!character.blinkEnabled)
        NumericPropertyControl(label: "閉じる長さ", value: numeric(\.blinkDuration), range: 0.05...0.5, step: 0.01, decimalPlaces: 2, unit: "秒", resetValue: 0.18)
            .disabled(!character.blinkEnabled)
    }
    private func numeric(_ key: WritableKeyPath<Character, Double>) -> Binding<Double?> {
        Binding(get: { character[keyPath: key] }, set: { value in
            guard let value, value.isFinite,
                  let index = store.project.characters.firstIndex(where: { $0.id == character.id }) else { return }
            // NumericPropertyControl records the gesture as one Undo operation.
            store.project.characters[index][keyPath: key] = value
        })
    }
}
