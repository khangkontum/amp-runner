## Install

Requires macOS 14 or later on **Apple Silicon** (M1 or newer). Intel Macs are not supported by this download.

1. Download the `macos-arm64.zip` asset below and unzip it.
2. Drag **Amp Runner.app** into **Applications**, then open it.
3. This personal app is **ad-hoc signed, not notarized**. If macOS blocks it, attempt to open it first, then use **System Settings → Privacy & Security → Open Anyway**, if available. Only approve downloads you trust; managed Macs may prohibit this override.
4. Install the [Amp CLI](https://ampcode.com/manual), run `amp login`, and add your project folders in the app.

No Xcode, build tools, or Apple developer account is needed to use the download. Amp itself is not bundled.

**Updating:** stop the runner and quit the manager before replacing the app. Reopen it and start the runner again. Your saved folders and runner ID are retained; re-enable Start at login if desired.

The `.sha256` asset contains the ZIP's SHA-256 checksum. Download both files into the same directory and run `shasum -a 256 -c Amp-Runner-<version>-macos-arm64.zip.sha256` there to check the archive.
