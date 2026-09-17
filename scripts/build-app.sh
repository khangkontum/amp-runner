#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
swift build --package-path "$ROOT" -c release
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
APP="$ROOT/dist/Amp Runner.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/AmpRunner" "$APP/Contents/MacOS/AmpRunner"
cp "$BIN/AmpRunnerService" "$APP/Contents/Helpers/AmpRunnerService"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AmpRunnerMenu.pdf" "$APP/Contents/Resources/AmpRunnerMenu.pdf"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP/Contents/Helpers/AmpRunnerService"
codesign --force --sign - "$APP"
echo "Built $APP"
