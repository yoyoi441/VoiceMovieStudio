#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
version="${1:-1.0.0}"
output_root="$project_root/dist"
archive_path="$output_root/VoiceMovieStudio-$version.xcarchive"
dmg_path="$output_root/VoiceMovieStudio-$version.dmg"
work_root="$(mktemp -d /tmp/VoiceMovieStudio-distribution.XXXXXX)"
stage_path="$work_root/VoiceMovieStudio-$version"
temporary_dmg="$work_root/VoiceMovieStudio-$version.dmg"
trap 'rm -rf "$work_root"' EXIT

cd "$project_root"
Scripts/check_distribution_privacy.sh
mkdir -p "$output_root"
xcodegen generate
swift test --package-path Packages/VMSCore
xcodebuild archive \
  -project VMS.xcodeproj \
  -scheme VMS \
  -configuration Release \
  -archivePath "$archive_path" \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  UPDATE_FEED_URL="${UPDATE_FEED_URL:-https://example.invalid/VoiceMovieStudio/appcast.xml}" \
  OTHER_SWIFT_FLAGS="-debug-prefix-map $project_root=/Source -file-prefix-map $project_root=/Source"

mkdir -p "$stage_path/AIWorker"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr --noacl "$archive_path/Products/Applications/VoiceMovieStudio.app" "$stage_path/VoiceMovieStudio.app"
if grep -R -a -l "$project_root" "$stage_path/VoiceMovieStudio.app"; then
  echo "配布アプリ内にビルド環境の絶対パスが残っています。" >&2
  exit 1
fi
cp README.md PRIVACY.md LICENSE.txt THIRD_PARTY_NOTICES.md CHANGELOG.md "$stage_path/"
cp Tools/AIWorker/README.md Tools/AIWorker/install.sh Tools/AIWorker/uninstall.sh Tools/AIWorker/worker.py Tools/AIWorker/worker.plist.template "$stage_path/AIWorker/"
ln -s /Applications "$stage_path/Applications"
if [[ -n "${DEVELOPER_ID_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$stage_path/VoiceMovieStudio.app"
fi
codesign --verify --deep --strict "$stage_path/VoiceMovieStudio.app"

rm -f "$dmg_path"
hdiutil create -volname "ボイスムービースタジオ $version" -srcfolder "$stage_path" -ov -format UDZO "$temporary_dmg"
cp "$temporary_dmg" "$dmg_path"
if [[ -n "${DEVELOPER_ID_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$dmg_path"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${DEVELOPER_ID_IDENTITY:-}" ]]; then
    echo "公証にはDEVELOPER_ID_IDENTITYの設定が必要です。" >&2
    exit 1
  fi
  xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
else
  echo "NOTARY_PROFILEが未設定のためApple公証を省略しました。"
fi

shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
echo "作成完了: $dmg_path"
