import AppKit
import SwiftUI
import VMSCore

struct CreditDescriptionView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AquesTalkPlayerSettings.publicLicenseIDKey) private var aquesTalkPublicLicenseID = ""

    private var entries: [ProjectCreditEntry] { ProjectCreditBuilder.usedEntries(project: store.project) }
    private var text: String {
        ProjectCreditBuilder.descriptionText(
            project: store.project,
            aquesTalkPublicLicenseID: aquesTalkPublicLicenseID
        )
    }
    private var usesAquesTalk: Bool { ProjectCreditBuilder.usesAquesTalkPlayer(project: store.project) }

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
            if usesAquesTalk {
                GroupBox("AquesTalk Player") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AquesTalkPlayerSupport.commercialUseNotice)
                            .font(.caption).foregroundStyle(.orange)
                        TextField("公開用ライセンスID（必要な場合のみ）", text: $aquesTalkPublicLicenseID)
                            .textFieldStyle(.roundedBorder)
                        Text("ここには秘密のライセンスキーを入力しないでください。受託制作などで公開用IDの記載を求められた場合だけ使用します。")
                            .font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Link("公式の利用条件", destination: URL(string: AquesTalkPlayerSupport.officialPageURL)!)
                            Link("使用ライセンス", destination: URL(string: AquesTalkPlayerSupport.licenseStoreURL)!)
                        }.font(.caption)
                    }
                }
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
        .frame(width: 680, height: usesAquesTalk ? 620 : 480)
    }
}
