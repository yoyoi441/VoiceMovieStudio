import SwiftUI
import VMSCore

/// Style IDs come from the engine, not from a fixed set of emotion names.
struct VoiceStylePicker: View {
    let speakers: [VoiceSpeaker]
    @Binding var selection: Int?

    private var selected: VoiceSpeaker? { speakers.first { $0.id == selection } }
    private var names: [String] { Array(Set(speakers.map(\.name))).sorted() }
    private var styles: [VoiceSpeaker] { speakers.filter { $0.name == selected?.name } }

    var body: some View {
        HStack {
            Picker("話者", selection: Binding(
                get: { selected?.name ?? "" },
                set: { name in selection = speakers.first { $0.name == name }?.id }
            )) {
                Text("未選択").tag("")
                ForEach(names, id: \.self) { Text($0).tag($0) }
            }
            Picker("感情・スタイル", selection: $selection) {
                Text("未選択").tag(Int?.none)
                ForEach(styles) { Text($0.styleName).tag(Int?.some($0.id)) }
            }
            .disabled(styles.isEmpty)
        }
    }
}

/// Draft controls do not add project Undo entries until inserted or saved as defaults.
struct VoiceDraftControls: View {
    @Binding var settings: VoiceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(VoiceVoxParameter.allCases) { parameter in
                HStack {
                    Text(parameter.label).frame(width: 72, alignment: .leading)
                    Slider(value: binding(parameter), in: parameter.range, step: 0.01)
                    TextField("", value: binding(parameter), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder).frame(width: 64)
                        .accessibilityLabel(parameter.label)
                }
            }
            Text("感情は選択した話者のスタイルで指定します。抑揚は声の高低の幅で、感情の強さとは別です。")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: 520)
    }

    private func binding(_ parameter: VoiceVoxParameter) -> Binding<Double> {
        Binding(get: { settings[keyPath: parameter.keyPath] },
                set: { settings[keyPath: parameter.keyPath] = parameter.clamp($0) })
    }
}
