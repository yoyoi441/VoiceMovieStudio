import SwiftUI
import VMSCore

/// Selects dialogue bundles by character and/or words, then replaces their character
/// assignment without depending on a particular track layout.
struct BulkEditView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var sourceCharacterID: UUID?
    @State private var phrase = ""
    @State private var targetCharacterID: UUID?
    @State private var regenerateVoice = true
    @State private var isApplying = false
    @State private var resultMessage = ""

    private var match: BulkClipMatch {
        store.bulkClipMatch(sourceCharacterID: sourceCharacterID, phrase: phrase)
    }

    private var targetCharacter: Character? {
        targetCharacterID.flatMap { store.project.character(withID: $0) }
    }

    private var canRegenerateVoice: Bool {
        guard let targetCharacter else { return false }
        let configured: Bool
        if targetCharacter.voiceProvider == "A.I.VOICE2"
            || targetCharacter.voiceProvider == SofTalkSupport.providerID {
            configured = !targetCharacter.voiceLibrary.isEmpty
        } else {
            configured = (targetCharacter.voiceProvider.isEmpty || targetCharacter.voiceProvider == "VOICEVOX")
                && targetCharacter.defaultSpeakerID != nil
        }
        return configured && !match.audioClipIDs.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("一括編集")
                        .font(.title2.bold())
                    Text("現在のシーンから条件に合う立ち絵・音声・字幕をまとめて扱います")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)

            Divider()

            Form {
                Section("対象を絞り込む") {
                    Picker("元キャラクター", selection: $sourceCharacterID) {
                        Text("すべてのキャラクター").tag(nil as UUID?)
                        ForEach(store.project.characters) { character in
                            Text(character.name).tag(Optional(character.id))
                        }
                    }

                    TextField("セリフに含まれる言葉（空欄ならすべて）", text: $phrase)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Label("該当 \(match.clipIDs.count)件", systemImage: "rectangle.stack")
                        Spacer()
                        Text("立ち絵 \(match.characterClipIDs.count)・音声 \(match.audioClipIDs.count)・字幕 \(match.subtitleClipIDs.count)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout.monospacedDigit())

                    Button("該当項目をタイムラインで選択") {
                        let count = store.selectBulkClipMatch(
                            sourceCharacterID: sourceCharacterID, phrase: phrase
                        )
                        resultMessage = count == 0
                            ? "条件に一致する項目はありません。"
                            : "\(count)件を選択しました。"
                    }
                    .disabled(match.clipIDs.isEmpty || isApplying)
                }

                Section("キャラクターと声を変更") {
                    Picker("置換先キャラクター", selection: $targetCharacterID) {
                        Text("選択してください").tag(nil as UUID?)
                        ForEach(store.project.characters) { character in
                            Text(character.name).tag(Optional(character.id))
                        }
                    }

                    Toggle("置換先キャラクターの声で音声を再生成", isOn: $regenerateVoice)
                        .disabled(!canRegenerateVoice || isApplying)

                    if let targetCharacter, !canRegenerateVoice {
                        Text(voiceRegenerationUnavailableMessage(for: targetCharacter))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("配置・表示時間・字幕の書式は維持します。表情指定は置換先で無効になる可能性があるため解除します。音声再生成を有効にした場合は、元のセリフから音声、字幕の長さ、口パクをまとめて更新します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !resultMessage.isEmpty {
                    Section("結果") {
                        Text(resultMessage)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                    Text("音声を生成しています…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("キャンセル") { dismiss() }
                    .disabled(isApplying)
                Button("一括変更") { applyReplacement() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        targetCharacterID == nil || match.clipIDs.isEmpty || isApplying
                            || (match.characterClipIDs.isEmpty && !(regenerateVoice && !match.audioClipIDs.isEmpty))
                    )
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 510, idealHeight: 560)
        .interactiveDismissDisabled(isApplying)
        .onAppear {
            let selectedCharacterID = store.selectedClips.compactMap { clip -> UUID? in
                guard case .character(let data) = clip.content else { return nil }
                return data.characterID
            }.first
            sourceCharacterID = selectedCharacterID
            targetCharacterID = store.project.characters.first(where: { $0.id != selectedCharacterID })?.id
                ?? store.project.characters.first?.id
            updateVoiceToggle()
        }
        .onChange(of: targetCharacterID) { _, _ in updateVoiceToggle() }
        .onChange(of: phrase) { _, _ in
            resultMessage = ""
            updateVoiceToggle()
        }
        .onChange(of: sourceCharacterID) { _, _ in
            resultMessage = ""
            updateVoiceToggle()
        }
    }

    private func updateVoiceToggle() {
        if !canRegenerateVoice { regenerateVoice = false }
    }

    private func voiceRegenerationUnavailableMessage(for character: Character) -> String {
        if match.audioClipIDs.isEmpty { return "条件に一致する音声がないため、立ち絵のみ変更します。" }
        return "このキャラクターにアプリ内生成用の話者を設定すると、声もまとめて再生成できます。"
    }

    private func applyReplacement() {
        guard let targetCharacterID else { return }
        isApplying = true
        resultMessage = ""
        Task {
            let message = await store.bulkReplaceCharacter(
                sourceCharacterID: sourceCharacterID,
                phrase: phrase,
                targetCharacterID: targetCharacterID,
                regenerateVoice: regenerateVoice
            )
            resultMessage = message
            isApplying = false
        }
    }
}
