#!/bin/zsh
set -euo pipefail

label="com.voicemoviestudio.AIWorker"
launch_file="$HOME/Library/LaunchAgents/$label.plist"
worker_root="$HOME/Library/Application Support/VoiceMovieStudioAIWorker"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
rm -f "$launch_file"
if [[ -d "$worker_root" ]]; then
  mv "$worker_root" "$HOME/.Trash/VoiceMovieStudioAIWorker-$(date +%Y%m%d-%H%M%S)"
fi
echo "AIワーカーを停止し、関連ファイルをゴミ箱へ移動しました。"
echo "必要に応じて 'tailscale serve --https=443 off' を実行してください。"
