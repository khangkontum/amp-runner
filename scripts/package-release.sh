#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Usage: bash scripts/package-release.sh major.minor.patch" >&2
    exit 1
fi
if [[ "$(uname -m)" != arm64 ]]; then
    echo "This release package targets Apple Silicon; build it on an arm64 Mac." >&2
    exit 1
fi
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
# Never overwrite a local app bundle that may be running a service.
APP_OUTPUT_DIR="$TEMP" APP_VERSION="$VERSION" bash "$ROOT/scripts/build-app.sh"
APP="$TEMP/Amp Runner.app"
for EXECUTABLE in "$APP/Contents/MacOS/AmpRunner" "$APP/Contents/Helpers/AmpRunnerService"; do
    test "$(lipo -archs "$EXECUTABLE")" = arm64
    codesign --verify --strict "$EXECUTABLE"
done
codesign --verify --deep --strict "$APP"
OUTPUT="$ROOT/dist"
NAME="Amp-Runner-$VERSION-macos-arm64.zip"
mkdir -p "$OUTPUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/$NAME"
(cd "$OUTPUT" && shasum -a 256 "$NAME" > "$NAME.sha256")
echo "Release: $OUTPUT/$NAME"
echo "Checksum: $OUTPUT/$NAME.sha256"
