import AppKit
import SwiftUI
import VMSCore

struct RemoteAIView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var controller = RemoteAIController()

    private var analyzableAssets: [MediaAsset] { store.project.mediaAssets.filter { $0.kind == .video || $0.kind == .audio } }

    var body: some View {
        @Bindable var controller = controller
        VStack(spacing: 0) {
            HStack {
                Label("AI編集支援", systemImage: "sparkles") .font(.title3).bold()
                Spacer()
                if let node = controller.node {
                    Label("\(controller.location.title)：\(node.name) 接続中", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else { Label("未接続", systemImage: "circle.dashed").foregroundColor(.secondary) }
                Button("閉じる") { dismiss() }
            }.padding()
            Divider()
            HSplitView {
                connectionPanel
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 350, maxHeight: .infinity, alignment: .top)
                workflowPanel
                    .frame(minWidth: 560, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 1000, height: 700, alignment: .top)
        .alert("AI処理エラー", isPresented: Binding(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })) {
            Button("OK") { controller.errorMessage = nil }
        } message: { Text(controller.errorMessage ?? "") }
        .onAppear { if controller.selectedAssetID == nil { controller.selectedAssetID = analyzableAssets.first?.id } }
    }

    private var connectionPanel: some View {
        @Bindable var controller = controller
        return Form {
            Section("実行場所") {
                Picker("実行場所", selection: Binding(
                    get: { controller.location },
                    set: { controller.selectLocation($0) }
                )) {
                    ForEach(AIExecutionLocation.allCases) { location in
                        Label(location.title, systemImage: location.symbol).tag(location)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(controller.isWorking)
                Text(locationDescription)
                    .font(.caption).foregroundColor(.secondary)
            }
            Section(controller.location == .local ? "このMacのAIノード" : "リモートMacのAIノード") {
                TextField("接続先", text: $controller.endpoint)
                    .onChange(of: controller.endpoint) { _, _ in controller.connectionSettingsChanged() }
                SecureField("接続トークン", text: $controller.tokenDraft)
                    .onChange(of: controller.tokenDraft) { _, _ in controller.connectionSettingsChanged() }
                if controller.location == .local {
                    Button("標準の接続先に戻す") { controller.restoreDefaultLocalEndpoint() }
                        .disabled(controller.isWorking || controller.endpoint == AIExecutionLocation.local.defaultEndpoint)
                }
                Button("接続を確認") { Task { await controller.connect() } }.disabled(controller.isWorking)
            }
            Section("接続先とトークンの確認方法") {
                if controller.location == .local {
                    Text("AIWorkerをこのMacへ導入すると、接続先は次の固定URLになります。")
                        .font(.caption).foregroundColor(.secondary)
                    copyableValue(title: "接続先", value: AIExecutionLocation.local.defaultEndpoint)
                    Text("接続トークンは、このMacのターミナルで次のコマンドを実行して確認します。")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("AIWorkerを入れた高性能なMacのターミナルで、次のコマンドを実行します。接続先には表示結果の https:// で始まるURLを入力してください。")
                        .font(.caption).foregroundColor(.secondary)
                    copyableValue(title: "接続先を確認", value: "/Applications/Tailscale.app/Contents/MacOS/Tailscale serve status")
                    Text("接続トークンも、AIWorkerを入れた高性能なMacで確認します。")
                        .font(.caption).foregroundColor(.secondary)
                }
                copyableValue(
                    title: "トークンを確認",
                    value: "cat \"$HOME/Library/Application Support/VoiceMovieStudioAIWorker/token\""
                )
                Text("ファイルが見つからない場合は、そのMacへAIWorkerがまだ導入されていません。同梱のAIWorker/install.shを実行してください。")
                    .font(.caption).foregroundColor(.secondary)
            }
            if let node = controller.node {
                Section("能力") {
                    LabeledContent("端末", value: node.name)
                    LabeledContent("処理装置", value: node.processor)
                    LabeledContent("メモリ", value: node.memoryGB > 0 ? "\(node.memoryGB) GB" : "不明")
                    ForEach(node.capabilities, id: \.self) { capability in Label(capabilityName(capability), systemImage: "checkmark") }
                }
                Section("言語モデル") {
                    Picker("モデル", selection: $controller.selectedModel) {
                        ForEach(node.models, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: controller.selectedModel) { _, _ in controller.saveSelectedModel() }
                }
            }
            Section("設定方法") {
                DisclosureGroup(controller.location == .local ? "このMacで動かす" : "別のMacで動かす") {
                    Text(setupInstructions)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            Section("安全性") {
                Text("接続先と選択モデルは実行場所ごとに保存します。トークンは別々のキーチェーン項目へ保存され、プロジェクトには入りません。リモートには信頼できるTailnet内の端末だけを登録してください。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.formStyle(.grouped)
    }

    private func copyableValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).bold()
            HStack(spacing: 6) {
                Text(value)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("コピー")
                .accessibilityLabel("\(title)をコピー")
            }
        }
    }

    private var locationDescription: String {
        switch controller.location {
        case .local:
            "編集しているMac自身で処理します。素材はネットワークへ送信されません。AIワーカーの導入が必要です。"
        case .remote:
            "母艦など別のMacへ解析用音声と文字起こしを送り、その端末の計算能力を使用します。"
        }
    }

    private var setupInstructions: String {
        switch controller.location {
        case .local:
            "1. このMacへAIワーカー、Ollama、Whisperを導入します。\n2. ワーカーを起動します。\n3. 接続先を http://127.0.0.1:8765 にします。\n4. ターミナルで cat \"$HOME/Library/Application Support/VoiceMovieStudioAIWorker/token\" を実行し、表示されたトークンを入力します。\n5. 「接続を確認」を押します。"
        case .remote:
            "1. 両方のMacを同じTailnetへ接続します。\n2. 高性能なMacへAIワーカー、Ollama、Whisperを導入します。\n3. Tailscale Serveが表示した https://端末名.ts.net/ を接続先へ入力します。\n4. 高性能なMacのターミナルで cat \"$HOME/Library/Application Support/VoiceMovieStudioAIWorker/token\" を実行し、表示されたトークンを入力します。\n5. 「接続を確認」を押します。"
        }
    }

    private var workflowPanel: some View {
        @Bindable var controller = controller
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("解析素材", selection: $controller.selectedAssetID) {
                    Text("選択してください").tag(UUID?.none)
                    ForEach(analyzableAssets) { Text($0.originalName).tag(Optional($0.id)) }
                }.frame(maxWidth: 420)
                Picker("言語", selection: $controller.language) { Text("日本語").tag("ja"); Text("自動").tag("auto"); Text("英語").tag("en") }.frame(width: 150)
                Button("文字起こし") { Task { await controller.transcribe(store: store) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.node?.capabilities.contains(.transcription) != true || controller.isWorking)
            }
            if let job = controller.job, controller.isWorking {
                HStack {
                    ProgressView(value: job.progress).frame(maxWidth: 360)
                    Text(job.message).font(.caption)
                    Button("キャンセル") { controller.cancel() }
                }
            }
            Divider()
            if let analysis = controller.analysis {
                HStack {
                    Text("文字起こし \(analysis.transcript.count)区間").font(.headline)
                    Spacer()
                    Button("字幕として追加") { store.addRemoteAISubtitles(analysis) }.disabled(analysis.transcript.isEmpty)
                }
                List(analysis.transcript.prefix(200)) { segment in
                    HStack(alignment: .top) {
                        Text(time(segment.start)).font(.caption.monospacedDigit()).foregroundColor(.secondary).frame(width: 64, alignment: .leading)
                        Text(segment.text).textSelection(.enabled)
                    }
                }.frame(minHeight: 180)
                HStack {
                    TextField("重要箇所への指示", text: $controller.instruction)
                    Button("重要箇所を分析") { Task { await controller.analyzeHighlights(store: store) } }
                        .disabled(controller.isWorking || analysis.transcript.isEmpty || controller.node?.capabilities.contains(.highlights) != true)
                }
                if !analysis.summary.isEmpty { Text(analysis.summary).font(.callout).padding(8).background(Color.blue.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 6)) }
                if !analysis.highlights.isEmpty {
                    List {
                        ForEach(Array(analysis.highlights.enumerated()), id: \.element.id) { index, candidate in
                            Toggle(isOn: Binding(get: { controller.analysis?.highlights[index].isSelected ?? false }, set: { controller.analysis?.highlights[index].isSelected = $0 })) {
                                VStack(alignment: .leading) {
                                    Text("\(candidate.title)　\(time(candidate.start))〜\(time(candidate.end))　重要度 \(Int(candidate.score * 100))%")
                                    Text(candidate.reason).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }.frame(minHeight: 140)
                    HStack { Spacer(); Button("選択した候補からクリップを作成") { if let value = controller.analysis { store.createRemoteAIClips(value) } }.buttonStyle(.borderedProminent) }
                }
            } else {
                ContentUnavailableView("素材を選んで文字起こしを開始", systemImage: "waveform.badge.magnifyingglass", description: Text("処理は選択中の「\(controller.location.title)」で実行されます。"))
            }
        }.padding()
    }

    private func capabilityName(_ value: RemoteAICapability) -> String {
        switch value { case .transcription: return "文字起こし"; case .highlights: return "重要箇所抽出"; case .clipPlanning: return "クリップ構成"; case .vision: return "映像理解" }
    }
    private func time(_ value: Double) -> String { String(format: "%02d:%02d", Int(value) / 60, Int(value) % 60) }
}
