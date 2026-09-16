import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VMSCore

struct StoryboardEditorView: View {
    @Environment(ProjectStore.self) private var store
    @State private var selectedID: UUID?
    @State private var importingScenario = false
    @State private var pendingAIImport: PendingAIStoryboardImport?
    @State private var overwrite = false

    private var cards: [StoryboardCard] { store.storyboard?.cards ?? [] }
    private var resolved: [ResolvedStoryboardCard] {
        (try? store.storyboard?.resolved(characters: store.project.characters)) ?? []
    }
    private var conflict: Bool { store.storyboard?.hasTimelineChanges(store.currentTimeline) ?? false }

    var body: some View {
        let times = Dictionary(uniqueKeysWithValues: resolved.map { ($0.card.id, Double($0.startFrame) / (store.storyboard?.frameRate ?? 30)) })
        VStack(spacing: 8) {
            HStack {
                Button("台本からコマを追加…") { importingScenario = true }
                Button("コマを追加") {
                    let card = StoryboardCard(speakerID: cards.last?.speakerID, dialogue: "台詞を入力",
                                              durationFrames: Int((store.storyboard?.frameRate ?? store.newStoryboard().frameRate) * 3))
                    if store.changeStoryboard({ $0.cards.append(card) }) { selectedID = card.id }
                }.disabled(conflict || cards.count >= 300)
                Divider().frame(height: 18)
                Button("AI情報を書き出す…") { exportAIInformation() }
                    .help("キャラクター・素材・現在の絵コンテ情報を、AI編集用JSONとして書き出します")
                Button("AI絵コンテJSONを読み込む…") { importAIStoryboard() }
                    .help("AIが編集したJSONを検証し、適用前に差分を表示します")
                Text("\(cards.count)コマ").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let board = store.storyboard {
                    Text("開始 \(Double(board.startFrame) / board.frameRate, specifier: "%.2f") 秒・\(board.frameRate, specifier: "%.0f") fps")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 12)
            if conflict {
                HStack {
                    Text("タイムライン側で変更されています。絵コンテからの上書きは停止中です。")
                    Button("絵コンテから再反映…") { overwrite = true }
                }.font(.caption).padding(8).background(Color.orange.opacity(0.12))
            }
            HSplitView {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 300))], spacing: 12) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            Button {
                                selectedID = card.id
                                store.isPlaying = false
                                if let item = resolved.first(where: { $0.card.id == card.id }), let board = store.storyboard {
                                    store.playhead = Double(item.startFrame) / board.frameRate
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    StoryboardFrame(time: times[card.id] ?? 0).aspectRatio(store.project.resolution.width / max(1, store.project.resolution.height), contentMode: .fit)
                                    Text("\(index + 1). \(speakerName(card.speakerID))").font(.caption).bold()
                                    Text(card.dialogue).font(.caption).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(card.audio == nil ? "音声未生成" : "音声あり").font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(8).background(.background)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedID == card.id ? Color.blue : .gray.opacity(0.3), lineWidth: selectedID == card.id ? 3 : 1))
                            }.buttonStyle(.plain).accessibilityLabel("コマ\(index + 1)：\(card.dialogue)")
                        }
                    }.padding(12)
                    if cards.isEmpty {
                        ContentUnavailableView("台詞から絵コンテを作成", systemImage: "rectangle.grid.2x2",
                            description: Text("「話者名：台詞」を1行ずつ入力します。1行が1コマになり、立ち位置は前のコマから引き継がれます。"))
                    }
                }.frame(minWidth: 320)
                if let card = cards.first(where: { $0.id == selectedID }) {
                    ScrollView {
                        StoryboardCardInspector(card: card, startTime: times[card.id] ?? 0)
                            .id(card.id).disabled(conflict)
                    }.frame(minWidth: 330, idealWidth: 390, maxWidth: 520)
                }
            }
        }
        .padding(.top, 8)
        .onChange(of: cards.map(\.id), initial: true) { _, ids in
            if !ids.contains(where: { $0 == selectedID }) { selectedID = ids.first }
        }
        .alert("タイムラインでの変更を上書きしますか？", isPresented: $overwrite) {
            Button("絵コンテから再反映", role: .destructive) { store.changeStoryboard(force: true) { _ in } }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("絵コンテ由来の項目だけを再作成します。その他の素材は変更しません。ロックされた項目は上書きしません。Undoで戻せます。")
        }
        .sheet(isPresented: $importingScenario) {
            ScenarioImportView(existingCardCount: cards.count, conflict: conflict) { added, replaceExisting in
                guard !added.isEmpty else { return }
                let changed = store.changeStoryboard { board in
                    if replaceExisting { board.cards = added }
                    else { board.cards.append(contentsOf: added) }
                }
                if changed {
                    selectedID = added.first?.id
                    importingScenario = false
                }
            }
        }
        .sheet(item: $pendingAIImport) { pending in
            AIStoryboardImportReviewView(
                result: pending.result,
                characterNames: store.project.characters.reduce(into: [:]) { $0[$1.id] = $1.name },
                timelineConflict: conflict
            ) { force in
                let changed = store.changeStoryboard(force: force) { board in
                    board = pending.result.storyboard
                }
                if changed {
                    selectedID = pending.result.differences.first(where: { $0.after != nil && $0.kind != .unchanged })?.after?.id
                        ?? pending.result.storyboard.cards.first?.id
                    pendingAIImport = nil
                }
            }
        }
    }

    private func startTime(_ id: UUID) -> Double {
        guard let item = resolved.first(where: { $0.card.id == id }), let board = store.storyboard else { return 0 }
        return Double(item.startFrame) / board.frameRate
    }
    private func speakerName(_ id: UUID?) -> String {
        id.flatMap { store.project.character(withID: $0)?.name } ?? "字幕のみ"
    }

    private func exportAIInformation() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "AI絵コンテ.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = AIStoryboardExchange.makeDocument(project: store.project, scene: store.currentScene)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(document).write(to: url, options: .atomic)
        } catch {
            store.errorMessage = "AI情報を書き出せませんでした：\(error.localizedDescription)"
        }
    }

    private func importAIStoryboard() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= 4 * 1_024 * 1_024 else {
                throw AIStoryboardFileError.invalidSize
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(AIStoryboardExchangeDocument.self, from: data)
            let result = try AIStoryboardExchange.validate(document, project: store.project, scene: store.currentScene)
            pendingAIImport = PendingAIStoryboardImport(result: result)
        } catch {
            store.errorMessage = "AI絵コンテJSONを読み込めませんでした：\(error.localizedDescription)"
        }
    }
}

private struct PendingAIStoryboardImport: Identifiable {
    let id = UUID()
    let result: AIStoryboardImportResult
}

private enum AIStoryboardFileError: Error, LocalizedError {
    case invalidSize
    var errorDescription: String? { "JSONは4MB以内の通常ファイルを選んでください。" }
}

/// Resizes the real compositor; does not mutate timeline clips by dragging a separate preview.
private struct StoryboardFrame: View {
    @Environment(ProjectStore.self) private var store
    let time: Double
    var body: some View {
        GeometryReader { proxy in
            let width = max(1, store.project.resolution.width)
            CompositeFrameView(project: store.project, timeline: store.currentTimeline, time: time,
                               imageProvider: store.imageProvider, videoFrameProvider: store.videoFrameProvider)
                .scaleEffect(proxy.size.width / width, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading).clipped()
        }
    }
}

private struct StoryboardCardInspector: View {
    @Environment(ProjectStore.self) private var store
    let card: StoryboardCard
    let startTime: Double
    @State private var placementID: UUID?
    @State private var generating = false
    @State private var deleting = false
    private var fps: Double { store.storyboard?.frameRate ?? 30 }
    private var placement: StoryboardPlacement {
        guard let id = placementID else { return StoryboardPlacement() }
        return (try? store.storyboard?.resolved(characters: store.project.characters))?
            .first { $0.card.id == card.id }?.placements[id]
            ?? store.storyboard?.initialPlacements[id] ?? StoryboardPlacement()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("コマの調整").font(.headline)
            StoryboardFrame(time: store.isPlaying ? store.playhead : startTime + Double(max(0, card.durationFrames - 1)) / fps)
                .aspectRatio(store.project.resolution.width / max(1, store.project.resolution.height), contentMode: .fit)
            HStack {
                Button("前へ") { move(-1) }.disabled(index == 0)
                Button("次へ") { move(1) }.disabled(index >= (store.storyboard?.cards.count ?? 0) - 1)
                Button("複製") {
                    store.changeStoryboard { board in
                        if let i = board.cards.firstIndex(where: { $0.id == card.id }) {
                            board.cards.insert(card.duplicated(), at: i + 1)
                        }
                    }
                }
                Button("削除", role: .destructive) { deleting = true }
            }
            Picker("話者", selection: Binding(get: { card.speakerID }, set: { id in
                store.editStoryboardCard(card.id) { $0.speakerID = id }
                placementID = id
            })) {
                Text("なし（字幕のみ）").tag(UUID?.none)
                ForEach(store.project.characters) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            TextField("台詞", text: Binding(get: { card.dialogue }, set: { value in
                store.editStoryboardCard(card.id, undo: false) { $0.dialogue = value }
            }), onEditingChanged: { editing in if editing { store.beginUndoableChange() } })
                .textFieldStyle(.roundedBorder)
            NumericPropertyControl(label: "長さ", value: Binding(get: { Double(card.durationFrames) / fps }, set: { value in
                guard let value, value.isFinite else { return }
                store.editStoryboardCard(card.id, undo: false) { $0.durationFrames = max(1, Int((value * fps).rounded())) }
            }), range: (1 / fps)...600, step: 1 / fps, decimalPlaces: 2, unit: "秒")

            Divider()
            Picker("配置する素材", selection: $placementID) {
                Text("選択してください").tag(UUID?.none)
                ForEach(store.project.characters) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            if let id = placementID {
                Text(card.placements[id] == nil ? "前のコマの配置を継承中" : "このコマから配置を変更")
                    .font(.caption).foregroundStyle(.secondary)
                NumericPropertyControl(label: "X", value: position(\.x), range: -2...2, step: 0.01, decimalPlaces: 2)
                NumericPropertyControl(label: "Y", value: position(\.y), range: -2...2, step: 0.01, decimalPlaces: 2)
                NumericPropertyControl(label: "拡大率", value: Binding(get: { placement.scale }, set: { value in
                    guard let value else { return }; setPlacement(undo: false) { $0.scale = value }
                }), range: 0.05...5, step: 0.05, decimalPlaces: 2, unit: "倍")
                Toggle("左右反転", isOn: Binding(get: { placement.flipHorizontal }, set: { value in
                    setPlacement { $0.flipHorizontal = value }
                }))
                Toggle("表示する", isOn: Binding(get: { placement.isVisible }, set: { value in
                    setPlacement { $0.isVisible = value }
                }))
                if let character = store.project.character(withID: id), !character.expressions.isEmpty {
                    Picker("表情", selection: Binding(get: { placement.expressionID }, set: { value in
                        setPlacement { $0.expressionID = value }
                    })) {
                        Text("キャラクターの初期表情").tag(UUID?.none)
                        ForEach(character.expressions) { expression in
                            Text(expression.name).tag(UUID?.some(expression.id))
                        }
                    }
                }
                Button("このコマの指定を解除して前から継承") {
                    store.editStoryboardCard(card.id) { $0.placements.removeValue(forKey: id) }
                }.disabled(card.placements[id] == nil)
            }
            Toggle("前のコマから滑らかに移動", isOn: Binding(get: { (card.transitionFrames ?? 0) > 0 }, set: { enabled in
                store.editStoryboardCard(card.id) { $0.transitionFrames = enabled ? max(1, Int((fps * 0.3).rounded())) : nil }
            }))
            if (card.transitionFrames ?? 0) > 0 {
                NumericPropertyControl(label: "移動時間", value: Binding(get: {
                    Double(min(card.transitionFrames ?? 0, card.durationFrames)) / fps
                }, set: { value in
                    guard let value, value.isFinite else { return }
                    store.editStoryboardCard(card.id, undo: false) {
                        $0.transitionFrames = min(card.durationFrames, max(1, Int((value * fps).rounded())))
                    }
                }), range: (1 / fps)...(Double(card.durationFrames) / fps), step: 1 / fps, decimalPlaces: 2, unit: "秒")
            }
            Button("このコマから再生") {
                store.isPlaying = false
                store.playhead = startTime
                store.isPlaying = true
            }.disabled(store.isPlaying)
            Text("停止中はコマ末尾の配置を表示します。再生すると前の配置から位置・拡大率が滑らかに変わります。最初の登場・表示切替・左右反転は即時切替です。")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button(voiceGenerationTitle) { Task { await generate() } }
                    .disabled(!canGenerateVoice)
                Button("WAVをこのコマに追加…") { chooseWAV() }
                if generating { ProgressView().controlSize(.small) }
            }
            Text(card.audio == nil ? "音声未生成。台詞・話者を変えた場合も再生成してください。" : "音声あり。生成時の長さに合わせています。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12).disabled(generating)
        .onAppear { placementID = card.speakerID }
        .alert("このコマを削除しますか？", isPresented: $deleting) {
            Button("削除", role: .destructive) {
                store.changeStoryboard { $0.cards.removeAll { $0.id == card.id } }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("このコマ由来の字幕・音声・立ち絵を削除し、後ろのコマを詰めます。Undoで戻せます。") }
    }

    private var index: Int { store.storyboard?.cards.firstIndex { $0.id == card.id } ?? 0 }
    private func move(_ direction: Int) {
        store.changeStoryboard { board in
            guard let from = board.cards.firstIndex(where: { $0.id == card.id }) else { return }
            let to = from + direction
            guard board.cards.indices.contains(to) else { return }
            board.cards.swapAt(from, to)
        }
    }
    private func position(_ key: WritableKeyPath<CodablePoint, Double>) -> Binding<Double?> {
        Binding(get: { placement.position[keyPath: key] }, set: { value in
            guard let value else { return }; setPlacement(undo: false) { $0.position[keyPath: key] = value }
        })
    }
    private func setPlacement(undo: Bool = true, _ change: (inout StoryboardPlacement) -> Void) {
        guard let id = placementID else { return }
        var value = placement
        change(&value)
        store.editStoryboardCard(card.id, undo: undo) { $0.placements[id] = value }
    }

    private func chooseWAV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav]
        if panel.runModal() == .OK, let url = panel.url { Task { await generate(wav: url) } }
    }
    private var assignedCharacter: Character? {
        card.speakerID.flatMap { store.project.character(withID: $0) }
    }
    private var voiceGenerationTitle: String {
        switch assignedCharacter?.voiceProvider {
        case "A.I.VOICE2": "A.I.VOICE2で音声生成"
        case AquesTalkPlayerSupport.providerID: "AquesTalk Playerで音声生成"
        case MacSystemVoiceSupport.providerID: "Mac音声で生成"
        default: "VOICEVOXで音声生成"
        }
    }
    private var canGenerateVoice: Bool {
        guard !card.dialogue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let character = assignedCharacter else { return false }
        let providerID = character.voiceProvider.isEmpty ? "VOICEVOX" : character.voiceProvider
        guard store.voiceIntegrations.isEnabled(providerID: providerID) else { return false }
        if character.voiceProvider == "A.I.VOICE2" { return !character.voiceLibrary.isEmpty }
        if character.voiceProvider == AquesTalkPlayerSupport.providerID {
            return AquesTalkPlayerService.isReady
        }
        if character.voiceProvider == MacSystemVoiceSupport.providerID { return !character.voiceLibrary.isEmpty }
        return (character.voiceProvider.isEmpty || character.voiceProvider == "VOICEVOX")
            && character.defaultSpeakerID != nil
    }
    private func generate(wav: URL? = nil) async {
        generating = true
        defer { generating = false }
        let projectID = store.project.id
        let sceneID = store.currentSceneID
        let assets = store.assetsDirectory
        let original = card
        let character = card.speakerID.flatMap { store.project.character(withID: $0) }
        let assignment = character.map(CharacterVoicePreset.init)
        do {
            var result: TTSImportResult
            if let wav {
                let scoped = wav.startAccessingSecurityScopedResource()
                defer { if scoped { wav.stopAccessingSecurityScopedResource() } }
                result = try await Task.detached {
                    try await ExternalVoiceImport.importFile(url: wav, text: original.dialogue,
                        provider: assignment?.provider.isEmpty == false ? assignment!.provider : "外部WAV",
                        characterID: character?.id, startTime: 0, assetsDirectory: assets,
                        mouthSpeed: character?.defaultMouthSpeed ?? 1)
                }.value
            } else if let assignment, assignment.provider == "A.I.VOICE2" {
                guard !assignment.speakerName.isEmpty else {
                    store.errorMessage = "キャラクター管理でA.I.VOICE2の話者を指定してください。"
                    return
                }
                var settings = assignment.settings.validatedForAIVoice2()
                var weights = settings.styleWeights ?? [:]
                for name in store.aiv2Catalog.styleNames where weights[name] == nil { weights[name] = 0 }
                settings.styleWeights = weights
                let exported = try await store.aiv2Automation.synthesize(.init(
                    text: original.dialogue, speakerName: assignment.speakerName, settings: settings
                ))
                defer { exported.removeTemporaryFiles() }
                result = try await ExternalVoiceImport.importFile(
                    url: exported.wavURL, text: original.dialogue, provider: "A.I.VOICE2",
                    characterID: character?.id, startTime: 0, assetsDirectory: assets,
                    mouthSpeed: character?.defaultMouthSpeed ?? 1
                )
                if case .audio(var data) = result.audioClip.content {
                    data.voiceLibrary = assignment.speakerName
                    data.voiceStyle = assignment.styleName
                    data.voiceSettings = settings
                    data.licenseNotes = character?.usageTerms ?? ""
                    result.audioClip.content = .audio(data)
                }
            } else if let assignment, assignment.provider == AquesTalkPlayerSupport.providerID {
                result = try await AquesTalkPlayerService.importSpeech(
                    text: original.dialogue,
                    presetName: assignment.speakerName,
                    character: character,
                    startTime: 0,
                    assetsDirectory: assets
                )
            } else if let assignment, assignment.provider == MacSystemVoiceSupport.providerID {
                guard !assignment.speakerName.isEmpty else {
                    store.errorMessage = "キャラクター管理でMacの日本語音声を指定してください。"
                    return
                }
                result = try await MacSystemVoiceSynthesisService.importSpeech(
                    text: original.dialogue,
                    voiceIdentifier: assignment.speakerName,
                    settings: assignment.settings.validatedForMacSystemVoice(),
                    character: character,
                    startTime: 0,
                    assetsDirectory: assets
                )
            } else {
                let speakers = try await store.voiceEngine.availableSpeakers()
                guard let assignment, let speaker = assignment.resolveVoiceVox(in: speakers) else {
                    store.errorMessage = "キャラクター管理でVOICEVOXの話者・スタイルを指定してください。別ソフトの指定は自動で置き換えません。"
                    return
                }
                result = try await TTSImportService.importSpeech(text: card.dialogue, speakerID: speaker.id,
                    characterID: character?.id, startTime: 0, engine: store.voiceEngine, assetsDirectory: assets,
                    settings: assignment.settings, mouthSpeed: character?.defaultMouthSpeed ?? 1)
            }
            guard store.project.id == projectID, store.currentSceneID == sceneID, store.assetsDirectory == assets,
                  store.storyboard?.cards.first(where: { $0.id == original.id }) == original else {
                store.errorMessage = "合成中にコマが変更されたため反映しませんでした。"
                return
            }
            guard case .audio(let data) = result.audioClip.content else { return }
            guard result.audioClip.duration.isFinite, result.audioClip.duration > 0,
                  result.audioClip.duration <= 600 else { throw StoryboardError.invalid }
            var keys: [MouthKeyframe] = []
            if let clip = result.characterClip, case .character(let data) = clip.content { keys = data.mouthKeyframes }
            store.changeStoryboard { board in
                guard let i = board.cards.firstIndex(where: { $0.id == original.id }) else { return }
                board.cards[i].audio = StoryboardAudio(data: data, mouthKeyframes: keys)
                board.cards[i].durationFrames = max(1, Int(ceil(result.audioClip.duration * board.frameRate)))
            }
        } catch { store.errorMessage = error.localizedDescription }
    }
}
