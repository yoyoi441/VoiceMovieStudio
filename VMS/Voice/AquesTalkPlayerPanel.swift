import AppKit
import SwiftUI
import VMSCore

struct AquesTalkPlayerPanel: View {
    @Environment(ProjectStore.self) private var store
    @Binding var characterID: UUID?
    @AppStorage(AquesTalkPlayerSettings.licenseAcknowledgedKey) private var licenseAcknowledged = false

    @State private var text = ""
    @State private var presetName = ""
    @State private var installation: AquesTalkPlayerInstallation?
    @State private var busy = false
    @State private var message: String?
    @State private var previewSound: NSSound?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("AquesTalk Playerを起動") { Task { await launch() } }
                    .disabled(installation == nil || busy)
                Button("アプリを選択…") { selectApplication() }
                    .disabled(busy)
                Link("公式ダウンロード", destination: URL(string: AquesTalkPlayerSupport.officialPageURL)!)
                Spacer()
                Text(installation.map { "検出済み v\($0.version)" } ?? "未検出")
                    .font(.caption)
                    .foregroundStyle(installation == nil ? Color.orange : Color.secondary)
            }

            TextField("プリセット名（空欄はPlayerで最後に選択したもの）", text: $presetName)
                .textFieldStyle(.roundedBorder)
            TextField("セリフを入力…", text: $text, axis: .vertical)
                .lineLimit(1...3)

            GroupBox("利用条件") {
                VStack(alignment: .leading, spacing: 5) {
                    Text(AquesTalkPlayerSupport.commercialUseNotice)
                        .font(.caption)
                    Toggle("公式の利用条件を確認しました", isOn: $licenseAcknowledged)
                    HStack {
                        Link("利用条件を確認", destination: URL(string: AquesTalkPlayerSupport.officialPageURL)!)
                        Link("使用ライセンス", destination: URL(string: AquesTalkPlayerSupport.licenseStoreURL)!)
                    }
                    .font(.caption)
                    Text("ライセンスキーはAquesTalk Player側で設定します。VMSはキーを保存・表示・プロジェクトへ記録しません。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("選択キャラクターの音声初期値に保存") { saveCharacterDefaults() }
                    .disabled(characterID == nil || busy)
                Spacer()
                Button("この設定で試聴") { Task { await audition() } }
                    .disabled(!canGenerate || busy)
                Button {
                    Task { await synthesizeAndInsert() }
                } label: {
                    if busy { ProgressView().controlSize(.small) }
                    else { Label("生成してタイムラインに追加", systemImage: "waveform.badge.plus") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGenerate || busy)
            }

            if let message { Text(message).font(.caption).textSelection(.enabled) }
            Text("プリセットはAquesTalk Playerで作成・調整します。VMSは公式コマンドでWAVを書き出し、字幕と音量ベースの口パクを追加します。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { refreshInstallation(); applyCharacterDefaults() }
        .onChange(of: characterID) { _, _ in applyCharacterDefaults() }
        .onDisappear { previewSound?.stop() }
    }

    private var canGenerate: Bool {
        installation != nil
            && licenseAcknowledged
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func refreshInstallation() {
        installation = AquesTalkPlayerService.installation()
    }

    private func selectApplication() {
        if let selected = AquesTalkPlayerService.selectApplication() {
            installation = selected
            message = "AquesTalk Playerを登録しました。"
        } else {
            refreshInstallation()
            message = "アプリの選択を変更しませんでした。"
        }
    }

    private func launch() async {
        do {
            try await AquesTalkPlayerService.launch()
            message = "AquesTalk Playerを起動しました。プリセットを編集できます。"
        } catch { message = error.localizedDescription }
    }

    private func applyCharacterDefaults() {
        guard let character = characterID.flatMap({ store.project.character(withID: $0) }),
              character.voiceProvider == AquesTalkPlayerSupport.providerID else { return }
        presetName = character.voiceLibrary
    }

    private func saveCharacterDefaults() {
        guard let characterID,
              let index = store.project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        store.beginUndoableChange()
        store.project.characters[index].voiceProvider = AquesTalkPlayerSupport.providerID
        store.project.characters[index].voiceLibrary = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        store.project.characters[index].voiceStyle = ""
        store.project.characters[index].defaultSpeakerID = nil
        store.project.characters[index].defaultVoiceSettings = VoiceSettings()
        message = presetName.isEmpty
            ? "Playerで最後に選択したプリセットを使う設定で保存しました。"
            : "プリセット「\(presetName)」を保存しました。"
    }

    private func audition() async {
        busy = true
        defer { busy = false }
        do {
            let result = try await AquesTalkPlayerService.speech(
                text: text, presetName: presetName, mouthSpeed: 1
            )
            guard let sound = NSSound(data: result.speech.audioData) else {
                throw AquesTalkPlayerError.emptyAudio
            }
            previewSound?.stop()
            previewSound = sound
            sound.play()
            message = "AquesTalk Playerの生成音声を試聴しています。"
        } catch { message = error.localizedDescription }
    }

    private func synthesizeAndInsert() async {
        busy = true
        defer { busy = false }
        let projectID = store.project.id
        let sceneID = store.currentSceneID
        let directory = store.assetsDirectory
        let character = characterID.flatMap { store.project.character(withID: $0) }
        do {
            let result = try await AquesTalkPlayerService.importSpeech(
                text: text,
                presetName: presetName,
                character: character,
                startTime: store.playhead,
                assetsDirectory: directory
            )
            guard store.project.id == projectID,
                  store.currentSceneID == sceneID,
                  store.assetsDirectory == directory else {
                message = "編集中のプロジェクト・シーンが変わったため追加しませんでした。"
                return
            }
            store.insert(result)
            message = "AquesTalk Playerで生成し、音声・字幕・口パクを追加しました。"
        } catch { message = "生成に失敗しました：\(error.localizedDescription)" }
    }
}
