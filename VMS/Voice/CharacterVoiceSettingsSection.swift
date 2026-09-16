import SwiftUI
import VMSCore

struct CharacterVoiceSettingsSection: View {
    @Environment(ProjectStore.self) private var store
    let character: Character
    @State private var speakers: [VoiceSpeaker] = []
    @State private var message = ""
    @State private var loading = false
    @State private var draftName = ""
    @State private var draftStyle = ""
    @State private var draftSettings = VoiceSettings()
    @State private var aquesTalkInstallation: AquesTalkPlayerInstallation?
    @AppStorage(AquesTalkPlayerSettings.licenseAcknowledgedKey) private var aquesTalkLicenseAcknowledged = false

    var body: some View {
        PropertySection("音声ソフト・話者") {
            Picker("使用ソフト", selection: stringBinding(\.voiceProvider)) {
                Text("未指定").tag("")
                Text("VOICEVOX").tag("VOICEVOX")
                Text("A.I.VOICE2").tag("A.I.VOICE2")
                Text("AquesTalk Player").tag(AquesTalkPlayerSupport.providerID)
                Text("Mac音声").tag(MacSystemVoiceSupport.providerID)
                if !["", "VOICEVOX", "A.I.VOICE2", AquesTalkPlayerSupport.providerID, MacSystemVoiceSupport.providerID]
                    .contains(character.voiceProvider) {
                    Text("保存済み：\(character.voiceProvider)").tag(character.voiceProvider)
                }
            }
            if character.voiceProvider == "VOICEVOX" {
                Button(loading ? "読み取り中…" : "VOICEVOXから話者を読み取る") {
                    Task { await loadVoiceVox() }
                }.disabled(loading)
                VoiceStylePicker(speakers: speakers, selection: Binding(
                    get: { CharacterVoicePreset(character: character).resolveVoiceVox(in: speakers)?.id },
                    set: { id in
                        guard let speaker = speakers.first(where: { $0.id == id }) else { return }
                        edit {
                            $0.defaultSpeakerID = speaker.id
                            $0.voiceLibrary = speaker.name
                            $0.voiceStyle = speaker.styleName
                        }
                    }
                ))
                DisclosureGroup("抑揚・話速などの初期値") {
                    VoiceDraftControls(settings: $draftSettings)
                    Button("音声初期値を保存") { saveSettings() }
                }
            } else if character.voiceProvider == "A.I.VOICE2" {
                Button("A.I.VOICE2を起動して話者を読む") {
                    Task { await store.aiv2Catalog.launchAndRead(preferredName: character.voiceLibrary) }
                }.disabled(store.aiv2Catalog.isBusy)
                Button("開いている一覧を再読み取り") {
                    store.aiv2Catalog.refresh(preferredName: character.voiceLibrary)
                }.disabled(store.aiv2Catalog.isBusy)
                Picker("読み取った話者", selection: stringBinding(\.voiceLibrary)) {
                    Text("未指定").tag("")
                    ForEach(store.aiv2Catalog.names, id: \.self) { Text($0).tag($0) }
                    if !character.voiceLibrary.isEmpty && !store.aiv2Catalog.names.contains(character.voiceLibrary) {
                        Text("保存済み：\(character.voiceLibrary)（未確認）").tag(character.voiceLibrary)
                    }
                }
                DisclosureGroup("抑揚・話速・高さ・感情スタイル") {
                    AIVoice2DraftControls(settings: $draftSettings, styleNames: aiv2StyleChoices)
                    Button("音声初期値を保存") { saveSettings() }
                }
                Text(store.aiv2Catalog.status).font(.caption).foregroundStyle(.secondary)
            } else if character.voiceProvider == AquesTalkPlayerSupport.providerID {
                HStack {
                    Button("AquesTalk Playerを起動") {
                        Task {
                            do { try await AquesTalkPlayerService.launch() }
                            catch { message = error.localizedDescription }
                        }
                    }
                    .disabled(aquesTalkInstallation == nil)
                    Button("アプリを選択…") {
                        if let selected = AquesTalkPlayerService.selectApplication() {
                            aquesTalkInstallation = selected
                        }
                    }
                    Link("公式サイト", destination: URL(string: AquesTalkPlayerSupport.officialPageURL)!)
                }
                Text(aquesTalkInstallation.map { "検出済み v\($0.version)" } ?? "AquesTalk Playerは未検出です。")
                    .font(.caption)
                    .foregroundStyle(aquesTalkInstallation == nil ? Color.orange : Color.secondary)
                TextField("プリセット名（空欄はPlayerの最後の設定）", text: stringBinding(\.voiceLibrary))
                Text(AquesTalkPlayerSupport.commercialUseNotice)
                    .font(.caption).foregroundStyle(.orange)
                Toggle("公式の利用条件を確認しました", isOn: $aquesTalkLicenseAcknowledged)
                HStack {
                    Link("利用条件", destination: URL(string: AquesTalkPlayerSupport.officialPageURL)!)
                    Link("使用ライセンス", destination: URL(string: AquesTalkPlayerSupport.licenseStoreURL)!)
                }.font(.caption)
                Text("ライセンスキーはAquesTalk Player側で設定し、VMSには入力しません。")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if character.voiceProvider == MacSystemVoiceSupport.providerID {
                HStack {
                    Button("霊夢向け") { applyMacProfile(.reimu) }
                    Button("魔理沙向け") { applyMacProfile(.marisa) }
                }
                Picker("Macの日本語音声", selection: macVoiceBinding) {
                    if MacSystemVoiceCatalog.japaneseVoices.isEmpty {
                        Text("日本語音声が見つかりません").tag("")
                    }
                    ForEach(MacSystemVoiceCatalog.japaneseVoices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }
                DisclosureGroup("音量・話速・高さの初期値") {
                    MacSystemVoiceDraftControls(settings: $draftSettings)
                    Button("音声初期値を保存") { saveSettings() }
                }
                Text("Mac内の日本語音声だけで生成します。霊夢向け・魔理沙向けは初期候補なので、試聴して好きな声へ変更できます。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            LabeledContent("保存中の話者", value: character.voiceLibrary.isEmpty ? "未指定" : character.voiceLibrary)
            LabeledContent("保存中のスタイル", value: character.voiceStyle.isEmpty ? "未指定" : character.voiceStyle)
            DisclosureGroup("話者名を手入力（未確認として保存）") {
                TextField("製品側の正確な話者名", text: $draftName)
                TextField("スタイル名（任意）", text: $draftStyle)
                Button("名前を保存") {
                    edit {
                        $0.voiceLibrary = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        $0.voiceStyle = draftStyle.trimmingCharacters(in: .whitespacesAndNewlines)
                        $0.defaultSpeakerID = nil
                    }
                }
                Text("素材名から推測しません。未検出の話者は自動選択・合成しません。").font(.caption2)
            }
            if !message.isEmpty { Text(message).font(.caption) }
            Text("この指定と抑揚・感情設定は下の「キャラクタープリセット」にも保存され、音声パネルの直接生成へ反映されます。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: character.voiceLibrary, initial: true) { _, value in draftName = value }
        .onChange(of: character.voiceStyle, initial: true) { _, value in draftStyle = value }
        .onChange(of: character.defaultVoiceSettings, initial: true) { _, value in
            if character.voiceProvider == "A.I.VOICE2" {
                draftSettings = value.validatedForAIVoice2()
            } else if character.voiceProvider == MacSystemVoiceSupport.providerID {
                draftSettings = value.validatedForMacSystemVoice()
            } else {
                draftSettings = value.validatedForVoiceVox()
            }
        }
        .onAppear { aquesTalkInstallation = AquesTalkPlayerService.installation() }
    }

    private func edit(_ change: (inout Character) -> Void) {
        guard let index = store.project.characters.firstIndex(where: { $0.id == character.id }) else { return }
        store.beginUndoableChange()
        change(&store.project.characters[index])
    }
    private func stringBinding(_ key: WritableKeyPath<Character, String>) -> Binding<String> {
        Binding(get: { character[keyPath: key] }, set: { value in
            edit {
                $0[keyPath: key] = value
                if key == \.voiceProvider {
                    $0.voiceLibrary = ""
                    $0.voiceStyle = ""
                    $0.defaultSpeakerID = nil
                    if value == "A.I.VOICE2" { $0.defaultVoiceSettings = .aIVoice2Default }
                    else if value == AquesTalkPlayerSupport.providerID {
                        $0.defaultVoiceSettings = VoiceSettings()
                    }
                    else if value == MacSystemVoiceSupport.providerID {
                        $0.defaultVoiceSettings = MacSystemVoiceSupport.BuiltInProfile.reimu.defaultSettings
                        if let voice = MacSystemVoiceCatalog.voice(for: .reimu) {
                            $0.voiceLibrary = voice.id
                            $0.voiceStyle = voice.name
                        }
                    }
                    else { $0.defaultVoiceSettings = VoiceSettings() }
                }
            }
            if key == \.voiceProvider {
                if value == "A.I.VOICE2" { draftSettings = .aIVoice2Default }
                else if value == AquesTalkPlayerSupport.providerID { draftSettings = VoiceSettings() }
                else if value == MacSystemVoiceSupport.providerID {
                    draftSettings = MacSystemVoiceSupport.BuiltInProfile.reimu.defaultSettings
                }
                else { draftSettings = VoiceSettings() }
            }
        })
    }

    private var aiv2StyleChoices: [String] {
        let saved = draftSettings.styleWeights?.keys.map { $0 } ?? []
        return Array(Set(store.aiv2Catalog.styleNames + saved)).sorted()
    }

    private func saveSettings() {
        edit { updated in
            if updated.voiceProvider == "A.I.VOICE2" {
                updated.defaultVoiceSettings = draftSettings.validatedForAIVoice2(
                    availableStyleNames: store.aiv2Catalog.styleNames.isEmpty
                        ? nil : Set(store.aiv2Catalog.styleNames)
                )
                updated.voiceStyle = updated.defaultVoiceSettings.styleWeights?
                    .max(by: { $0.value < $1.value })?.key ?? ""
            } else if updated.voiceProvider == MacSystemVoiceSupport.providerID {
                updated.defaultVoiceSettings = draftSettings.validatedForMacSystemVoice()
                updated.voiceStyle = MacSystemVoiceCatalog.voice(identifier: updated.voiceLibrary)?.name ?? ""
                updated.defaultSpeakerID = nil
            } else if updated.voiceProvider == AquesTalkPlayerSupport.providerID {
                updated.defaultVoiceSettings = VoiceSettings()
                updated.voiceStyle = ""
                updated.defaultSpeakerID = nil
            } else {
                updated.defaultVoiceSettings = draftSettings.validatedForVoiceVox()
            }
        }
        message = "音声初期値を保存しました。"
    }
    private func loadVoiceVox() async {
        loading = true
        defer { loading = false }
        do {
            speakers = try await store.voiceEngine.availableSpeakers()
            message = "\(speakers.count)件の話者スタイルを読み取りました。"
        } catch { message = error.localizedDescription }
    }

    private var macVoiceBinding: Binding<String> {
        Binding(
            get: { character.voiceLibrary },
            set: { identifier in
                edit {
                    $0.voiceLibrary = identifier
                    $0.voiceStyle = MacSystemVoiceCatalog.voice(identifier: identifier)?.name ?? ""
                    $0.defaultSpeakerID = nil
                }
            }
        )
    }

    private func applyMacProfile(_ profile: MacSystemVoiceSupport.BuiltInProfile) {
        guard let voice = MacSystemVoiceCatalog.voice(for: profile) else {
            message = "利用できる日本語音声がありません。"
            return
        }
        draftSettings = profile.defaultSettings.validatedForMacSystemVoice()
        edit {
            $0.voiceProvider = MacSystemVoiceSupport.providerID
            $0.voiceLibrary = voice.id
            $0.voiceStyle = voice.name
            $0.defaultSpeakerID = nil
            $0.defaultVoiceSettings = draftSettings
        }
        message = "\(profile.displayName)に\(voice.name)を設定しました。"
    }
}
