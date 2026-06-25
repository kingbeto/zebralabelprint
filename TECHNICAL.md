# Zebra Label Print — Technical Notes

Developer documentation for building, extending, and debugging the app.

## Project layout

```
ZebraLabelPrint/
├── ZebraLabelPrintApp.swift      @main entry point
├── ContentView.swift             SwiftUI layout
├── PrintViewModel.swift          State, persistence, print/preview orchestration
├── CUPSPrinterService.swift      lpstat / lpr integration
├── ZPLPreviewService.swift       Labelary API, ZPL parsing, ^LS offset injection
├── LabelPreviewContainer.swift   Label roll preview UI
├── ZebraLabelPrint.entitlements  Sandbox: print, user-selected files, network
├── Info.plist                    ATS exception for api.labelary.com (HTTP)
└── Assets.xcassets/
```

- **Xcode project:** `ZebraLabelPrint.xcodeproj`
- **Target / scheme:** `ZebraLabelPrint`
- **Bundle ID:** `com.zebra.ZebraLabelPrint`
- **Deployment target:** macOS 13
- **Architecture:** arm64 only (Apple silicon). Builds on Apple silicon Macs produce an arm64 binary; there is no Intel (x86_64) slice.
- **Window size:** 1640 × 1040

## Printing

The app sends raw ZPL to CUPS via `lpr`:

```bash
lpr -P "QUEUE_NAME" -l
```

ZPL is read in-process and piped to the subprocess stdin (avoids sandbox file-access issues with `lp -d`).

Printer queue names come from `lpstat -a` (CUPS names, not display names). Example: `Zebra_Technologies_ZTC_ZD410-203dpi_ZPL`.

### Horizontal offset

When the offset slider is non-zero, the app injects `^LS<n>` (dots) immediately after each `^XA` in the ZPL before print and preview. Conversion uses the selected printer’s DPMM from CUPS when available.

## Preview

Preview is rendered by the [Labelary](http://labelary.com) API (`api.labelary.com`). The app:

1. Splits multi-label ZPL on `^XA…^XZ` boundaries
2. Renders up to 5 labels (no dummy duplication)
3. Uses the user-selected label size for aspect ratio in `LabelPreviewContainer`

`Info.plist` includes an App Transport Security exception for HTTP access to Labelary.

## Persistence (UserDefaults)

| Key | Purpose |
|-----|---------|
| Saved printer queue name | Restored on launch; auto-select Zebra regex `(?i)zebra` if unset |
| Horizontal offset (mm) | Applied on launch |
| Label size ID | Default `2x1` |

## Build

### Prerequisites

Full **Xcode** from the Mac App Store is required (Command Line Tools alone are not enough).

Verify the active developer directory:

```bash
xcode-select -p
# Expected: /Applications/Xcode.app/Contents/Developer
```

If it shows `CommandLineTools`:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Or prefix commands with:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

### Build in Xcode

```bash
open ZebraLabelPrint.xcodeproj
```

1. Scheme: **ZebraLabelPrint**, destination: **My Mac**
2. **⌘R** to run, **⌘B** to build only
3. Release: **Product → Scheme → Edit Scheme → Run → Build Configuration → Release**

Default DerivedData output:

```
~/Library/Developer/Xcode/DerivedData/ZebraLabelPrint-*/Build/Products/Release/ZebraLabelPrint.app
```

### Build from the command line

From the repository root:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild \
  -project ZebraLabelPrint.xcodeproj \
  -scheme ZebraLabelPrint \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build
```

Output:

```
build/DerivedData/Build/Products/Release/ZebraLabelPrint.app
```

### Copy to Downloads

```bash
xcodebuild \
  -project ZebraLabelPrint.xcodeproj \
  -scheme ZebraLabelPrint \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build

rm -rf ~/Downloads/ZebraLabelPrint.app
cp -R build/DerivedData/Build/Products/Release/ZebraLabelPrint.app ~/Downloads/
```

### Install to Applications

```bash
cp -R build/DerivedData/Build/Products/Release/ZebraLabelPrint.app /Applications/
```

### Create a DMG (installer)

For a drag-to-Applications installer with background art:

```bash
./scripts/make-dmg.sh
```

Output: `dist/ZebraLabelPrint-arm64.dmg`

The script builds Release if needed, stages the app with an **Applications** shortcut, sets Finder icon positions, and compresses the image.

Minimal DMG (app only, no layout):

```bash
hdiutil create -volname "ZebraLabelPrint" \
  -srcfolder build/DerivedData/Build/Products/Release/ZebraLabelPrint.app \
  -ov -format UDZO dist/ZebraLabelPrint-arm64.dmg
```

## GitHub Releases (distributing the .app)

Do **not** commit `ZebraLabelPrint.app` or zip/dmg files to git. Ship binaries through [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) instead.

### 1. Build

Use the command-line build above. Output:

```
build/DerivedData/Build/Products/Release/ZebraLabelPrint.app
```

### 2. Package

**Zip (recommended)** — simple and works well on GitHub:

```bash
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent \
  build/DerivedData/Build/Products/Release/ZebraLabelPrint.app \
  dist/ZebraLabelPrint-arm64.zip
```

Use `ditto`, not plain `zip`, so macOS metadata and the app bundle structure stay intact.

**DMG (optional)** — drag-to-Applications installer:

```bash
./scripts/make-dmg.sh
```

Attach `dist/ZebraLabelPrint-arm64.dmg` to the release (instead of or alongside the zip).

Name assets with `-arm64` so Intel users know the build is Apple silicon only.

The `dist/` folder is gitignored.

### 3. Publish on GitHub

**In the browser**

1. Open the repo → **Releases** → **Draft a new release**
2. Choose a tag (for example `v1.0.0`)
3. Title: `Zebra Label Print 1.0.0`
4. Attach `dist/ZebraLabelPrint-arm64.zip` (and/or the DMG)
5. Note in the release body: macOS 13+, Apple silicon, CUPS driver required
6. Publish release

**With GitHub CLI** (`gh`):

```bash
gh release create v1.0.0 \
  dist/ZebraLabelPrint-arm64.zip \
  --title "Zebra Label Print 1.0.0" \
  --notes "macOS 13+. Apple silicon (arm64) only. Requires Zebra CUPS driver."
```

Users download the zip from the release page, unzip, and copy `ZebraLabelPrint.app` to `/Applications/`.

## Troubleshooting (development)

**`xcodebuild` requires Xcode`**

Xcode is installed but not selected. Use `xcode-select -s` or set `DEVELOPER_DIR` before building.

**Print works in Terminal but not in the app**

Check entitlements (`com.apple.security.print`, `com.apple.security.files.user-selected.read-only`). Confirm the queue name matches `lpstat -a` output exactly.

**Verify raw print outside the app**

```bash
cat /path/to/file.zpl | lpr -P "YourPrinter" -l
```

**Find a built app quickly**

```bash
find ~/Library/Developer/Xcode/DerivedData -name "ZebraLabelPrint.app" -path "*/Release/*" 2>/dev/null | head -1
```

## App icon

The icon is from [The Noun Project](https://thenounproject.com/) (zebra illustration). Rebuild in Xcode to refresh asset catalog output.

## Known implementation notes

| Topic | Detail |
|-------|--------|
| macOS `lp -P` | Use `lpr -P` for queue, `-l` for raw/literal ZPL |
| Labelary limit | Split ZPL per label; render individually |
| SwiftUI `onChange` | Single-parameter form for macOS 13 compatibility |
| Preview strip | Shows up to 5 real labels from the file |
