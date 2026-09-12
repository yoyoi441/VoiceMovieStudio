import SwiftUI
import VMSCore

/// §7: the detail panel for whatever's selected on the timeline. Content-specific
/// sections (text/character/audio/image) only appear when every selected clip shares the
/// same content kind — mixing e.g. a text clip and an audio clip in one selection still
/// lets you adjust their shared "共通" properties together, just not kind-specific ones.
struct InspectorView: View {
    @Environment(ProjectStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                if let primary = store.selectedClips.first {
                    header(primary: primary, count: store.selectedClips.count)

                    switch uniformKind {
                    case .text:
                        TextClipInspector(primary: primary, isMultiSelect: store.selectedClips.count > 1)
                    case .character:
                        TachieInspector(primary: primary)
                    case .audio:
                        VoiceSettingsInspector(primary: primary)
                    case .image:
                        imageSection(primary: primary)
                    case .video:
                        videoSection(primary: primary)
                    case nil:
                        EmptyView()
                    }

                    CommonPropertiesSection(clip: primary)
                } else {
                    Text("クリップを選択してください")
                        .foregroundColor(.secondary)
                        .padding(.top, 24)
                }
            }
            .padding()
        }
        .frame(minWidth: 280, maxWidth: 340)
        .background(Theme.panelBackground)
    }

    private func header(primary: Clip, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(count > 1 ? "クリップ (\(count)個選択中)" : "クリップ").font(.headline)
            LabeledContent("開始") { Text(String(format: "%.2fs", primary.startTime)) }
            LabeledContent("長さ") { Text(String(format: "%.2fs", primary.duration)) }
            if primary.isLocked {
                Label("ロック中", systemImage: "lock.fill").font(.caption).foregroundColor(.secondary)
            }
            Divider()
        }
    }

    private enum ContentKind { case text, character, audio, image, video }

    private var uniformKind: ContentKind? {
        let kinds = Set(store.selectedClips.map { clip -> ContentKind in
            switch clip.content {
            case .text: return .text
            case .character: return .character
            case .audio: return .audio
            case .image: return .image
            case .video: return .video
            }
        })
        return kinds.count == 1 ? kinds.first : nil
    }

    private func videoSection(primary: Clip) -> some View {
        guard case .video(let data) = primary.content else { return AnyView(EmptyView()) }
        return AnyView(
            PropertySection("動画") {
                Text("ファイル: \(data.fileName)").font(.caption).foregroundColor(.secondary)
                NumericPropertyControl(
                    label: "素材開始",
                    value: store.numericBinding(
                        get: { if case .video(let d) = $0.content { d.sourceStartTime } else { 0 } },
                        set: { if case .video(var d) = $0.content { d.sourceStartTime = max(0, $1); $0.content = .video(d) } }
                    ),
                    range: 0...3600, decimalPlaces: 2, unit: "秒"
                )
                NumericPropertyControl(
                    label: "音量",
                    value: store.numericBinding(
                        get: { if case .video(let d) = $0.content { d.volume } else { 1 } },
                        set: { if case .video(var d) = $0.content { d.volume = min(max(0, $1), 2); $0.content = .video(d) } }
                    ),
                    range: 0...2, decimalPlaces: 2, unit: "×", resetValue: 1
                )
                TogglePropertyControl(
                    label: "ミュート",
                    value: store.mixedBinding(
                        get: { if case .video(let d) = $0.content { d.isMuted } else { false } },
                        set: { if case .video(var d) = $0.content { d.isMuted = $1; $0.content = .video(d) } }
                    )
                )
            }
        )
    }

    private func imageSection(primary: Clip) -> some View {
        guard case .image(let data) = primary.content else { return AnyView(EmptyView()) }
        return AnyView(
            PropertySection("画像") {
                Text("ファイル: \(data.fileName)").font(.caption).foregroundColor(.secondary)
                NumericPropertyControl(
                    label: "拡大率",
                    value: store.numericBinding(
                        get: { if case .image(let d) = $0.content { d.scale } else { 1 } },
                        set: { if case .image(var d) = $0.content { d.scale = max(0.1, $1); $0.content = .image(d) } }
                    ),
                    range: 0.1...3, decimalPlaces: 2, unit: "×", resetValue: 1
                )
            }
        )
    }
}
