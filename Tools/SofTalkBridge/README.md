# SofTalk連携ブリッジ

ボイスムービースタジオから、Windows PCに利用者自身がインストールしたSofTalkを呼び出してWAVを受け取るための補助プログラムです。SofTalk本体・音声合成エンジン・音源は同梱しません。

## 設定

1. Windows PCへPython 3をインストールします。
2. `bridge-config.example.json`を`bridge-config.json`へコピーし、`executable`を実際の`SofTalk.exe`へ変更します。
3. `reimu`と`marisa`の`arguments`へ、利用中のSofTalkと音源で声を一意に選べる引数を設定し、確認できたものだけ`enabled`を`true`にします。
4. 24文字以上のランダムな接続トークンを環境変数`SOFTALK_BRIDGE_TOKEN`へ設定します。
5. `python bridge.py --config bridge-config.json`で起動します。
6. 別のMacから使う場合、ブリッジを直接LANへ公開せず、Tailscale Serve等で`127.0.0.1:18881`をHTTPS公開します。
7. VMSの音声パネルでSofTalkを選び、HTTPSの接続先と同じトークンを入力します。

音声選択引数は製品・音源・版によって異なるため、VMSは番号を推測しません。必ずインストール済み製品のヘルプで確認し、両プリセットを試聴してから使ってください。`/W:`はブリッジが必ず最後に追加します。
霊夢と魔理沙へまったく同じ引数を設定した場合は取り違え防止のため、両方とも未設定としてVMSへ通知します。

## 制約

- 現行SofTalkは従来のゆっくりボイスを内蔵していません。対応音源を利用できる版・構成を利用者が正規に用意する必要があります。
- 生成音声の利用条件は、SofTalkだけでなく選択した音声合成エンジン・音源の規約にも従ってください。
- `pitch`は初期状態では引数へ変換しません。利用中の版で正しい引数を確認できた場合だけ`parameterArguments.pitch`へ設定してください。
- 読み上げ処理は直列化されます。複数のVMSから同時生成しないでください。

## 動作確認

SofTalkなしでブリッジの引数生成だけを確認できます。

```powershell
python bridge.py --self-test
```
