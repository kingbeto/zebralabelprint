# Zebra Label Print — Technical Notes

Developer documentation for building, extending, and debugging the app.

## Project layout

```
ZebraLabelPrint/
├── ZebraLabelPrintApp.swift      @main entry point
├── ContentView.swift             SwiftUI layout, setup checklist UI
├── PrintViewModel.swift          State, persistence, print/preview orchestration
├── CUPSPrinterService.swift      lpstat / lpr, queue status, CUPS restart
├── SetupRequirements.swift       Setup checklist rules and Zebra driver links
├── ZPLPreviewService.swift       Labelary API, ZPL parsing, offset, label count
├── LabelPreviewContainer.swift   Label roll preview UI
├── ZebraLabelPrint.entitlements  Hardened runtime (not App Store sandboxed)
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
lpr -P "QUEUE_NAME" -l /path/to/job.zpl
```

ZPL is written to a temporary file and passed to `lpr` as a path argument. Piping large jobs on stdin was truncated (~1 KB); the temp-file approach submits the full job.

Before printing, the app runs `cupsenable` and `cupsaccept` on the selected queue when needed.

Printer queue names come from `lpstat -a` (CUPS names, not display names). Example: `Zebra_Technologies_ZTC_ZD410-203dpi_ZPL`.

### Horizontal offset

When the offset slider is non-zero, the app shifts X coordinates on `^FO`, `^FT`, `^GB`, and `^GC` by `offsetMM × dpmm` dots before print and preview. Positive mm moves content to the right.

### Setup checklist and privileged CUPS restart

`SetupRequirements.swift` evaluates CUPS (`lpstat -r`), Zebra queue presence, printer selection, and queue state (`lpoptions` / `lpstat -p`).

The ↻ control restarts CUPS with `launchctl kickstart -k system/org.cups.cupsd` via AppleScript administrator privileges. The app is not App Store sandboxed so this prompt can succeed with a local admin password.

## Label counting

`ZPLParser.labelCount(from:)` estimates how many labels will print:

1. Sum `^PQ` quantities per `^XA…^XZ` block (default 1 when omitted)
2. If that is still low, count `^XA` starts (labels without a closing `^XZ` between them)
3. Otherwise use the number of `^XA…^XZ` pairs

Printing always sends the full adjusted ZPL file; the count is for UI messaging only.

## Preview

Preview is rendered by the [Labelary](http://labelary.com) API (`api.labelary.com`). The app:

1. Renders the **first label only** (Labelary rate limits; printing still sends all labels)
2. Waits **200 ms** before each Labelary HTTP request; offset slider changes are debounced 300 ms
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

**DMG (recommended)** — drag-to-Applications installer:

```bash
./scripts/make-dmg.sh
```

Attach `dist/ZebraLabelPrint-arm64.dmg` to the release.

**Zip (optional)**:

```bash
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent \
  build/DerivedData/Build/Products/Release/ZebraLabelPrint.app \
  dist/ZebraLabelPrint-arm64.zip
```

Use `ditto`, not plain `zip`, so macOS metadata and the app bundle structure stay intact.

Name assets with `-arm64` so Intel users know the build is Apple silicon only.

The `dist/` folder is gitignored.

### 3. Publish on GitHub

**In the browser**

1. Open the repo → **Releases** → **Draft a new release**
2. Choose a tag (for example `v1.1.0`)
3. Title: `Zebra Label Print 1.1.0`
4. Attach `dist/ZebraLabelPrint-arm64.dmg`
5. Note in the release body: macOS 13+, Apple silicon, CUPS driver required
6. Publish release

**With GitHub CLI** (`gh`):

```bash
gh release create v1.1.0 \
  dist/ZebraLabelPrint-arm64.dmg \
  --title "Zebra Label Print 1.1.0" \
  --notes "macOS 13+. Apple silicon (arm64) only. Requires Zebra CUPS driver."
```

Users download the DMG, open it, and drag `ZebraLabelPrint.app` to `/Applications/`.

## Troubleshooting (development)

**`xcodebuild` requires Xcode`**

Xcode is installed but not selected. Use `xcode-select -s` or set `DEVELOPER_DIR` before building.

**Print works in Terminal but not in the app**

Confirm the queue name matches `lpstat -a` output exactly. CUPS restart needs a local macOS administrator password (the app is not App Store sandboxed so privileged `launchctl` can run).

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
| Large print jobs | Stage ZPL in a temp file; do not pipe multi-KB jobs to `lpr` stdin |
| Labelary limit | Preview first label only; 200 ms delay before each API call |
| Label count | `^PQ` sum, then `^XA` count, then `^XA…^XZ` pair count |
| Horizontal offset | Shift `^FO` / `^FT` / `^GB` / `^GC` X coordinates, not `^LS` |
| CUPS locale | `lpstat -r` output is localized; parse text, not English-only strings |
| SwiftUI `onChange` | Single-parameter form for macOS 13 compatibility |
