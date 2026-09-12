import SwiftUI
import VMSCore

/// §3-4 "プロジェクト設定". One undo step covers the whole time the sheet is open,
/// pushed once on appear — simpler than grouping every keystroke, and matches how a
/// modal settings sheet is edited in practice (open, adjust a few fields, close).
struct ProjectSettingsView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var hasPushedUndo = false

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 16) {
            Text("プロジェクト設定").font(.title3).bold()

            LabeledContent("プロジェクト名") {
                TextField("プロジェクト名", text: $store.project.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            LabeledContent("フレームレート") {
                TextField("fps", value: $store.project.frameRate, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("fps").foregroundColor(.secondary)
            }
            LabeledContent("解像度") {
                TextField("幅", value: $store.project.resolution.width, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("×")
                TextField("高さ", value: $store.project.resolution.height, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            HStack {
                Spacer()
                Button("閉じる") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            guard !hasPushedUndo else { return }
            hasPushedUndo = true
            store.beginUndoableChange()
        }
    }
}
