import AppKit
import SwiftUI
import VMSCore

struct SofTalkPanel: View {
    @Environment(ProjectStore.self) private var store
    @Binding var characterID: UUID?
    @State private var connection = SofTalkConnectionController.shared
    @State private var text = ""
    @State private var selectedProfileID = SofTalkSupport.BuiltInProfile.reimu.rawValue
    @State private var settings = VoiceSettings.sofTalkDefault
    @State private var busy = false
    @State private var message: String?
    @State private var previewSound: NSSound?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup("Windows側のSofTalk連携") {
                TextField("接続先（https://…）", text: $connection.endpoint)
                    .onChange(of: connection.endpoint) { _, _ in connection.connectionSettingsChanged() }
                SecureField("接続トークン", text: $connection.tokenDraft)
                    .onChange(of: connection.tokenDraft) { _, _ in connection.connectionSettingsChanged() }
                HStack {
                    Button("接続を確認") { Task { await connection.connect() } }
                    Button("SofTalkを起動") { Task { await launch() } }
                        .disabled(connection.info == nil)
                    if connection.isWorking { ProgressView().controlSize(.small) }
                }
                Text(connection.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("SofTalk本体と音源は同梱しません。Windows側に付属ブリッジを設定し、Tailscale ServeなどのHTTPS経由で接続してください。")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Picker("話者プリセット", selection: $selectedProfileID) {
                ForEach(connection.profiles) { profile in
                    Text(profile.isConfigured ? profile.displayName : "\(profile.displayName)（未設定）")
                        .tag(profile.id)
                }
            }

            TextField("セリフを入力…", text: $text, axis: .vertical)
                .lineLimit(1...3)

            DisclosureGroup("音量・話速・高さ") {
                SofTalkDraftControls(settings: $settings)
                Button("選択キャラクターの音声初期値に保存") { saveCharacterDefaults() }
                    .disabled(characterID == nil || !selectedProfileIsConfigured || busy)
            }

            HStack {
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
            if !selectedProfileIsConfigured {
                Text("このプリセットは未設定です。Windows側のbridge-config.jsonで、利用中の音源に対応する引数を明示的に割り当ててください。")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .onChange(of: characterID, initial: true) { _, _ in applyCharacterDefaults() }
        .onDisappear { previewSound?.stop() }
    }

    private var selectedProfileIsConfigured: Bool {
        connection.profile(id: selectedProfileID)?.isConfigured == true
    }

    private var canGenerate: Bool {
        selectedProfileIsConfigured && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyCharacterDefaults() {
        guard let character = characterID.flatMap({ store.project.character(withID: $0) }),
              character.voiceProvider == SofTalkSupport.providerID else {
            settings = .sofTalkDefault
            return
        }
        selectedProfileID = character.voiceLibrary.isEmpty
            ? SofTalkSupport.BuiltInProfile.reimu.rawValue : character.voiceLibrary
        settings = character.defaultVoiceSettings.validatedForSofTalk()
    }

    private func saveCharacterDefaults() {
        guard let characterID,
              let index = store.project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        store.beginUndoableChange()
        store.project.characters[index].voiceProvider = SofTalkSupport.providerID
        store.project.characters[index].voiceLibrary = selectedProfileID
        store.project.characters[index].voiceStyle = SofTalkSupport.displayName(for: selectedProfileID)
        store.project.characters[index].defaultSpeakerID = nil
        store.project.characters[index].defaultVoiceSettings = settings.validatedForSofTalk()
        message = "「\(SofTalkSupport.displayName(for: selectedProfileID))」を音声初期値として保存しました。"
    }

    private func launch() async {
        do { try await connection.launch(); message = connection.message }
        catch { message = error.localizedDescription }
    }

    private func audition() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let data = try await connection.synthesize(
                text: text, profileID: selectedProfileID, settings: settings.validatedForSofTalk()
            )
            guard let sound = NSSound(data: data) else { throw SofTalkBridgeClient.ClientError.invalidAudio }
            previewSound?.stop()
            previewSound = sound
            sound.play()
            message = "\(SofTalkSupport.displayName(for: selectedProfileID))で試聴しています。"
        } catch { message = error.localizedDescription }
    }

    private func synthesizeAndInsert() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let projectID = store.project.id
        let sceneID = store.currentSceneID
        let directory = store.assetsDirectory
        let character = characterID.flatMap { store.project.character(withID: $0) }
        let safeSettings = settings.validatedForSofTalk()
        do {
            let result = try await SofTalkSynthesisService.importSpeech(
                text: text, profileID: selectedProfileID, settings: safeSettings,
                character: character, startTime: store.playhead, assetsDirectory: directory
            )
            guard store.project.id == projectID, store.currentSceneID == sceneID,
                  store.assetsDirectory == directory else {
                message = "編集中のプロジェクト・シーンが変わったため追加しませんでした。"
                return
            }
            store.insert(result)
            message = "SofTalkで生成し、音声・字幕・口パクを追加しました。"
        } catch { message = "生成に失敗しました：\(error.localizedDescription)" }
    }
}

struct SofTalkDraftControls: View {
    @Binding var settings: VoiceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("音量", value: $settings.volume, range: 0...2)
            row("話速", value: $settings.speed, range: 0.5...2)
            row("高さ", value: $settings.pitch, range: 0.5...2)
            Text("実際に反映できる項目はWindows側のブリッジ設定と選択音源に依存します。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520)
    }

    private func row(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack {
            Text(label).frame(width: 72, alignment: .leading)
            Slider(value: value, in: range, step: 0.01)
            TextField("", value: value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder).frame(width: 64).accessibilityLabel(label)
        }
    }
}
