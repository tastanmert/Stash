#!/bin/zsh
# Builds Stash.app into /Applications (or the folder given as $1).
# The app is built by Xcode (project.yml → Stash.xcodeproj via XcodeGen) so the Shortcuts
# actions get their App Intents metadata; `swift test` still runs the tests from Package.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${1:-/Applications}"
APP="build/Stash.app"

rm -rf build/Stash.app build/AppIcon.iconset && mkdir -p build
xcodegen generate --spec project.yml --quiet
# Universal binary: runs natively on Apple Silicon and Intel Macs.
xcodebuild -project Stash.xcodeproj -scheme Stash -configuration Release -derivedDataPath build/dd \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -quiet build
cp -R build/dd/Build/Products/Release/Stash.app "$APP"

# Icon
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Sign with the local Apple Development certificate when there is one, so macOS keeps
# permissions (login item, folders) across rebuilds. Ad-hoc otherwise.
IDENTITY="${STASH_SIGN:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
[ "$IDENTITY" = "-" ] && IDENTITY=""
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Signed: ${IDENTITY:-ad-hoc}"
mkdir -p "$DEST"
rm -rf "$DEST/Stash.app"
cp -R "$APP" "$DEST/"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/Stash.app" >/dev/null 2>&1 || true
echo "Ready: $DEST/Stash.app"
