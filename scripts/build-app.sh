#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
if [[ -n "${APP_VERSION:-}" && ! "$APP_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "APP_VERSION must be major.minor.patch (for example, 0.1.0)." >&2
    exit 1
fi
swift build --package-path "$ROOT" -c release
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
APP="${APP_OUTPUT_DIR:-$ROOT/dist}/Amp Runner.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/AmpRunner" "$APP/Contents/MacOS/AmpRunner"
cp "$BIN/AmpRunnerService" "$APP/Contents/Helpers/AmpRunnerService"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP/Contents/Info.plist"
fi
cp "$ROOT/Resources/AmpRunnerMenu.pdf" "$APP/Contents/Resources/AmpRunnerMenu.pdf"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP/Contents/Helpers/AmpRunnerService"
codesign --force --sign - "$APP"
echo "Built $APP"
