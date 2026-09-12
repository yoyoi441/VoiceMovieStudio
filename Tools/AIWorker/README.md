# AIWorker

同じMacまたは別のApple Silicon Macを、文字起こし・重要箇所抽出・クリップ作成・シナリオ配置提案用のAIノードにします。

## 必要なもの

- Apple Silicon Mac
- macOS 14以降
- Homebrew
- Ollamaと任意の言語モデル
- リモート利用時は両端末で同じTailnetへ接続

## インストール

AI処理を担当するMacでターミナルを開き、`install.sh`を実行します。FFmpeg、専用Python環境、mlx-whisperを導入し、ログイン後に自動起動するワーカーを登録します。

使用するOllamaモデルを固定する場合は、次のように指定します。未指定時は`qwen3:14b`です。

```zsh
VIDEO_AI_TEXT_MODEL=qwen3:30b Tools/AIWorker/install.sh
```

完了時に表示される接続先を、編集アプリの「AI」画面へ入力してください。接続トークンは次のコマンドで確認できます。トークンを第三者へ渡さないでください。

```zsh
cat "$HOME/Library/Application Support/VoiceMovieStudioAIWorker/token"
```

リモート用の接続先が分からなくなった場合は、AIWorkerを入れたMacで次を実行します。表示結果の`https://`で始まるURLが接続先です。

```zsh
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve status
```

## このMacで使う

1. 編集に使うMac自身で`install.sh`を実行します。
2. アプリの「AI」を開き、実行場所を「このMac」にします。
3. 接続先へ`http://127.0.0.1:8765`、接続トークンへ上のコマンドで確認した値を入力します。
4. 「接続を確認」を押し、端末名と能力が表示されることを確認します。

このモードでは解析用データはネットワークへ送信されません。「このMac」ではループバックアドレス以外を登録できません。

## 別のMacで使う

1. 編集用MacとAI処理用Macを同じTailnetへ接続します。
2. AI処理用Macで`install.sh`を実行します。
3. アプリの「AI」を開き、実行場所を「リモートMac」にします。
4. 接続先へインストール時に表示された`https://端末名.ts.net/`、接続トークンへAI処理用Macで発行された値を入力します。
5. 「接続を確認」を押し、端末名と能力が表示されることを確認します。

リモート接続はHTTPSだけを受け付けます。このMac用とリモートMac用のURL・モデル・トークンは別々に保存されるため、実行場所を切り替えても再入力は不要です。

## 通信

ワーカーは`127.0.0.1:8765`だけで待ち受けます。リモート利用時だけTailscale Serveを通してTailnet内へHTTPS公開します。一般インターネットへ公開する機能は使用しません。

## 接続できない場合

- 「認証されていません」と表示される場合は、選択中の実行場所とトークンの組み合わせを確認します。
- 「接続できません」と表示される場合は、AI処理用Macでワーカーが起動しているか確認します。
- リモートだけ接続できない場合は、両方のMacが同じTailnetにあり、Tailscale ServeのHTTPS URLを使っているか確認します。
- 文字起こし能力が表示されない場合は、AI処理用Macで`install.sh`を再実行します。
- 初回処理はモデルの読み込みに時間がかかることがあります。

## ログ

- `/tmp/VoiceMovieStudioAIWorker.log`
- `/tmp/VoiceMovieStudioAIWorker.error.log`

## アンインストール

`uninstall.sh`を実行します。AIモデルやOllama本体は削除しません。
