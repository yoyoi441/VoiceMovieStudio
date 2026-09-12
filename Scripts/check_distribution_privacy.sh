#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

failed=0

scan_content() {
    label=$1
    pattern=$2
    matches=$(git grep -Il -E "$pattern" -- . ':(exclude)Scripts/check_distribution_privacy.sh' || true)
    if [ -n "$matches" ]; then
        printf '配布監査エラー: %s\n%s\n' "$label" "$matches" >&2
        failed=1
    fi
}

tracked_private_files=$(git ls-files | grep -E '(^|/)(\.env($|\.)|[^/]*(secret|credential)[^/]*|id_(rsa|ed25519)(\.pub)?$|[^/]+\.(p8|p12|pem|mobileprovision|VMS|vms|psd|psb))$' || true)
if [ -n "$tracked_private_files" ]; then
    printf '配布監査エラー: 非公開にすべきファイルが追跡されています\n%s\n' "$tracked_private_files" >&2
    failed=1
fi

scan_content 'Mac内の絶対ユーザーパスを検出しました' '/Users/[A-Za-z0-9._-]+/'
scan_content 'プライベートネットワークの固定IPを検出しました' '100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}'
scan_content '固定されたGitHubアカウントを検出しました' '(raw\.githubusercontent\.com|github\.com)/[A-Za-z0-9_.-]+/VoiceMovieStudio'
scan_content 'ハードコードされた開発チームIDを検出しました' 'DEVELOPMENT_TEAM[[:space:]]*[:=][[:space:]]*[A-Z0-9]{10}'
scan_content '秘密情報らしい文字列を検出しました' '(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z_-]{25,}|AKIA[0-9A-Z]{16})'
scan_content '個人用テスト素材の自動読込処理を検出しました' 'TemporaryDefaultCharacter|loadTemporaryDefaultCharacterIfNeeded|テスト用デフォルトキャラクター'

if [ "$failed" -ne 0 ]; then
    exit 1
fi

printf '配布監査: 個人設定・秘密情報・テスト素材の混入は見つかりませんでした。\n'
