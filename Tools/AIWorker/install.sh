#!/bin/zsh
set -euo pipefail

worker_source="${0:A:h}/worker.py"
worker_root="$HOME/Library/Application Support/VoiceMovieStudioAIWorker"
label="com.voicemoviestudio.AIWorker"
launch_file="$HOME/Library/LaunchAgents/$label.plist"
text_model="${VIDEO_AI_TEXT_MODEL:-qwen3:14b}"
mkdir -p "$worker_root/jobs" "$HOME/Library/LaunchAgents"
cp "$worker_source" "$worker_root/worker.py"
chmod 700 "$worker_root/worker.py"
if command -v brew >/dev/null && ! command -v ffmpeg >/dev/null; then
  brew install ffmpeg
fi
if [[ ! -x "$worker_root/venv/bin/python3" ]]; then
  python3 -m venv "$worker_root/venv"
fi
if ! "$worker_root/venv/bin/python3" -c 'import mlx_whisper' 2>/dev/null; then
  "$worker_root/venv/bin/pip" install mlx-whisper
fi
if [[ ! -s "$worker_root/token" ]]; then
  openssl rand -hex 32 > "$worker_root/token"
  chmod 600 "$worker_root/token"
fi

python_path="$worker_root/venv/bin/python3"
sed -e "s|__PYTHON__|$python_path|g" \
    -e "s|__WORKER__|$worker_root/worker.py|g" \
    -e "s|__TEXT_MODEL__|$text_model|g" \
    "${0:A:h}/worker.plist.template" > "$launch_file"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
for _ in {1..25}; do
  if ! /usr/bin/nc -z 127.0.0.1 8765 2>/dev/null; then
    break
  fi
  sleep 0.2
done
if /usr/bin/nc -z 127.0.0.1 8765 2>/dev/null; then
  echo "ポート8765を別のプロセスが使用しています。既存のAIワーカーを終了してから再実行してください。" >&2
  exit 1
fi
launchctl bootstrap "gui/$(id -u)" "$launch_file"
launchctl kickstart -k "gui/$(id -u)/$label"
if command -v tailscale >/dev/null; then
  tailscale serve --bg --yes 8765
else
  echo "Tailscale CLIが見つかりません。Tailnet経由で使用するにはTailscaleを導入し、'tailscale serve --bg --yes 8765'を実行してください。"
fi
echo "AIワーカーを起動しました。使用モデル: $text_model"
echo "接続トークンは $worker_root/token に保存しました。"
echo "接続先の確認: /Applications/Tailscale.app/Contents/MacOS/Tailscale serve status"
echo "接続トークンの確認: cat \"$worker_root/token\""
