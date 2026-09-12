# 正式配布チェックリスト

## 現在完了している項目

- [x] バージョン1.0.0
- [x] macOS 14以降
- [x] Apple Silicon／Intel Universal Binary
- [x] Hardened Runtime
- [x] 独自AppIcon
- [x] プロジェクト形式の関連付け
- [x] 個人端末・Tailnet固有値の除去
- [x] 初回チュートリアルとヘルプ
- [x] README、プライバシー、変更履歴、第三者表記
- [x] AIWorkerの導入・削除手順
- [x] Coreテスト
- [x] DMG自動生成とSHA-256

## 正式公開前に必要な項目

- [ ] Developer ID Application証明書をキーチェーンへ追加
- [ ] App Store Connect APIキーまたはApple IDでnotarytool資格を保存
- [ ] `DEVELOPER_ID_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=<プロファイル名> Scripts/build_distribution.sh 1.0.0`を実行
- [ ] `spctl -a -vv --type open VoiceMovieStudio-1.0.0.dmg`で受理を確認
- [ ] 初期状態の別Macでインストール、起動、保存、再読込、動画出力を確認
- [ ] 使用許諾文面を配布方針と対象法域に合わせて確認
- [ ] サポート窓口と配布URLをREADMEへ追加
- [ ] リリース版のバックアップを保管

## 署名について

Apple Development署名は開発・端末テスト用です。不特定多数へ警告なしで配布するにはDeveloper ID Application署名とApple公証が必要です。
