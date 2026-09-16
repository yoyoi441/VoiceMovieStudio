import AppKit
import SwiftUI
import VMSCore

struct MacSystemVoicePanel: View {
    @Environment(ProjectStore.self) private var store
    @Binding var characterID: UUID?
    @State private var text = ""
    @State private var selectedVoiceID = ""
    @State private var settings = VoiceSettings.macSystemDefault
    @State private var busy = false
    @State private var message: String?
    @State private var previewSound: NSSound?

    private var voices: [MacSystemVoiceOption] { MacSystemVoiceCatalog.japaneseVoices }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("霊夢向け") { applyProfile(.reimu) }
                Button("魔理沙向け") { applyProfile(.marisa) }
                Text("Mac内蔵の日本語音声を使用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Macの日本語音声", selection: $selectedVoiceID) {
                if voices.isEmpty { Text("日本語音声が見つかりません").tag("") }
                ForEach(voices) { voice in
                    Text(voice.displayName).tag(voice.id)
                }
            }

            TextField("セリフを入力…", text: $text, axis: .vertical)
                .lineLimit(1...3)

            DisclosureGroup("音量・話速・高さ") {
                MacSystemVoiceDraftControls(settings: $settings)
                Button("選択キャラクターの音声初期値に保存") { saveCharacterDefaults() }
                    .disabled(characterID == nil || selectedVoiceID.isEmpty || busy)
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
            if voices.isEmpty {
                Text("システム設定で日本語音声を追加してから、アプリを開き直してください。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("霊夢向け・魔理沙向けは声質の初期候補です。Mac標準音声のため、特定の市販音源と同じ声ではありません。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: characterID, initial: true) { _, _ in applyCharacterDefaults() }
        .onDisappear { previewSound?.stop() }
    }

    private var canGenerate: Bool {
        !selectedVoiceID.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyProfile(_ profile: MacSystemVoiceSupport.BuiltInProfile) {
        guard let voice = MacSystemVoiceCatalog.voice(for: profile) else {
            message = "利用できる日本語音声がありません。"
            return
        }
        selectedVoiceID = voice.id
        settings = profile.defaultSettings.validatedForMacSystemVoice()
        message = "\(profile.displayName)に\(voice.name)を選びました。試聴して調整できます。"
    }

    private func applyCharacterDefaults() {
        guard let character = characterID.flatMap({ store.project.character(withID: $0) }),
              character.voiceProvider == MacSystemVoiceSupport.providerID,
              MacSystemVoiceCatalog.voice(identifier: character.voiceLibrary) != nil else {
            if selectedVoiceID.isEmpty {
                applyProfile(.reimu)
                message = nil
            }
            return
        }
        selectedVoiceID = character.voiceLibrary
        settings = character.defaultVoiceSettings.validatedForMacSystemVoice()
    }

    private func saveCharacterDefaults() {
        guard let characterID,
              let index = store.project.characters.firstIndex(where: { $0.id == characterID }),
              let voice = MacSystemVoiceCatalog.voice(identifier: selectedVoiceID) else { return }
        store.beginUndoableChange()
        store.project.characters[index].voiceProvider = MacSystemVoiceSupport.providerID
        store.project.characters[index].voiceLibrary = voice.id
        store.project.characters[index].voiceStyle = voice.name
        store.project.characters[index].defaultSpeakerID = nil
        store.project.characters[index].defaultVoiceSettings = settings.validatedForMacSystemVoice()
        message = "\(voice.name)を音声初期値として保存しました。"
    }

    private func audition() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await MacSystemVoiceSynthesisService.speech(
                text: text,
                voiceIdentifier: selectedVoiceID,
                settings: settings,
                mouthSpeed: 1
            )
            guard let sound = NSSound(data: result.speech.audioData) else {
                throw MacSystemVoiceError.emptyAudio
            }
            previewSound?.stop()
            previewSound = sound
            sound.play()
            message = "\(MacSystemVoiceCatalog.voice(identifier: selectedVoiceID)?.name ?? "Mac音声")で試聴しています。"
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
        do {
            let result = try await MacSystemVoiceSynthesisService.importSpeech(
                text: text,
                voiceIdentifier: selectedVoiceID,
                settings: settings,
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
            message = "Mac内で音声を生成し、音声・字幕・口パクを追加しました。"
        } catch { message = "生成に失敗しました：\(error.localizedDescription)" }
    }
}

struct MacSystemVoiceDraftControls: View {
    @Binding var settings: VoiceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("音量", value: $settings.volume, range: 0...1)
            row("話速", value: $settings.speed, range: 0.5...2)
            row("高さ", value: $settings.pitch, range: 0.5...2)
            Text("音量・話速・高さはMac標準の音声合成へ直接反映されます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .accessibilityLabel(label)
        }
    }
}
