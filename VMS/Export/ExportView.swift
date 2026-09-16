import SwiftUI
import AppKit
import VMSCore

struct ExportView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var exporter = VideoExporter()
    @State private var errorMessage: String?
    @State private var didFinish = false
    @AppStorage(AquesTalkPlayerSettings.publicLicenseIDKey) private var aquesTalkPublicLicenseID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("動画に書き出し").font(.title3).bold()

            let project = store.project
            let timeline = store.currentTimeline
            LabeledContent("シーン") { Text(store.currentScene.name) }
            LabeledContent("解像度") { Text("\(Int(project.resolution.width)) x \(Int(project.resolution.height))") }
            LabeledContent("フレームレート") { Text("\(Int(project.frameRate)) fps") }
            LabeledContent("長さ") { Text(String(format: "%.2fs", timeline.duration)) }

            if ProjectCreditBuilder.usesAquesTalkPlayer(project: project) {
                GroupBox("AquesTalk Playerの利用条件") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AquesTalkPlayerSupport.commercialUseNotice)
                            .font(.caption).foregroundStyle(.orange)
                        if aquesTalkPublicLicenseID.isEmpty {
                            Text("公開用ライセンスIDはクレジット画面から設定できます。秘密のライセンスキーは入力しないでください。")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Link("公式の利用条件を確認", destination: URL(string: AquesTalkPlayerSupport.officialPageURL)!)
                            .font(.caption)
                    }
                }
            }

            if exporter.isExporting {
                ProgressView(value: exporter.progress) {
                    Text("書き出し中… \(Int(exporter.progress * 100))%")
                }
            } else if didFinish {
                Label("書き出しが完了しました", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("閉じる") { dismiss() }
                    .disabled(exporter.isExporting)
                Button("書き出し先を選んで開始…") {
                    startExport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(exporter.isExporting || timeline.duration <= 0)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func startExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(store.documentDisplayName).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        errorMessage = nil
        didFinish = false
        let project = store.project
        let timeline = store.currentTimeline
        let assetsDirectory = store.assetsDirectory
        let imageProvider = store.imageProvider
        let videoFrameProvider = store.videoFrameProvider

        Task {
            do {
                try await exporter.export(
                    project: project,
                    timeline: timeline,
                    assetsDirectory: assetsDirectory,
                    imageProvider: imageProvider,
                    videoFrameProvider: videoFrameProvider,
                    to: url
                )
                didFinish = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
