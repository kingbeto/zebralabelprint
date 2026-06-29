# Zebra Label Print — Technical Notes

Developer documentation for building, extending, and debugging the app.

## Project layout

```
ZebraLabelPrint/
├── ZebraLabelPrintApp.swift      @main entry point
├── ContentView.swift             SwiftUI layout, setup checklist UI
├── PrintViewModel.swift          State, persistence, print/preview orchestration, label selection parsing
├── PrinterDpmm.swift             DPMM inference from CUPS queue name
├── CUPSPrinterService.swift      lpstat / lpr, queue status, pause/resume/cancel, CUPS restart
├── SetupRequirements.swift       Setup checklist rules and Zebra driver links
├── ZPLPreviewService.swift       Labelary API, ZPL parsing, offset, label count, print resolution
├── LabelPreviewContainer.swift   Label roll preview UI
├── ZebraLabelPrint.entitlements  Hardened runtime (not App Store sandboxed)
├── Info.plist                    App metadata + admin-authorization usage string
└── Assets.xcassets/

ZebraLabelPrintTests/
├── ZPLParserTests.swift
├── ZPLModifierTests.swift
└── LabelSelectionParserTests.swift
```

- **Xcode project:** `ZebraLabelPrint.xcodeproj`
- **Target / scheme:** `ZebraLabelPrint`
- **Bundle ID:** `com.zebra.ZebraLabelPrint`
- **Deployment target:** macOS 13
- **Architecture:** arm64 only (`ARCHS = arm64` on the app target; `i386` excluded)
- **Window size:** 1640 × 1040 default; sidebar controls column 460 pt wide; preview fills remaining width

## UI layout (`ContentView.swift`)

- **Controls column** — fixed 460 pt width; **Print labels** section always visible with fixed-height option row and hint area to avoid layout shift when switching scope or loading a file
- **Preview column** — expands to fill remaining window width; label image scales to fit the preview area
- **`PrintLabelScope`** — at the top of `PrintViewModel.swift` (`all`, `range`, `pages`); `LabelSelectionParser` and `LabelSelectionError` are in the same file for module visibility

## Printing

The app sends raw ZPL to CUPS via `lpr`:

```bash
lpr -P "QUEUE_NAME" -l /path/to/job.zpl
```

ZPL is written to a temporary file and passed to `lpr` as a path argument. Piping large jobs on stdin was truncated (~1 KB); the temp-file approach submits the full job.

Before printing, the app runs `cupsenable` and `cupsaccept` on the selected queue when needed.

### Partial print selection

`PrintViewModel.resolvedPrintIndices()` maps the UI scope to 1-based label indices:

| Scope | Behavior |
|-------|----------|
| `all` | Every expanded label |
| `range` | Inclusive `printRangeFrom` … `printRangeTo` (clamped to file) |
| `pages` | Parsed list: `1`, `10`, `1, 5, 10-20` (macOS print-dialog style) |

`ZPLParser.buildPrintZPL(from:oneBasedIndices:)` joins only the selected expanded blocks. The section is disabled when `labelsToPrintCount <= 1` or no file is selected; hints explain why (`printSelectionHint`).

### Queue control

`CUPSPrinterService` exposes:

- `pausePrinterQueue` — `cupsdisable`
- `resumePrinterQueue` — `cupsenable` + `cupsaccept`
- `cancelAllJobs` — `cancel -a QUEUE`
- `pendingJobCount` — `lpstat -o QUEUE`

The sidebar **PrinterQueueStatusBanner** wires these to `PrintViewModel`.

Printer queue names come from `lpstat -a` (CUPS names, not display names). Example: `Zebra_Technologies_ZTC_ZD410-203dpi_ZPL`.

### Horizontal offset

When the offset slider is non-zero, the app shifts X coordinates on `^FO`, `^FT`, `^GB`, and `^GC` by `offsetMM × dpmm` dots before print and preview. Positive mm moves content to the right. DPMM comes from `ZebraPrintResolutionOption.resolvedDpmm` (Auto parses the printer queue name, e.g. `203dpi` → 8 dpmm).

### Print resolution (`ZebraPrintResolutionOption`)

| ID | DPMM | Use |
|----|------|-----|
| `auto` | from printer name | Default |
| `8` | 8 | 203 dpi preview / offset |
| `12` | 12 | 300 dpi preview / offset |
| `24` | 24 | 600 dpi preview / offset |

Does **not** rescale ZPL sent to the printer — only preview, offset math, and **Print definition** display.

### Setup checklist and privileged CUPS restart

`SetupRequirements.swift` evaluates CUPS (`lpstat -r`), Zebra queue presence, printer selection, and queue state (`lpoptions` / `lpstat -p`).

The ↻ control restarts CUPS with `launchctl kickstart -k system/org.cups.cupsd` via AppleScript administrator privileges. The app is not App Store sandboxed so this prompt can succeed with a local admin password.

## Label counting and expansion

`ZPLParser.printableLabelCount(from:)` returns `0` when the file is empty or contains no `^XA`. Otherwise it returns `expandedLabelZPLBlocks(from:).count`.

`expandedLabelZPLBlocks(from:)`:

1. Split the file into `^XA…^XZ` blocks (or treat the whole file as one block)
2. Read `^PQ` per block (default 1)
3. Normalize each block to `^PQ1` and repeat it `^PQ` times — one array entry per **physical** label

Printing sends only the ZPL for indices chosen in **Print labels** via `buildPrintZPL(from:oneBasedIndices:)`. Parsing lives in `LabelSelectionParser` at the bottom of `PrintViewModel.swift`.

## Preview

Preview is rendered by the [Labelary](http://labelary.com) API (`api.labelary.com`). The app:

1. Renders **one label at a time** — `renderExpandedLabel(atOneBasedIndex:…)` for the preview picker; Labelary rate limits apply
2. Waits **200 ms** before each Labelary HTTPS request; offset slider changes are debounced 300 ms; preview label number changes are debounced before refresh
3. Uses the user-selected label size for aspect ratio in `LabelPreviewContainer`
4. Uses `resolvedDpmm` from the print resolution picker for Labelary `dpmm` and offset

Requests go to Labelary over **HTTPS**, so no App Transport Security exception is needed. The preview panel discloses that label data is sent to labelary.com.

## Testing

Unit tests live in **ZebraLabelPrintTests** (XCTest). Run from Xcode (**⌘U**) or:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project ZebraLabelPrint.xcodeproj -scheme ZebraLabelPrint -destination 'platform=macOS' test
```

Coverage includes `ZPLParser`, `ZPLModifier`, and `LabelSelectionParser`. CI runs the same command on push (`.github/workflows/ci.yml`).

## Persistence (UserDefaults)

| Key | Purpose |
|-----|---------|
| Saved printer queue name | Restored on launch; auto-select Zebra regex `(?i)zebra` if unset |
| Horizontal offset (mm) | Applied on launch |
| Label size ID | Default `2x1` |
| Print resolution ID | Default `auto` (`selectedPrintResolutionId`) |

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

Requires **ImageMagick** (`magick` on `PATH`) for the DMG background. Install with `brew install imagemagick` if needed.

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
2. Choose a tag (for example `v1.2.0`)
3. Title: `Zebra Label Print 1.2.0`
4. Attach `dist/ZebraLabelPrint-arm64.dmg`
5. Note in the release body: macOS 13+, Apple silicon, CUPS driver required
6. Publish release

**With GitHub CLI** (`gh`):

```bash
gh release create v1.2.0 \
  dist/ZebraLabelPrint-arm64.dmg \
  --title "Zebra Label Print 1.2.0" \
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
| Labelary limit | One label per preview request; 200 ms delay before each API call |
| Label expansion | `^PQ` copies expand to one block per physical label; print uses selected indices |
| Print label UI | Always visible; disabled when `labelsToPrintCount <= 1` or no file |
| `wasPaused` print hint | Queue status captured **before** auto-resume in `printRaw` |
| Process timeout | `lpr` / `lpstat` subprocesses time out after 30 seconds |
| CUPS requirements | Gathered off the main thread via `SetupRequirementsSnapshot` |
| Horizontal offset | Shift `^FO` / `^FT` / `^GB` / `^GC` X coordinates, not `^LS` |
| Print resolution | Preview and offset only; printer native DPI unchanged |
| CUPS queue UI | Pause / resume / cancel via `cupsdisable`, `cupsenable`, `cancel -a` |
| CUPS locale | `lpstat -r` output is localized; parse text, not English-only strings |
| SwiftUI `onChange` | Single-parameter form for macOS 13 compatibility |
| SourceKit / IDE | Optional `buildServer.json` at repo root for Xcode project indexing |
| First-launch file picker | `hasCompletedFirstLaunch` is set before `NSOpenPanel` runs; canceling on first open does not auto-prompt again — use **Choose…** |

## Discoverability (SEO)

Most users find this project through **Google** and **GitHub search** when looking for:

- how to print labels on Mac with Zebra printers
- print ZPL on Mac / macOS
- Zebra ZD410 (or ZD620, GK420d) Mac printing
- Zebra CUPS driver macOS setup
- Zebra thermal printer Mac without Windows

Keep the [README](../README.md) title, first paragraph, and **How to print labels on Mac with a Zebra printer** section aligned with those phrases. Use question-style FAQ headings (`### How do I print labels with Zebra printers on Mac OS?`) — they match real searches and help rich snippets.

Set the GitHub **About** description and **topics** from [.github/REPOSITORY.md](.github/REPOSITORY.md). Release titles should include “Mac”, “ZPL”, and “Zebra” (e.g. “Zebra Label Print 1.2.0 — print ZPL labels on Mac”).

Model names (**ZD410**, **ZD620**, **GK420d**, **ZT410**) in the README support long-tail searches. Link to [Zebra’s official CUPS driver article](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false) for driver-setup queries — this app does not replace that step.
