import AppKit
import SwiftUI
import VMSCore

struct CreditDescriptionView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var entries: [ProjectCreditEntry] { ProjectCreditBuilder.usedEntries(project: store.project) }
    private var text: String { ProjectCreditBuilder.descriptionText(project: store.project) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("使用素材・クレジット").font(.title3).bold()
                Spacer()
                Button("閉じる") { dismiss() }
            }
            Text("タイムラインで実際に使用している素材だけを自動集計しています。")
                .font(.caption).foregroundColor(.secondary)
            if entries.contains(where: { $0.credit.creator.isEmpty || $0.credit.sourceURL.isEmpty }) {
                Label("作者名または配布元が未登録の素材があります。投稿前に確認してください。", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.orange)
            }
            TextEditor(text: .constant(text))
                .font(.body.monospaced())
                .frame(minHeight: 300)
                .border(Color.secondary.opacity(0.3))
            HStack {
                Text("\(entries.count)素材").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("概要欄用テキストをコピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 680, height: 480)
    }
}
