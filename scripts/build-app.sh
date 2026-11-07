#!/bin/bash
# Builds the Swift package and wraps it in build/WinMix.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="${1:-build/WinMix.app}"
if [[ "$APP" != *.app || "$APP" == ".app" ]]; then
    echo "Output must be a path ending in .app" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/WinMix" "$APP/Contents/MacOS/WinMix"
cp "$BIN_DIR/ChromeBridge" "$APP/Contents/MacOS/ChromeBridge"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Extensions/Chrome "$APP/Contents/Resources/ChromeExtension"
cp docs/chrome-tab-volume.md "$APP/Contents/Resources/chrome-tab-volume.md"
cp docs/chrome-tab-validation.md "$APP/Contents/Resources/chrome-tab-validation.md"
cp docs/chrome-manual-validation.md "$APP/Contents/Resources/chrome-manual-validation.md"
cp -R docs/history "$APP/Contents/Resources/history"
mkdir -p "$APP/Contents/Resources/scripts"
cp scripts/install-chrome-bridge.py scripts/uninstall-chrome-bridge.py "$APP/Contents/Resources/scripts/"
codesign --force --sign - "$APP/Contents/MacOS/ChromeBridge"
codesign --force --sign - "$APP"

echo "Built $APP"
