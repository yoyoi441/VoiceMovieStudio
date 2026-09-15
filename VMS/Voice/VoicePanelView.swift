import SwiftUI
import VMSCore

/// TTS panel: type text, pick a VOICEVOX speaker + character, and insert voice + subtitle
/// + lip-synced character clips into the timeline in one step.
struct VoicePanelView: View {
    @Environment(ProjectStore.self) private var store

    @State private var text: String = "ゆっくりしていってね!"
    @State private var provider = "VOICEVOX"
    @State private var draftSettings = VoiceSettings()
    @State private var previewSound: NSSound?
    @State private var speakers: [VoiceSpeaker] = []
    @State private var selectedSpeakerID: Int?
    @State private var isLoadingSpeakers = false
    @State private var isSynthesizing = false
    @State private var isLaunching = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("音声連携", selection: $provider) {
                Text("VOICEVOX").tag("VOICEVOX")
                Text("A.I.VOICE2").tag("A.I.VOICE2")
                Text("SofTalk").tag(SofTalkSupport.providerID)
            }.pickerStyle(.segmented).disabled(isSynthesizing)
            characterPicker.disabled(isSynthesizing || store.aiv2Catalog.isBusy)

            if provider == SofTalkSupport.providerID {
                SofTalkPanel(characterID: $selectedCharacterID).id(provider)
            } else if provider != "VOICEVOX" {
                ExternalVoicePanel(provider: provider, characterID: $selectedCharacterID).id(provider)
            } else {

            TextField("セリフを入力…", text: $text, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            HStack {
                VoiceStylePicker(speakers: speakers, selection: $selectedSpeakerID)
            }.disabled(isSynthesizing)

            DisclosureGroup("抑揚・話速などの調整") {
                VoiceDraftControls(settings: $draftSettings)
                Button("選択キャラクターの音声初期値に保存") {
                    guard let id = selectedCharacterID,
                          let index = store.project.characters.firstIndex(where: { $0.id == id }) else { return }
                    store.beginUndoableChange()
                    store.project.characters[index].defaultVoiceSettings = draftSettings.validatedForVoiceVox()
                    store.project.characters[index].defaultSpeakerID = selectedSpeakerID
                    store.project.characters[index].voiceProvider = "VOICEVOX"
                    store.project.characters[index].voiceLibrary = speakers.first { $0.id == selectedSpeakerID }?.name ?? ""
                    store.project.characters[index].voiceStyle = speakers.first { $0.id == selectedSpeakerID }?.styleName ?? ""
                    statusMessage = "音声初期値を保存しました。"
                }.disabled(selectedCharacterID == nil || selectedSpeakerID == nil)
            }.disabled(isSynthesizing)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(3)
            }

            HStack {
                Button {
                    Task { await launchAndConnect() }
                } label: {
                    if isLaunching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("VOICEVOXを起動", systemImage: "power")
                    }
                }
                .disabled(isLaunching || isLoadingSpeakers)

                Button {
                    Task { await loadSpeakers() }
                } label: {
                    if isLoadingSpeakers {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("VOICEVOXに接続", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isLoadingSpeakers || isLaunching)

                Spacer()

                Button("この設定で試聴") {
                    Task { await audition() }
                }.disabled(isSynthesizing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedSpeakerID == nil)

                Button {
                    Task { await synthesizeAndInsert() }
                } label: {
                    if isSynthesizing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("生成してタイムラインに追加", systemImage: "waveform.badge.plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSynthesizing || text.isEmpty || selectedSpeakerID == nil)
            }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .task { await loadSpeakers() }
        .onChange(of: selectedVoicePreset) { _, _ in applyVoicePreset() }
        .onChange(of: provider) { _, _ in previewSound?.stop() }
        .onDisappear { previewSound?.stop() }
    }

    private var speakerPicker: some View {
        Picker("話者", selection: $selectedSpeakerID) {
            Text("未選択").tag(Int?.none)
            ForEach(speakers) { speaker in
                Text("\(speaker.name) (\(speaker.styleName))").tag(Int?.some(speaker.id))
            }
        }
        .frame(maxWidth: 220)
    }

    @State private var selectedCharacterID: UUID?
    private var selectedVoicePreset: CharacterVoicePreset? {
        selectedCharacterID.flatMap { store.project.character(withID: $0) }.map(CharacterVoicePreset.init)
    }

    private func applyVoicePreset() {
        guard let assignment = selectedVoicePreset else { return }
        guard ["VOICEVOX", "A.I.VOICE2", SofTalkSupport.providerID].contains(assignment.provider) else { return }
        provider = assignment.provider
        if assignment.provider == "VOICEVOX" {
            draftSettings = assignment.settings.validatedForVoiceVox()
            selectedSpeakerID = assignment.resolveVoiceVox(in: speakers)?.id
            statusMessage = selectedSpeakerID == nil ? "プリセットの話者・スタイルが未確認です。接続後に確認してください。" : "キャラクターの音声プリセットを適用しました。"
        }
    }

    private var characterPicker: some View {
        Picker("キャラクター", selection: $selectedCharacterID) {
            Text("なし(音声+字幕のみ)").tag(UUID?.none)
            ForEach(store.project.characters) { character in
                Text(character.name).tag(UUID?.some(character.id))
            }
        }
        .frame(maxWidth: 220)
    }

    private func loadSpeakers() async {
        isLoadingSpeakers = true
        errorMessage = nil
        defer { isLoadingSpeakers = false }
        do {
            speakers = try await store.voiceEngine.availableSpeakers()
            if !speakers.contains(where: { $0.id == selectedSpeakerID }) {
                selectedSpeakerID = speakers.first?.id
            }
            statusMessage = nil
            applyVoicePreset()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Launches the VOICEVOX app (if it's not already running) and keeps retrying the
    /// speaker list until its local server comes up — VOICEVOX takes a few seconds to
    /// start, so a single connect attempt right after launching would usually fail.
    private func launchAndConnect() async {
        errorMessage = nil
        do {
            try VoiceVoxLauncher.launch()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isLaunching = true
        defer {
            isLaunching = false
            statusMessage = nil
        }

        for attempt in 1...30 {
            statusMessage = "VOICEVOXの起動を待っています…(\(attempt)/30)"
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let fetched = try? await store.voiceEngine.availableSpeakers(), !fetched.isEmpty {
                speakers = fetched
                if selectedSpeakerID == nil {
                    selectedSpeakerID = fetched.first?.id
                }
                applyVoicePreset()
                return
            }
        }
        errorMessage = "VOICEVOXの起動を確認できませんでした。起動後に「VOICEVOXに接続」を押してください。"
    }

    private func synthesizeAndInsert() async {
        guard let speakerID = selectedSpeakerID else { return }
        isSynthesizing = true
        errorMessage = nil
        defer { isSynthesizing = false }
        let projectID = store.project.id
        let sceneID = store.currentSceneID
        let assets = store.assetsDirectory
        do {
            let character = selectedCharacterID.flatMap { id in store.project.character(withID: id) }
            let settings = draftSettings.validatedForVoiceVox()
            var result = try await TTSImportService.importSpeech(
                text: text,
                speakerID: speakerID,
                characterID: selectedCharacterID,
                startTime: store.playhead,
                engine: store.voiceEngine,
                assetsDirectory: store.assetsDirectory,
                settings: settings,
                mouthSpeed: character?.defaultMouthSpeed ?? 1.0
            )
            guard store.project.id == projectID, store.currentSceneID == sceneID,
                  store.assetsDirectory == assets else {
                errorMessage = "プロジェクト・シーンが変更されたため追加しませんでした。"
                return
            }
            if var characterClip = result.characterClip {
                characterClip.effects.flipHorizontal = character?.defaultFlipHorizontal ?? false
                result.characterClip = characterClip
            }
            store.insert(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func audition() async {
        guard let speakerID = selectedSpeakerID else { return }
        isSynthesizing = true
        errorMessage = nil
        previewSound?.stop()
        defer { isSynthesizing = false }
        do {
            let speech = try await store.voiceEngine.synthesize(
                text: text, speakerID: speakerID, settings: draftSettings.validatedForVoiceVox())
            guard let sound = NSSound(data: speech.audioData) else {
                errorMessage = "試聴音声を読み込めませんでした。"
                return
            }
            previewSound = sound
            sound.play()
        } catch { errorMessage = error.localizedDescription }
    }
}
