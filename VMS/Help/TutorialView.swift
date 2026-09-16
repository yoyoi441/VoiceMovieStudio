import SwiftUI

private struct TutorialPage {
    var title: String
    var symbol: String
    var message: String
    var tips: [String]
}

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hasCompleted: Bool
    @State private var page = 0

    private let pages = [
        TutorialPage(title: "動画づくりを始めましょう", symbol: "sparkles.rectangle.stack", message: "素材を入れて、並べて、声や字幕を付け、完成動画を書き出せます。", tips: ["このガイドはヘルプメニューからいつでも開けます", "編集内容はプロジェクトとして保存できます"]),
        TutorialPage(title: "素材を編集画面へドロップ", symbol: "square.and.arrow.down", message: "Finderから動画・画像・音声・キャラクター素材を、そのまま編集画面へドラッグしてください。", tips: ["動画・音声・画像はタイムラインへ追加されます", "プロファイルや立ち絵パーツはキャラクター管理へ登録されます", "未対応形式は理由を表示します"]),
        TutorialPage(title: "タイムラインで組み立てる", symbol: "timeline.selection", message: "アイテムの中央をドラッグして移動し、左右端をドラッグして長さを調整します。", tips: ["Spaceで再生／停止", "空き部分のクリックで赤い再生ヘッドを移動", "Command+Bで再生位置から分割"]),
        TutorialPage(title: "声・字幕・キャラクター", symbol: "waveform.and.mic", message: "音声エンジンへ接続して文章を入力すると、声・字幕・キャラクターを一度に追加できます。", tips: ["キャラクター管理で立ち絵と口画像を登録", "プレビュー上で文字やキャラクターを直接移動", "詳細パネルから音量や表示方法を調整"]),
        TutorialPage(title: "Macだけで霊夢・魔理沙向けの声", symbol: "laptopcomputer", message: "Mac内蔵の日本語音声から霊夢向け・魔理沙向けの候補を選び、音声・字幕・口パクを作れます。", tips: ["別PC・接続先・トークンは不要", "キャラクター管理で声・話速・高さを保存", "音声パネルで必ず試聴してから追加", "特定の市販音源と同じ声ではありません"]),
        TutorialPage(title: "AquesTalk Playerを使う", symbol: "waveform.badge.plus", message: "Mac版AquesTalk Playerを自分で導入すると、保存したプリセットから音声・字幕・口パクを作れます。", tips: ["起動後にPlayerのプリセット一覧を読み取って選択", "初回の利用条件確認は完了後に設定画面へ移動", "個人かつ非営利の場合のみ無償。その他は使用ライセンスが必要", "ライセンスキーはPlayer側だけで設定し、VMSには入力しません"]),
        TutorialPage(title: "クレジットを自動作成", symbol: "doc.on.clipboard", message: "「クレジット」を開くと、実際に使用している素材だけから概要欄用テキストを作成します。", tips: ["重複した素材は一つにまとめます", "作者名や配布元が不足している場合は警告します", "ボタン一つでクリップボードへコピーできます"]),
        TutorialPage(title: "このMac／リモートMacでAI編集", symbol: "sparkles", message: "同じMac、または自宅の高性能なMacを使って、文字起こし・重要箇所抽出・クリップ作成を実行できます。", tips: ["編集画面の「AI」で実行場所を選択", "このMacは127.0.0.1、リモートMacはTailnet限定HTTPSで接続", "接続先・モデル・トークンは実行場所ごとに保存", "文字起こし結果を字幕やクリップへ反映"]),
        TutorialPage(title: "AIの絵コンテを安全に仮組み", symbol: "rectangle.2.swap", message: "現在の素材と絵コンテ情報をJSONでAIへ渡し、返された編集案を差分確認してから仮組みできます。", tips: ["絵コンテ画面で「AI情報を書き出す…」を選択", "AIにはJSON内のinstructionsに従いproposalだけを編集させます", "「AI絵コンテJSONを読み込む…」で不正なIDや数値を検証", "追加・変更・削除を確認してから仮組み。Command+Zで一括取消"]),
        TutorialPage(title: "確認して動画出力", symbol: "square.and.arrow.up", message: "再生して内容を確認し、保存してから「動画出力」で完成動画を書き出します。", tips: ["保存はCommand+S", "困ったときはヘルプセンターを検索", "これで準備完了です"])
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("はじめての使い方").font(.headline)
                Spacer()
                Button("閉じる") { completeAndDismiss() }
            }
            .padding()
            Divider()
            VStack(spacing: 22) {
                Image(systemName: pages[page].symbol)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.blue)
                    .frame(height: 70)
                Text(pages[page].title).font(.title).bold()
                Text(pages[page].message)
                    .font(.title3).multilineTextAlignment(.center).foregroundColor(.secondary)
                    .frame(maxWidth: 560)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(pages[page].tips, id: \.self) { tip in
                        Label(tip, systemImage: "checkmark.circle.fill")
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
            }
            .padding(34)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle().fill(index == page ? Color.accentColor : Color.secondary.opacity(0.25)).frame(width: 8, height: 8)
                    }
                }
                Spacer()
                Button("戻る") { page -= 1 }.disabled(page == 0)
                Button(page == pages.count - 1 ? "編集を始める" : "次へ") {
                    if page == pages.count - 1 { completeAndDismiss() } else { page += 1 }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 720, height: 560)
    }

    private func completeAndDismiss() {
        hasCompleted = true
        dismiss()
    }
}
