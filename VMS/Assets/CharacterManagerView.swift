import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VMSCore

/// Sheet for importing character art: a base "tachie" image per character, plus one
/// overlay image per mouth shape (closed/small/open) drawn in the same rect for lip-sync.
struct CharacterManagerView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var newCharacterName: String = ""
    @State private var importMessage = ""
    @State private var isDeleteMode = false
    @State private var characterPendingDeletion: Character?
    @State private var selectedCharacterID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("キャラクター管理").font(.title3).bold()
                Spacer()
                Button(isDeleteMode ? "削除モード終了" : "削除モード") {
                    isDeleteMode.toggle()
                }
                .tint(isDeleteMode ? .red : nil)
                Button("閉じる") { dismiss() }
            }

            HStack {
                Button("プロファイルを読み込む") { importProfile() }
                Text(importMessage).font(.caption).foregroundColor(.secondary).lineLimit(2)
            }

            HStack {
                TextField("新しいキャラクター名", text: $newCharacterName)
                    .textFieldStyle(.roundedBorder)
                Button("ベース画像を選んで追加") {
                    addCharacter()
                }
                .disabled(newCharacterName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            HSplitView {
                List(selection: $selectedCharacterID) {
                    ForEach(store.project.characters) { character in
                        HStack {
                            Label(character.name, systemImage: "person.crop.rectangle")
                            Spacer()
                            if isDeleteMode {
                                Button(role: .destructive) { characterPendingDeletion = character } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.borderless)
                            }
                        }
                        .tag(character.id)
                    }
                }.frame(minWidth: 150, idealWidth: 180, maxWidth: 230)
                if let character = store.project.characters.first(where: { $0.id == selectedCharacterID }) {
                    ScrollView {
                        CharacterRow(character: character, isDeleteMode: isDeleteMode) {
                            characterPendingDeletion = character
                        }.id(character.id)
                    }.frame(minWidth: 390, idealWidth: 430)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("立ち絵の確認").font(.headline)
                            CharacterSettingsPreview(character: character, previewHeight: 340).id(character.id)
                            Text("デフォルト表情：\(character.expressions.first(where: { $0.id == character.defaultExpressionID })?.name ?? "通常の立ち絵")")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(12)
                    }.frame(minWidth: 310, idealWidth: 380, maxWidth: 540)
                } else {
                    ContentUnavailableView("キャラクターを選択", systemImage: "person.crop.rectangle", description: Text("左の一覧から設定するキャラクターを選んでください。"))
                    }
            }
        }
        .padding(20)
        .frame(minWidth: 960, idealWidth: 1200, minHeight: 640, idealHeight: 820)
        .onChange(of: store.project.characters.map(\.id), initial: true) { _, ids in
            if selectedCharacterID == nil || !ids.contains(selectedCharacterID!) { selectedCharacterID = ids.first }
        }
        .alert("キャラクターを削除しますか？", isPresented: Binding(
            get: { characterPendingDeletion != nil },
            set: { if !$0 { characterPendingDeletion = nil } }
        )) {
            Button("削除", role: .destructive) {
                if let characterPendingDeletion {
                    store.removeCharacter(id: characterPendingDeletion.id)
                }
                characterPendingDeletion = nil
            }
            Button("キャンセル", role: .cancel) { characterPendingDeletion = nil }
        } message: {
            Text("このキャラクターを使用しているタイムライン項目も削除されます。取り消しで元に戻せます。")
        }
    }

    private func addCharacter() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addCharacter(name: newCharacterName.trimmingCharacters(in: .whitespaces), baseImageURL: url)
        newCharacterName = ""
    }

    private func importProfile() {
        do {
            guard let report = try CharacterProfileImporter.prompt() else { return }
            guard !report.characters.isEmpty else {
                importMessage = report.warnings.joined(separator: " / ")
                return
            }
            store.beginUndoableChange()
            let existing = Set(store.project.characters.compactMap(\.importedSourceID))
            store.project.characters.append(contentsOf: report.characters.filter { character in
                guard let sourceID = character.importedSourceID else { return true }
                return !existing.contains(sourceID)
            })
            importMessage = "\(report.characters.count)件を読み込みました（\(report.filesRead)ファイル）"
            if !report.warnings.isEmpty { importMessage += "・一部警告あり" }
        } catch {
            importMessage = error.localizedDescription
        }
    }
}

private struct CharacterFrameAssignment: Identifiable {
    let id = UUID()
    let part: CharacterPartKind
    let frameID: UUID
}

private struct CharacterRow: View {
    @Environment(ProjectStore.self) private var store
    let character: Character
    let isDeleteMode: Bool
    let requestDeletion: () -> Void
    @State private var isShowingPSDReviewer = false
    @State private var editedName = ""
    @State private var isRenaming = false
    @State private var presetName = ""
    @State private var frameAssignment: CharacterFrameAssignment?
    @State private var automaticAnimationMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                thumbnail(fileName: character.baseImageFileName)
                if isRenaming {
                    TextField("素材名", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .onSubmit { commitName() }
                    Button("保存") { commitName() }.font(.caption)
                    Button("取消") { isRenaming = false }.font(.caption)
                } else {
                    Text(character.name).bold()
                    Button { editedName = character.name; isRenaming = true } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("素材名を変更")
                }
                if character.importedSource != nil {
                    Text("読込済み").font(.caption2).padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12)).clipShape(Capsule())
                }
                Spacer()
                if isDeleteMode {
                    Button(role: .destructive, action: requestDeletion) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("キャラクターを削除")
                }
            }

            CharacterVoiceSettingsSection(character: character)
            PropertySection("立ち絵・ファイル") {
            Picker("立ち絵の種類", selection: Binding(get: { character.tachieKind }, set: { kind in
                guard let index = store.project.characters.firstIndex(where: { $0.id == character.id }) else { return }
                store.beginUndoableChange()
                store.project.characters[index].tachieKind = kind
            })) {
                ForEach(TachieKind.selectableCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            LabeledContent("ファイル", value: character.importedSource ?? character.baseImageFileName)
                .font(.caption).textSelection(.enabled)
            if character.tachieKind == .psd {
                HStack(spacing: 8) {
                    settingStatus("既定", character.defaultExpressionID != nil)
                    settingStatus("口 \(character.mouthAnimationFrames.compactMap(\.imageFileName).count)/\(character.mouthAnimationFrames.count)", character.mouthAnimationFrames.allSatisfy { $0.imageFileName != nil })
                    settingStatus("目 \(character.eyeAnimationFrames.compactMap(\.imageFileName).count)/\(character.eyeAnimationFrames.count)", character.eyeAnimationFrames.allSatisfy { $0.imageFileName != nil })
                    Text("表情 \(character.expressions.count)件").font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Button("レイヤーを編集…") { isShowingPSDReviewer = true }
                    Button("PSDを開く") { openPSD() }
                    Button("PSDを差し替える…") { replacePSD() }
                    Button("表示を再読み込み") { store.reloadPSDPreview(for: character.id) }
                }
                .font(.caption)
                .sheet(isPresented: $isShowingPSDReviewer) {
                    PSDLayerReviewerView(characterID: character.id)
                }
                HStack(spacing: 8) {
                    Button {
                        automaticAnimationMessage = store.configureRecommendedPSDAnimation(
                            characterID: character.id
                        )
                    } label: {
                        Label("目パチ・口パクを自動設定", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(character.layerTree.isEmpty)
                    .help("PSDのレイヤー名と階層から、滑らかな目パチ・口パクの推奨コマをまとめて設定します")
                    Text("読み込み直後は空です。必要なときにこのボタンで設定できます。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if !automaticAnimationMessage.isEmpty {
                    Text(automaticAnimationMessage)
                        .font(.caption2)
                        .foregroundStyle(automaticAnimationMessage.contains("適用しました") ? .green : .orange)
                }
            }
            }

            PropertySection("口パク・通常口") {
            animationFrameStrip(part: .mouth, frames: character.mouthAnimationFrames, minimumCount: 3)
            NumericPropertyControl(label: "基本速度", value: Binding(get: { character.defaultMouthSpeed }, set: { value in
                guard let value, value.isFinite,
                      let index = store.project.characters.firstIndex(where: { $0.id == character.id }) else { return }
                store.project.characters[index].defaultMouthSpeed = min(max(value, 0.5), 3)
            }), range: 0.5...3, step: 0.1, decimalPlaces: 1, unit: "倍", resetValue: 1)
            .help("キャラクターごとの口パク速度。大きいほど口を素早く閉じます")
            Text("左から閉→開の順です。PSD素材では枠を押してPSDレイヤーを選びます。＋で中間フレームを増やせます。")
                .font(.caption).foregroundStyle(.secondary)
            }
            PropertySection("配置・左右反転") {
            Toggle(
                "新規アイテムを左右反転",
                isOn: Binding(
                    get: { character.defaultFlipHorizontal },
                    set: { store.setCharacterDefaultFlip(id: character.id, value: $0) }
                )
            )
            .font(.caption)
            .toggleStyle(.switch)
            .help("このキャラクターを新しく配置するときのデフォルト左右反転")
            }

            PropertySection("表情") {
            HStack {
                Text("表情").font(.caption).bold().foregroundColor(.secondary)
                Spacer()
                Button("表情を追加…") { addExpression() }.font(.caption)
            }
            if character.expressions.isEmpty {
                Text("通常編集画面で切り替える表情を登録できます。")
                    .font(.caption2).foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                    ForEach(character.expressions) { expression in
                        VStack(spacing: 3) {
                            thumbnail(fileName: expression.imageFileName)
                            Text(expression.name).font(.caption2).lineLimit(1)
                            Button(character.defaultExpressionID == expression.id ? "デフォルト" : "デフォルトにする") {
                                store.setDefaultExpression(characterID: character.id, expressionID: expression.id)
                            }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                            .disabled(character.defaultExpressionID == expression.id)
                            Button(role: .destructive) {
                                store.removeExpression(for: character.id, expressionID: expression.id)
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("表情を削除")
                        }
                    }
                }
            }
            }

            PropertySection("目パチ") {
            CharacterBlinkControls(character: character)
            animationFrameStrip(part: .eye, frames: character.eyeAnimationFrames, minimumCount: 2)
            Text("左から開→閉の順です。3枚以上では中間フレームを往復して滑らかに目パチします。")
                .font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            PropertySection("キャラクタープリセット") {
            HStack {
                TextField("プリセット名", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                Button("現在の設定を保存") {
                    store.saveCharacterPreset(characterID: character.id, name: presetName)
                    presetName = ""
                }
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(character.presets) { preset in
                HStack {
                    Image(systemName: "person.crop.rectangle.stack")
                    Text(preset.name).font(.caption)
                    if let voice = preset.voice, !voice.provider.isEmpty {
                        Text("\(voice.provider) / \(voice.speakerName)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("適用") { store.applyCharacterPreset(characterID: character.id, presetID: preset.id) }
                    Button(role: .destructive) {
                        store.removeCharacterPreset(characterID: character.id, presetID: preset.id)
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
            }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.05))
        .cornerRadius(8)
        .sheet(item: $frameAssignment) { assignment in
            PSDCharacterPartPickerView(
                characterID: character.id,
                part: assignment.part,
                frameID: assignment.frameID
            )
        }
    }

    private func thumbnail(fileName: String) -> some View {
        Group {
            if let image = store.imageProvider.croppedToVisibleContent(named: fileName) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 72, height: 64)
        .background(Color.black.opacity(0.1))
        .cornerRadius(4)
    }

    @ViewBuilder
    private func animationFrameStrip(
        part: CharacterPartKind,
        frames: [CharacterPartFrame],
        minimumCount: Int
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                    VStack(spacing: 4) {
                        Button {
                            chooseImage(for: part, frameID: frame.id)
                        } label: {
                            Group {
                                if let fileName = frame.imageFileName {
                                    thumbnail(fileName: fileName)
                                } else {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.16))
                                        .overlay(Image(systemName: character.tachieKind == .psd ? "square.3.layers.3d" : "photo.badge.plus"))
                                        .frame(width: 72, height: 64)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                Text("\(index + 1)")
                                    .font(.caption2.monospacedDigit())
                                    .padding(3)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 3))
                                    .padding(3)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(character.tachieKind == .psd ? "PSDレイヤーから割り当て" : "画像ファイルを割り当て")
                        Text(frame.name).font(.caption2).lineLimit(1).frame(width: 76)
                        if !frame.allSourceLayerIDs.isEmpty {
                            Label(
                                frame.allSourceLayerIDs.count > 1 ? "PSD合成" : "PSD",
                                systemImage: "link"
                            )
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                        if frames.count > minimumCount, index > 0, index < frames.count - 1 {
                            Button(role: .destructive) {
                                store.removeCharacterPartFrame(characterID: character.id, part: part, frameID: frame.id)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("このフレームを削除")
                        }
                    }
                }
                Button {
                    store.addCharacterPartFrame(characterID: character.id, part: part)
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .frame(width: 72, height: 64)
                            .overlay(Image(systemName: "plus").font(.title3))
                        Text("枠を追加").font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .help("滑らかな動きに使う中間フレームを追加")
            }
            .padding(.vertical, 2)
        }
    }

    private func chooseImage(for part: CharacterPartKind, frameID: UUID) {
        if character.tachieKind == .psd {
            frameAssignment = CharacterFrameAssignment(part: part, frameID: frameID)
        } else {
            pickPartImage(for: part, frameID: frameID)
        }
    }

    private func pickPartImage(for part: CharacterPartKind, frameID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setCharacterPartFrameImage(characterID: character.id, part: part, frameID: frameID, sourceURL: url)
    }

    private func addExpression() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            store.addExpression(for: character.id, name: url.deletingPathExtension().lastPathComponent, sourceURL: url)
        }
    }

    private func openPSD() {
        guard let source = character.importedSource else { return }
        NSWorkspace.shared.open(store.assetsDirectory.appendingPathComponent(source))
    }

    private func replacePSD() {
        let panel = NSOpenPanel()
        if let psdType = UTType(filenameExtension: "psd") {
            panel.allowedContentTypes = [psdType]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.replacePSD(for: character.id, sourceURL: url)
    }

    private func commitName() {
        store.renameCharacter(id: character.id, name: editedName)
        isRenaming = false
    }

    private func settingStatus(_ title: String, _ complete: Bool) -> some View {
        Label(title + (complete ? " 設定済み" : " 未設定"), systemImage: complete ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.caption2)
            .foregroundColor(complete ? .green : .orange)
    }
}
