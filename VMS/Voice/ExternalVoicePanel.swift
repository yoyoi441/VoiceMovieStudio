import SwiftUI
import UniformTypeIdentifiers
import VMSCore

/// Explicit file import plus a non-recursive inbox. Watching detects, never silently edits a project.
struct ExternalVoicePanel: View {
    @Environment(ProjectStore.self) private var store
    let provider: String
    @State private var text = ""
    @Binding var characterID: UUID?
    @State private var busy = false
    @State private var message: String?
    @State private var selectedSpeakerName = ""
    @State private var draftSettings = VoiceSettings.aIVoice2Default
    @State private var folder: URL?
    @State private var known: [URL: String] = [:]
    @State private var candidates: [URL: String] = [:]
    @State private var pending: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("A.I.VOICE2を起動して話者を読む") {
                    Task {
                        await store.aiv2Catalog.launchAndRead(preferredName: preferredSpeaker)
                    }
                }.disabled(store.aiv2Catalog.isBusy)
                Button("一覧を再読み取り") { store.aiv2Catalog.refresh(preferredName: preferredSpeaker) }
                    .disabled(store.aiv2Catalog.isBusy)
                Button("アプリを選び直す…") { Task { await launchEditor(selectAgain: true) } }
            }.disabled(busy)
            Text(store.aiv2Catalog.status).font(.caption).foregroundStyle(.secondary)

            Picker("話者", selection: $selectedSpeakerName) {
                Text("未選択").tag("")
                ForEach(speakerChoices, id: \.self) { Text($0).tag($0) }
            }
            .disabled(busy)

            TextField("セリフを入力…", text: $text, axis: .vertical)
                .lineLimit(1...3)

            DisclosureGroup("抑揚・話速・高さ・感情スタイル") {
                AIVoice2DraftControls(
                    settings: $draftSettings,
                    styleNames: styleChoices
                )
                Button("選択キャラクターの音声初期値に保存") { saveCharacterDefaults() }
                    .disabled(characterID == nil || selectedSpeakerName.isEmpty || busy)
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

            DisclosureGroup("WAVを手動で取り込む・監視する") {
                Text("製品側で書き出したWAVも、音声・字幕・口パクとして追加できます。")
                    .font(.caption)
                HStack {
                    Button("WAVを選択して追加…") { selectAudio() }.disabled(busy)
                    Button(folder == nil ? "監視フォルダー…" : "監視を停止") {
                        if folder == nil { selectFolder() } else { stopWatching() }
                    }.disabled(busy)
                    if busy { ProgressView().controlSize(.small) }
                }
                if let folder {
                    Text("監視中: \(folder.lastPathComponent) ／ 新しいWAVを検出後、下の追加ボタンで取り込み")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !pending.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(pending, id: \.self) { url in
                                HStack {
                                    Text(url.lastPathComponent).lineLimit(1)
                                    Spacer()
                                    Button("追加") { Task { await insert(url) } }.disabled(busy)
                                    Button("除外") { pending.removeAll { $0 == url } }.disabled(busy)
                                }
                            }
                        }
                    }.frame(maxHeight: 90)
                }
            }
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            Text("直接生成はA.I.VOICE2が公開するアクセシビリティ項目を操作します。固定座標や非公開APIは使いません。口パクは生成音声の音量から推定し、目パチはキャラクター設定を使用します。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: folder) {
            guard folder != nil else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                scan()
            }
        }
        .onDisappear { stopWatching() }
        .onChange(of: characterID, initial: true) { _, _ in applyCharacterDefaults() }
        .onChange(of: store.aiv2Catalog.names) { _, _ in selectPreferredSpeakerIfAvailable() }
    }

    private func selectAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await insert(url) }
        }
    }

    private var preferredSpeaker: String? {
        guard let character = characterID.flatMap({ store.project.character(withID: $0) }),
              character.voiceProvider == "A.I.VOICE2", !character.voiceLibrary.isEmpty else { return nil }
        return character.voiceLibrary
    }

    private var speakerChoices: [String] {
        Array(Set(store.aiv2Catalog.names + [selectedSpeakerName, preferredSpeaker ?? ""]))
            .filter { !$0.isEmpty }.sorted()
    }

    private var styleChoices: [String] {
        let saved = draftSettings.styleWeights?.keys.map { $0 } ?? []
        return Array(Set(store.aiv2Catalog.styleNames + saved)).sorted()
    }

    private var canGenerate: Bool {
        !selectedSpeakerName.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func launchEditor(selectAgain: Bool = false) async {
        busy = true
        defer { busy = false }
        do { try await AIVoice2Launcher.launch(selectAgain: selectAgain) }
        catch { message = error.localizedDescription }
    }

    private func selectPreferredSpeakerIfAvailable() {
        guard selectedSpeakerName.isEmpty, let preferredSpeaker,
              store.aiv2Catalog.names.contains(preferredSpeaker) else { return }
        selectedSpeakerName = preferredSpeaker
    }

    private func applyCharacterDefaults() {
        guard let character = characterID.flatMap({ store.project.character(withID: $0) }),
              character.voiceProvider == "A.I.VOICE2" else {
            selectedSpeakerName = ""
            draftSettings = .aIVoice2Default
            return
        }
        selectedSpeakerName = character.voiceLibrary
        draftSettings = character.defaultVoiceSettings.validatedForAIVoice2()
        if let style = character.voiceStyle.isEmpty ? nil : character.voiceStyle,
           draftSettings.styleWeights?[style] == nil {
            draftSettings.styleWeights = [style: 1]
        }
    }

    private func saveCharacterDefaults() {
        guard let characterID,
              let index = store.project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        let settings = draftSettings.validatedForAIVoice2(
            availableStyleNames: store.aiv2Catalog.styleNames.isEmpty ? nil : Set(store.aiv2Catalog.styleNames)
        )
        store.beginUndoableChange()
        store.project.characters[index].voiceProvider = "A.I.VOICE2"
        store.project.characters[index].voiceLibrary = selectedSpeakerName
        store.project.characters[index].voiceStyle = dominantStyle(in: settings)
        store.project.characters[index].defaultSpeakerID = nil
        store.project.characters[index].defaultVoiceSettings = settings
        message = "音声初期値をキャラクターへ保存しました。"
    }

    private func request() -> AIVoice2AutomationClient.Request {
        var settings = draftSettings
        var weights = settings.styleWeights ?? [:]
        for name in store.aiv2Catalog.styleNames where weights[name] == nil { weights[name] = 0 }
        settings.styleWeights = weights
        return AIVoice2AutomationClient.Request(
            text: text,
            speakerName: selectedSpeakerName,
            settings: settings.validatedForAIVoice2(
                availableStyleNames: store.aiv2Catalog.styleNames.isEmpty ? nil : Set(store.aiv2Catalog.styleNames)
            )
        )
    }

    private func audition() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await store.aiv2Automation.audition(request())
            message = "A.I.VOICE2で試聴を開始しました。"
        } catch { message = error.localizedDescription }
    }

    private func synthesizeAndInsert() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let projectID = store.project.id
        let sceneID = store.currentSceneID
        let directory = store.assetsDirectory
        let position = store.playhead
        let character = characterID.flatMap { store.project.character(withID: $0) }
        let settings = request().settings
        do {
            let exported = try await store.aiv2Automation.synthesize(request())
            defer { exported.removeTemporaryFiles() }
            var result = try await ExternalVoiceImport.importFile(
                url: exported.wavURL, text: text, provider: provider,
                characterID: character?.id, startTime: position, assetsDirectory: directory,
                mouthSpeed: character?.defaultMouthSpeed ?? 1
            )
            guard store.project.id == projectID, store.currentSceneID == sceneID,
                  store.assetsDirectory == directory else {
                message = "編集中のプロジェクト・シーンが変わったため追加しませんでした。"
                return
            }
            if case .audio(var audio) = result.audioClip.content {
                audio.voiceLibrary = selectedSpeakerName
                audio.voiceStyle = dominantStyle(in: settings)
                audio.voiceSettings = settings
                audio.licenseNotes = character?.usageTerms ?? ""
                result.audioClip.content = .audio(audio)
            }
            if var clip = result.characterClip {
                clip.effects.flipHorizontal = character?.defaultFlipHorizontal ?? false
                result.characterClip = clip
            }
            store.insert(result)
            message = "A.I.VOICE2で生成し、音声・字幕・口パクを追加しました。"
        } catch { message = "直接生成に失敗しました：\(error.localizedDescription)" }
    }

    private func dominantStyle(in settings: VoiceSettings) -> String {
        settings.styleWeights?.max(by: { $0.value < $1.value })?.key ?? ""
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            folder = url
            known = snapshot(url)
            candidates = [:]
            pending = []
            message = "監視開始前のファイルは自動検出しません。「WAVを選択」で追加できます。"
        }
    }

    private func stopWatching() {
        folder?.stopAccessingSecurityScopedResource()
        folder = nil
        known = [:]
        candidates = [:]
        pending = []
    }

    private func snapshot(_ directory: URL) -> [URL: String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles])) ?? []
        var result: [URL: String] = [:]
        for url in urls where url.pathExtension.lowercased() == "wav" {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
               values.isRegularFile == true, let size = values.fileSize, size > 0 {
                result[url] = "\(size):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            }
        }
        return result
    }

    private func scan() {
        guard let folder else { return }
        let current = snapshot(folder)
        pending.removeAll { current[$0] == nil }
        for (url, signature) in current where known[url] != signature {
            if candidates[url] == signature {
                if !pending.contains(url) { pending.append(url) }
                known[url] = signature
            }
        }
        candidates = current
        pending.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func insert(_ url: URL) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let projectID = store.project.id
        let sceneID = store.currentSceneID
        let directory = store.assetsDirectory
        let position = store.playhead
        let character = characterID.flatMap { store.project.character(withID: $0) }
        do {
            var subtitle = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if subtitle.isEmpty {
                let sidecar = url.deletingPathExtension().appendingPathExtension("txt")
                if FileManager.default.fileExists(atPath: sidecar.path) {
                    guard (try sidecar.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_000_000 else {
                        message = "字幕.txtは1MB以内にしてください。"
                        return
                    }
                    let data = try Data(contentsOf: sidecar)
                    guard data.count <= 1_000_000,
                          let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
                        message = "字幕.txtを読めません。UTF-8で保存するか字幕欄に入力してください。"
                        return
                    }
                    subtitle = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            guard !subtitle.isEmpty else {
                message = "字幕を入力するか、WAVと同名の.txtを用意してください。"
                return
            }
            let capturedText = subtitle
            let capturedProvider = provider
            var result = try await Task.detached {
                try await ExternalVoiceImport.importFile(
                    url: url, text: capturedText, provider: capturedProvider,
                    characterID: character?.id, startTime: position, assetsDirectory: directory,
                    mouthSpeed: character?.defaultMouthSpeed ?? 1)
            }.value
            guard store.project.id == projectID, store.currentSceneID == sceneID,
                  store.assetsDirectory == directory,
                  character.map({ store.project.character(withID: $0.id) != nil }) ?? true else {
                message = "編集中のプロジェクト・シーンが変わったため追加しませんでした。もう一度選択してください。"
                return
            }
            if case .audio(var audio) = result.audioClip.content, provider == "A.I.VOICE2" {
                audio.voiceLibrary = selectedSpeakerName.isEmpty ? nil : selectedSpeakerName
                audio.voiceStyle = dominantStyle(in: draftSettings)
                audio.voiceSettings = draftSettings.validatedForAIVoice2()
                result.audioClip.content = .audio(audio)
            }
            if var clip = result.characterClip {
                clip.effects.flipHorizontal = character?.defaultFlipHorizontal ?? false
                result.characterClip = clip
            }
            store.insert(result)
            pending.removeAll { $0 == url }
            message = "\(url.lastPathComponent) を追加しました（元に戻す操作1回で取り消せます）。"
        } catch {
            message = "取り込みに失敗しました: \(error.localizedDescription)"
        }
    }
}

struct AIVoice2DraftControls: View {
    @Binding var settings: VoiceSettings
    let styleNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(AIVoice2Parameter.allCases) { parameter in
                HStack {
                    Text(parameter.label).frame(width: 72, alignment: .leading)
                    Slider(value: binding(parameter), in: parameter.range, step: 0.01)
                    TextField("", value: binding(parameter), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder).frame(width: 64)
                        .accessibilityLabel(parameter.label)
                }
            }
            if styleNames.isEmpty {
                Text("話者を読み取ると、その話者の画面で確認できた感情スタイルを表示します。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("感情スタイル").font(.caption.bold())
                ForEach(styleNames, id: \.self) { name in
                    HStack {
                        Text(name).frame(width: 72, alignment: .leading).lineLimit(1)
                        Slider(value: styleBinding(name), in: 0...1, step: 0.01)
                        TextField("", value: styleBinding(name), format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(.roundedBorder).frame(width: 64)
                            .accessibilityLabel("\(name)の強さ")
                    }
                }
            }
            Text("スタイルの種類は話者によって異なります。表示されていない感情名は推測して追加しません。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520)
    }

    private func binding(_ parameter: AIVoice2Parameter) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: parameter.keyPath] },
            set: { settings[keyPath: parameter.keyPath] = parameter.clamp($0) }
        )
    }

    private func styleBinding(_ name: String) -> Binding<Double> {
        Binding(
            get: { settings.styleWeights?[name] ?? 0 },
            set: { value in
                var weights = settings.styleWeights ?? [:]
                weights[name] = min(1, max(0, value.isFinite ? value : 0))
                settings.styleWeights = weights
            }
        )
    }
}
