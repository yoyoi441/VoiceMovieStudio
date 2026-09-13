import SwiftUI
import VMSCore

struct AIStoryboardImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let result: AIStoryboardImportResult
    let characterNames: [UUID: String]
    let timelineConflict: Bool
    let apply: (Bool) -> Void

    @State private var acceptsOutdatedSource = false
    @State private var overwritesTimelineChanges = false

    private var canApply: Bool {
        (!result.isSourceOutdated || acceptsOutdatedSource) &&
            (!timelineConflict || overwritesTimelineChanges) && result.changedCount > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "rectangle.2.swap")
                Text("AI絵コンテの差分確認").font(.title2).bold()
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("差分を適用して仮組み") { apply(overwritesTimelineChanges) }
                    .buttonStyle(.borderedProminent).disabled(!canApply)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    if result.isSourceOutdated || timelineConflict || !result.warnings.isEmpty {
                        warningPanel
                    }
                    Text("変更内容").font(.headline)
                    LazyVStack(spacing: 8) {
                        ForEach(Array(result.differences.enumerated()), id: \.offset) { _, difference in
                            DifferenceRow(difference: difference, characterNames: characterNames)
                        }
                    }
                    Text("適用すると、字幕・立ち絵・既に生成済みの音声をタイムラインへ仮組みします。台詞または話者が変わったコマは音声未生成へ戻ります。素材ファイル本体や通常のタイムライン項目は追加・削除しません。操作全体は1回のUndoで戻せます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 520, idealHeight: 680)
    }

    private var summary: some View {
        let counts = Dictionary(grouping: result.differences, by: \.kind).mapValues(\.count)
        return HStack(spacing: 10) {
            SummaryBadge(title: "追加", count: counts[.added, default: 0], color: .green)
            SummaryBadge(title: "変更", count: counts[.modified, default: 0], color: .blue)
            SummaryBadge(title: "削除", count: counts[.removed, default: 0], color: .red)
            SummaryBadge(title: "変更なし", count: counts[.unchanged, default: 0], color: .secondary)
            Spacer()
            Text("適用後 \(result.storyboard.cards.count)コマ")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var warningPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("確認が必要です", systemImage: "exclamationmark.triangle.fill").bold()
                .foregroundStyle(.orange)
            ForEach(result.warnings, id: \.self) { Text("• \($0)").font(.caption) }
            if timelineConflict {
                Text("• 絵コンテ由来の項目がタイムライン側で変更されています。適用時に、その項目だけを再作成します。")
                    .font(.caption)
            }
            if result.isSourceOutdated {
                Toggle("書き出し後の変更を理解し、現在との差分を確認しました", isOn: $acceptsOutdatedSource)
            }
            if timelineConflict {
                Toggle("タイムライン側で変更した絵コンテ由来項目を上書きする", isOn: $overwritesTimelineChanges)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SummaryBadge: View {
    let title: String
    let count: Int
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title) \(count)").font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(color.opacity(0.1), in: Capsule())
    }
}

private struct DifferenceRow: View {
    let difference: AIStoryboardDifference
    let characterNames: [UUID: String]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(kindTitle)
                .font(.caption.bold()).foregroundStyle(kindColor)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(indexTitle).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(speakerTitle).font(.caption).bold()
                }
                if let before = difference.before, let after = difference.after, difference.kind == .modified {
                    if before.dialogue != after.dialogue {
                        changeLine(label: "台詞", before: before.dialogue, after: after.dialogue)
                    } else {
                        Text(after.dialogue).lineLimit(2)
                    }
                    if before.speakerID != after.speakerID {
                        changeLine(label: "話者", before: speaker(before.speakerID), after: speaker(after.speakerID))
                    }
                    if before.durationFrames != after.durationFrames {
                        changeLine(label: "尺", before: "\(before.durationFrames)フレーム", after: "\(after.durationFrames)フレーム")
                    }
                    if before.transitionFrames != after.transitionFrames {
                        changeLine(label: "移動", before: "\(before.transitionFrames ?? 0)フレーム", after: "\(after.transitionFrames ?? 0)フレーム")
                    }
                    if before.placements != after.placements {
                        Text("配置・表情を変更").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text((difference.after ?? difference.before)?.dialogue ?? "").lineLimit(3)
                }
                if let note = difference.note, !note.isEmpty {
                    Label(note, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(kindColor.opacity(0.25)))
    }

    private var kindTitle: String {
        switch difference.kind {
        case .added: "追加"
        case .modified: "変更"
        case .removed: "削除"
        case .unchanged: "変更なし"
        }
    }
    private var kindColor: Color {
        switch difference.kind {
        case .added: .green
        case .modified: .blue
        case .removed: .red
        case .unchanged: .secondary
        }
    }
    private var indexTitle: String {
        switch (difference.oldIndex, difference.newIndex) {
        case let (old?, new?) where old != new: "\(old + 1) → \(new + 1)コマ目"
        case let (_, new?): "\(new + 1)コマ目"
        case let (old?, _): "元の\(old + 1)コマ目"
        default: ""
        }
    }
    private var speakerTitle: String { speaker((difference.after ?? difference.before)?.speakerID) }
    private func speaker(_ id: UUID?) -> String { id.flatMap { characterNames[$0] } ?? "字幕のみ" }

    @ViewBuilder
    private func changeLine(label: String, before: String, after: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            Text(before).strikethrough().foregroundStyle(.secondary).lineLimit(2)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
            Text(after).lineLimit(2)
        }
        .font(.caption)
    }
}
