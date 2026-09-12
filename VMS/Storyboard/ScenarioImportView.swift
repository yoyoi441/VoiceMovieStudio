import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VMSCore

struct ScenarioImportView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let existingCardCount: Int
    let conflict: Bool
    let onImport: ([StoryboardCard], Bool) -> Void

    @State private var sourceText = ""
    @State private var sourceName = "直接入力"
    @State private var sourceFormat: ScenarioDocumentFormat = .text
    @State private var defaultSpeaker: UUID?
    @State private var lines: [ScenarioDraftLine] = []
    @State private var replaceExisting = false
    @State private var parsingError: String?
    @State private var ai = RemoteAIController()
    @State private var aiInstruction = "会話の流れが分かりやすくなるよう、自然な表示時間と左右配置を提案してください"
    @State private var aiSummary = ""

    private var frameRate: Double { store.storyboard?.frameRate ?? store.newStoryboard().frameRate }
    private var unresolvedCount: Int { lines.count(where: \.needsSpeakerResolution) }
    private var exceedsLimit: Bool { !replaceExisting && existingCardCount + lines.count > 300 }

    var body: some View {
        @Bindable var ai = ai
        VStack(spacing: 0) {
            HStack {
                Label("シナリオを読み込む", systemImage: "doc.text.magnifyingglass")
                    .font(.title3).bold()
                Text(sourceName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("閉じる") { dismiss() }
            }
            .padding()
            Divider()
            HSplitView {
                sourcePanel.frame(minWidth: 320, idealWidth: 380, maxWidth: 460, maxHeight: .infinity, alignment: .top)
                reviewPanel.frame(minWidth: 600, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack {
                if conflict {
                    Label("タイムライン側の変更があるため反映できません", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if unresolvedCount > 0 {
                    Label("未確認の話者が\(unresolvedCount)件あります", systemImage: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.orange)
                } else if exceedsLimit {
                    Label("合計300コマを超えます", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text("\(lines.count)件を\(replaceExisting ? "置き換え" : "追加")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("既存コマを置き換える", isOn: $replaceExisting)
                    .toggleStyle(.checkbox)
                Button("確認した内容を反映") { apply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(lines.isEmpty || unresolvedCount > 0 || exceedsLimit || conflict || ai.isWorking)
            }
            .padding()
        }
        .frame(width: 1120, height: 760, alignment: .top)
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("TXT・CSV・JSONを選択…") { chooseFile() }
                Button("直接入力に戻す") {
                    sourceName = "直接入力"
                    sourceFormat = .text
                    sourceText = ""
                    lines = []
                    parsingError = nil
                }
            }
            Picker("名前がない行の話者", selection: $defaultSpeaker) {
                Text("なし（字幕のみ）").tag(UUID?.none)
                ForEach(store.project.characters) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            Text("TXTは「キャラクター名：セリフ」を1行ずつ入力します。CSV／JSONでは話者、セリフ、秒数も読み取れます。")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $sourceText)
                .font(.body.monospaced())
                .border(.gray.opacity(0.3))
                .frame(maxHeight: .infinity)
            if let parsingError {
                Label(parsingError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
            Button("読み込んで確認") { parseSource() }
                .buttonStyle(.borderedProminent)
                .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private var reviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            aiRecommendationPanel
            Divider()
            if lines.isEmpty {
                ContentUnavailableView(
                    "シナリオを読み込んでください",
                    systemImage: "text.page.badge.magnifyingglass",
                    description: Text("読み込み後、話者・長さ・配置を確認してから反映します。")
                )
            } else {
                List {
                    ForEach($lines) { $line in
                        scenarioRow(line: $line)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding()
    }

    private var aiRecommendationPanel: some View {
        @Bindable var ai = ai
        return GroupBox("おすすめの編集補助AI") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("実行場所", selection: Binding(
                        get: { ai.location },
                        set: { ai.selectLocation($0) }
                    )) {
                        ForEach(AIExecutionLocation.allCases) { location in
                            Label(location.title, systemImage: location.symbol).tag(location)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    TextField("AIへの追加指示", text: $aiInstruction)
                    Button("おすすめ配置をAIに依頼") { requestAIRecommendation() }
                        .disabled(lines.isEmpty || ai.isWorking)
                }
                Text("ボタンを押した場合だけ、セリフ本文と登録キャラクター名を選択中の「\(ai.location.title)」へ送ります。セリフ本文と順番は変更せず、話者候補・表示時間・左右配置だけを提案します。")
                    .font(.caption).foregroundStyle(.secondary)
                if ai.isWorking {
                    HStack {
                        ProgressView()
                        Text(ai.job?.message ?? "AIへ接続しています…")
                        Button("キャンセル") { ai.cancel() }
                    }
                    .font(.caption)
                }
                if let error = ai.errorMessage {
                    Text("\(error)　接続先とトークンは編集画面の「AI」で設定できます。")
                        .font(.caption).foregroundStyle(.red)
                } else if !aiSummary.isEmpty {
                    Text(aiSummary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }

    private func scenarioRow(line: Binding<ScenarioDraftLine>) -> some View {
        let current = line.wrappedValue
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("元\(current.sourceLine)行").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Picker("話者", selection: Binding(
                    get: { line.wrappedValue.speakerID },
                    set: { value in
                        line.wrappedValue.speakerID = value
                        line.wrappedValue.unresolvedSpeakerName = nil
                    }
                )) {
                    Text("なし（字幕のみ）").tag(UUID?.none)
                    ForEach(store.project.characters) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .labelsHidden()
                .frame(width: 180)
                TextField("秒", value: line.durationSeconds, format: .number.precision(.fractionLength(1)))
                    .frame(width: 58)
                Text("秒").font(.caption)
                Picker("配置", selection: line.placement) {
                    ForEach(ScenarioPlacementSuggestion.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                Spacer()
            }
            if let unresolved = current.unresolvedSpeakerName {
                Text("「\(unresolved)」は登録済みキャラクターと一致しません。話者を選択してください。")
                    .font(.caption).foregroundStyle(.orange)
            }
            TextField("セリフ", text: line.dialogue, axis: .vertical)
                .lineLimit(1...4)
            if let reason = current.recommendationReason, !reason.isEmpty {
                Label(reason, systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "シナリオを選択"
        panel.allowedContentTypes = ["txt", "md", "csv", "tsv", "json"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 2 * 1024 * 1024 else {
                throw ScenarioDocumentError.invalidFormat
            }
            let data = try Data(contentsOf: url)
            sourceFormat = .infer(fileExtension: url.pathExtension)
            sourceName = url.lastPathComponent
            sourceText = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .shiftJIS)
                ?? String(data: data, encoding: .utf16)
                ?? ""
            lines = try ScenarioDocumentParser.parse(
                data: data, format: sourceFormat, characters: store.project.characters,
                defaultSpeaker: defaultSpeaker
            )
            parsingError = nil
            aiSummary = ""
        } catch {
            parsingError = error.localizedDescription
            lines = []
        }
    }

    private func parseSource() {
        do {
            lines = try ScenarioDocumentParser.parse(
                data: Data(sourceText.utf8), format: sourceFormat,
                characters: store.project.characters, defaultSpeaker: defaultSpeaker
            )
            parsingError = nil
            aiSummary = ""
        } catch {
            parsingError = error.localizedDescription
            lines = []
        }
    }

    private func requestAIRecommendation() {
        let snapshot = lines
        Task {
            guard let plan = await ai.recommendStoryboard(
                lines: snapshot,
                characters: store.project.characters,
                instruction: aiInstruction
            ) else { return }
            guard lines == snapshot else {
                ai.errorMessage = "AI処理中にシナリオが変更されたため、配置案を反映しませんでした。"
                return
            }
            apply(plan)
        }
    }

    private func apply(_ plan: ScenarioAIPlan) {
        let characters = store.project.characters
        for suggestion in plan.suggestions where lines.indices.contains(suggestion.lineIndex) {
            var line = lines[suggestion.lineIndex]
            line.durationSeconds = min(30, max(0.5, suggestion.durationSeconds))
            line.placement = suggestion.placement
            line.recommendationReason = suggestion.reason
            if line.speakerID == nil, let name = suggestion.speakerName {
                let matches = characters.filter { $0.name == name }
                if matches.count == 1 {
                    line.speakerID = matches[0].id
                    line.unresolvedSpeakerName = nil
                }
            }
            lines[suggestion.lineIndex] = line
        }
        aiSummary = plan.summary
    }

    private func apply() {
        let cards = lines.map { $0.storyboardCard(frameRate: frameRate) }
        onImport(cards, replaceExisting)
    }
}
