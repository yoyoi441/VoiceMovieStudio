import AppKit
import SwiftUI
import VMSCore

/// §7-7. Volume/pan/pitch/speed/intonation/silence are real and, via "再生成", actually
/// re-synthesize the clip through `store.voiceEngine` (provider-agnostic — VOICEVOX is
/// just today's implementation). Echo/custom-voice/watched-folder are out of scope for
/// any engine we support yet, so they're present but disabled, per spec allowance.
struct VoiceSettingsInspector: View {
    @Environment(ProjectStore.self) private var store
    let primary: Clip

    @State private var speakers: [VoiceSpeaker] = []
    @State private var isRegenerating = false

    var body: some View {
        guard case .audio(let data) = primary.content else { return AnyView(EmptyView()) }

        return AnyView(
            PropertySection("音声") {
                HStack(spacing: 6) {
                    Text("ファイル名").font(Theme.labelFont).foregroundColor(.secondary).frame(width: 64, alignment: .leading)
                    Text(data.fileName).font(.caption2).lineLimit(1).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        preview(data)
                    } label: {
                        IconCatalog.resolve(.play).font(.system(size: 10))
                        Text("試聴").font(.caption2)
                    }
                    .buttonStyle(.plain)
                }

                if let sourceText = data.sourceText {
                    HStack(alignment: .top, spacing: 6) {
                        Text("元テキスト").font(Theme.labelFont).foregroundColor(.secondary).frame(width: 64, alignment: .leading)
                        Text(sourceText).font(.caption2).lineLimit(3).foregroundColor(.secondary)
                    }
                }

                if data.voiceProvider == nil && !speakers.isEmpty {
                    VoiceStylePicker(speakers: speakers, selection: speakerBinding(data))
                    Text("対応する感情・スタイルだけを表示します。変更後は「この設定で再生成」で反映します。")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                if data.voiceProvider == nil {
                    Group {
                        NumericPropertyControl(label: "音量", value: voiceNumeric({ $0.volume }, { $0.volume = max(0, $1) }), range: 0...2, decimalPlaces: 2, resetValue: 1)
                        NumericPropertyControl(label: "パン", value: voiceNumeric({ $0.pan }, { $0.pan = $1 }), range: -1...1, decimalPlaces: 2, resetValue: 0)
                        NumericPropertyControl(label: "声の高さ", value: voiceNumeric({ $0.pitch }, { $0.pitch = $1 }), range: -0.15...0.15, decimalPlaces: 3, resetValue: 0)
                        NumericPropertyControl(label: "読み上げ速度", value: voiceNumeric({ $0.speed }, { $0.speed = max(0.5, $1) }), range: 0.5...2, decimalPlaces: 2, unit: "×", resetValue: 1)
                        NumericPropertyControl(label: "抑揚", value: voiceNumeric({ $0.intonation }, { $0.intonation = max(0, $1) }), range: 0...2, decimalPlaces: 2, resetValue: 1)
                        NumericPropertyControl(label: "開始無音", value: voiceNumeric({ $0.preSilence }, { $0.preSilence = max(0, $1) }), range: 0...2, decimalPlaces: 2, unit: "秒")
                        NumericPropertyControl(label: "終了無音(余韻)", value: voiceNumeric({ $0.postSilence }, { $0.postSilence = max(0, $1) }), range: 0...2, decimalPlaces: 2, unit: "秒")
                    }
                    regenerationButton { await regenerateVoiceVox(data) }
                        .disabled(isRegenerating || data.sourceText == nil || data.speakerID == nil)
                } else if data.voiceProvider == "A.I.VOICE2" {
                    Text("音声元: A.I.VOICE2 ／ 話者: \(data.voiceLibrary ?? "未指定")")
                        .font(.caption)
                    ForEach(AIVoice2Parameter.allCases) { parameter in
                        NumericPropertyControl(
                            label: parameter.label,
                            value: voiceNumeric(
                                { $0[keyPath: parameter.keyPath] },
                                { $0[keyPath: parameter.keyPath] = parameter.clamp($1) }
                            ),
                            range: parameter.range, step: 0.01, decimalPlaces: 2,
                            resetValue: parameter.defaultValue
                        )
                    }
                    ForEach(aiv2StyleNames(data), id: \.self) { style in
                        NumericPropertyControl(
                            label: style,
                            value: voiceNumeric(
                                { $0.styleWeights?[style] ?? 0 },
                                { settings, value in
                                    var weights = settings.styleWeights ?? [:]
                                    weights[style] = min(1, max(0, value))
                                    settings.styleWeights = weights
                                }
                            ),
                            range: 0...1, step: 0.01, decimalPlaces: 2, resetValue: 0
                        )
                    }
                    regenerationButton { await regenerateAIVoice2(data) }
                        .disabled(isRegenerating || data.sourceText == nil || data.voiceLibrary?.isEmpty != false)
                } else if data.voiceProvider == SofTalkSupport.providerID {
                    Text("音声元: SofTalk ／ 話者: \(SofTalkSupport.displayName(for: data.voiceLibrary ?? "未指定"))")
                        .font(.caption)
                    NumericPropertyControl(
                        label: "音量",
                        value: voiceNumeric({ $0.volume }, { $0.volume = min(2, max(0, $1)) }),
                        range: 0...2, step: 0.01, decimalPlaces: 2, resetValue: 1
                    )
                    NumericPropertyControl(
                        label: "読み上げ速度",
                        value: voiceNumeric({ $0.speed }, { $0.speed = min(2, max(0.5, $1)) }),
                        range: 0.5...2, step: 0.01, decimalPlaces: 2, unit: "×", resetValue: 1
                    )
                    NumericPropertyControl(
                        label: "声の高さ",
                        value: voiceNumeric({ $0.pitch }, { $0.pitch = min(2, max(0.5, $1)) }),
                        range: 0.5...2, step: 0.01, decimalPlaces: 2, unit: "×", resetValue: 1
                    )
                    regenerationButton { await regenerateSofTalk(data) }
                        .disabled(isRegenerating || data.sourceText == nil || data.voiceLibrary?.isEmpty != false)
                } else if let provider = data.voiceProvider {
                    Text("音声元: \(provider) ／ 再合成は製品側で行ってください").font(.caption)
                }

                Divider()
                HStack(alignment: .top, spacing: 6) {
                    Text("説明欄").font(Theme.labelFont).foregroundColor(.secondary).frame(width: 64, alignment: .leading)
                    TextField("利用条件などのメモ", text: licenseNotesBinding(), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                }

                Divider()
                Text("以下は現在のエンジンでは未対応です:").font(.caption2).foregroundColor(.secondary)
                Toggle("エコー設定", isOn: .constant(false)).disabled(true).controlSize(.small)
                Toggle("カスタムボイス設定", isOn: .constant(false)).disabled(true).controlSize(.small)
                Text("外部製品のWAV監視は、音声パネルで製品名を選び「監視フォルダー…」から設定します。").font(.caption2).foregroundColor(.secondary)
                Text("音声エフェクト一覧は下の「エフェクト一覧」を共通で使用します。").font(.caption2).foregroundColor(.secondary)
            }
            .task { await loadSpeakers() }
        )
    }

    private func regenerationButton(_ action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            if isRegenerating { ProgressView().controlSize(.small) }
            else { Text("この設定で再生成") }
        }
        .font(.caption)
    }

    private func aiv2StyleNames(_ data: AudioClipData) -> [String] {
        let saved = data.voiceSettings.styleWeights?.keys.map { $0 } ?? []
        return Array(Set(store.aiv2Catalog.styleNames + saved)).sorted()
    }

    private func preview(_ data: AudioClipData) {
        let url = store.assetsDirectory.appendingPathComponent(data.fileName)
        NSSound(contentsOf: url, byReference: true)?.play()
    }

    private func loadSpeakers() async {
        speakers = (try? await store.voiceEngine.availableSpeakers()) ?? []
    }

    private func speakerBinding(_ data: AudioClipData) -> Binding<Int?> {
        Binding(
            get: { data.speakerID },
            set: { newValue in
                store.beginUndoableChange()
                var updated = primary
                guard case .audio(var d) = updated.content else { return }
                d.speakerID = newValue
                updated.content = .audio(d)
                store.updateClip(updated)
            }
        )
    }

    private func licenseNotesBinding() -> Binding<String> {
        Binding(
            get: { data.licenseNotes },
            set: { newValue in
                var updated = primary
                guard case .audio(var d) = updated.content else { return }
                d.licenseNotes = newValue
                updated.content = .audio(d)
                store.updateClip(updated)
            }
        )
    }

    private var data: AudioClipData {
        guard case .audio(let d) = primary.content else { return AudioClipData(fileName: "") }
        return d
    }

    private func voiceNumeric(
        _ get: @escaping (VoiceSettings) -> Double,
        _ set: @escaping (inout VoiceSettings, Double) -> Void
    ) -> Binding<Double?> {
        store.numericBinding(
            get: { clip in guard case .audio(let d) = clip.content else { return 0 }; return get(d.voiceSettings) },
            set: { clip, newValue in
                guard case .audio(var d) = clip.content else { return }
                set(&d.voiceSettings, newValue)
                clip.content = .audio(d)
            }
        )
    }

    private func regenerateVoiceVox(_ data: AudioClipData) async {
        guard data.voiceProvider == nil, let sourceText = data.sourceText, let speakerID = data.speakerID else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        let original = primary
        let projectID = store.project.id
        let sceneID = store.currentSceneID
        let directory = store.assetsDirectory
        do {
            let speech = try await store.voiceEngine.synthesize(text: sourceText, speakerID: speakerID, settings: data.voiceSettings)
            guard store.project.id == projectID, store.currentSceneID == sceneID,
                  store.assetsDirectory == directory else { throw SpeechRegeneration.Failure.targetChanged }
            let fileName = "voice_\(UUID().uuidString).wav"
            let updatedTimeline = try SpeechRegeneration.replacing(
                original: original, in: store.currentTimeline, speech: speech, fileName: fileName,
                mouthSpeeds: Dictionary(uniqueKeysWithValues: store.project.characters.map { ($0.id, $0.defaultMouthSpeed) }))
            try speech.audioData.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            store.beginUndoableChange()
            store.currentTimeline = updatedTimeline
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func regenerateAIVoice2(_ data: AudioClipData) async {
        guard data.voiceProvider == "A.I.VOICE2", let sourceText = data.sourceText,
              let speakerName = data.voiceLibrary, !speakerName.isEmpty else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        let original = primary
        let projectID = store.project.id
        let sceneID = store.currentSceneID
        let directory = store.assetsDirectory
        do {
            let exported = try await store.aiv2Automation.synthesize(.init(
                text: sourceText, speakerName: speakerName,
                settings: data.voiceSettings.validatedForAIVoice2()
            ))
            defer { exported.removeTemporaryFiles() }
            let analysis = try ExternalVoiceImport.analyze(url: exported.wavURL)
            let speech = SynthesizedSpeech(
                audioData: try Data(contentsOf: exported.wavURL),
                moraTimings: [], duration: analysis.duration
            )
            guard store.project.id == projectID, store.currentSceneID == sceneID,
                  store.assetsDirectory == directory else { throw SpeechRegeneration.Failure.targetChanged }
            let fileName = "voice_\(UUID().uuidString).wav"
            let updatedTimeline = try SpeechRegeneration.replacing(
                original: original, in: store.currentTimeline, speech: speech, fileName: fileName,
                mouthSpeeds: [:], expectedProvider: "A.I.VOICE2",
                amplitudeMouthKeyframes: analysis.mouthKeyframes
            )
            try speech.audioData.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            store.beginUndoableChange()
            store.currentTimeline = updatedTimeline
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func regenerateSofTalk(_ data: AudioClipData) async {
        guard data.voiceProvider == SofTalkSupport.providerID,
              let sourceText = data.sourceText,
              let profileID = data.voiceLibrary, !profileID.isEmpty else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        let original = primary
        let projectID = store.project.id
        let sceneID = store.currentSceneID
        let directory = store.assetsDirectory
        do {
            let generated = try await SofTalkSynthesisService.speech(
                text: sourceText,
                profileID: profileID,
                settings: data.voiceSettings.validatedForSofTalk(),
                mouthSpeed: 1
            )
            guard store.project.id == projectID, store.currentSceneID == sceneID,
                  store.assetsDirectory == directory else { throw SpeechRegeneration.Failure.targetChanged }
            let fileName = "voice_\(UUID().uuidString).wav"
            let updatedTimeline = try SpeechRegeneration.replacing(
                original: original,
                in: store.currentTimeline,
                speech: generated.speech,
                fileName: fileName,
                mouthSpeeds: [:],
                expectedProvider: SofTalkSupport.providerID,
                amplitudeMouthKeyframes: generated.mouthKeyframes
            )
            try generated.speech.audioData.write(
                to: directory.appendingPathComponent(fileName), options: .atomic
            )
            store.beginUndoableChange()
            store.currentTimeline = updatedTimeline
        } catch { store.errorMessage = error.localizedDescription }
    }
}
