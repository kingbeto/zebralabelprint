# Zebra Label Print

A small macOS app for sending ZPL files to a Zebra printer via CUPS.

## What it does

1. Double-click **ZebraPrint** to launch the app.
2. Choose a `.zpl` file (the file picker opens automatically on launch).
3. Pick your printer from the dropdown if needed. Printer selection is remembered automatically. On first launch, if no printer was saved yet, the app auto-selects the first printer whose name matches `zebra` (case-insensitive).
4. Click **Print**. The app runs:

```bash
lpr -P "SELECTED_ZEBRA_PRINTER" -l
```

The `-l` option sends the ZPL as raw/literal data (already formatted for the printer).

## Preview

When you select a ZPL file, a **preview** appears on the right. It is rendered via the [Labelary](http://labelary.com) API, which simulates how the label should look. This is an approximation — your physical Zebra output may differ slightly, but it is useful for checking layout and content before printing.

## Horizontal offset

If labels print slightly off-center on the roll, use the **Horizontal offset** slider (in mm). Positive values shift content to the right; negative values shift left. The offset is applied via ZPL `^LS` and affects both preview and print. Your setting is saved automatically.

For a 2 mm shift to the right, set **+2.0 mm**.

## Requirements

- macOS 13 or later
- Xcode (to build)
- A Zebra printer already added in **System Settings → Printers & Scanners**

## Build

### Prerequisites

You need **full Xcode** from the Mac App Store (Command Line Tools alone are not enough).

Verify Xcode is selected:

```bash
xcode-select -p
```

It should show `/Applications/Xcode.app/Contents/Developer`. If it shows `CommandLineTools`, Xcode is installed but not selected. Fix it permanently:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Or prefix build commands with `DEVELOPER_DIR` (no `sudo` needed):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

### Troubleshooting

If you see:

```
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

Xcode is installed but not active. Use `sudo xcode-select -s` above, or set `DEVELOPER_DIR` before `xcodebuild`. The `cp` step will also fail if the build did not complete.

### Option 1: Build in Xcode

```bash
open ZebraPrint.xcodeproj
```

1. Set the scheme to **ZebraPrint** and the destination to **My Mac**.
2. Press **⌘R** to build and run, or **⌘B** to build only.
3. For a Release build: **Product → Scheme → Edit Scheme → Run → Build Configuration → Release**.

The built app is usually at:

```
~/Library/Developer/Xcode/DerivedData/ZebraPrint-*/Build/Products/Release/ZebraPrint.app
```

Find it quickly:

```bash
find ~/Library/Developer/Xcode/DerivedData -name "ZebraPrint.app" -path "*/Release/*" 2>/dev/null | head -1
```

### Option 2: Build from the command line

From the project folder, with a predictable output path:

```bash
cd /Users/alberto/Sites/zebra

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild \
  -project ZebraPrint.xcodeproj \
  -scheme ZebraPrint \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build
```

The `.app` will be at:

```
build/DerivedData/Build/Products/Release/ZebraPrint.app
```

### Build and copy to Downloads

```bash
cd /Users/alberto/Sites/zebra

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild \
  -project ZebraPrint.xcodeproj \
  -scheme ZebraPrint \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build

rm -rf ~/Downloads/ZebraPrint.app
cp -R build/DerivedData/Build/Products/Release/ZebraPrint.app ~/Downloads/
```

The app will be at `~/Downloads/ZebraPrint.app`.

### Install to Applications

```bash
cp -R build/DerivedData/Build/Products/Release/ZebraPrint.app /Applications/
```

### First launch

macOS may block an unsigned app on first open. Use **right-click → Open → Open**, or allow it in **System Settings → Privacy & Security**.

### Optional: create a DMG

```bash
hdiutil create -volname "ZebraPrint" \
  -srcfolder build/DerivedData/Build/Products/Release/ZebraPrint.app \
  -ov -format UDZO ZebraPrint.dmg
```

## App icon

The app icon is from [The Noun Project](https://thenounproject.com/) (zebra illustration). Rebuild in Xcode (**⌘R**) to see it in the Dock and Finder.

## Notes

- Printer names come from CUPS (`lpstat -a`), not display names. Your queue might look like `Zebra_Technologies_ZTC_ZD410-203dpi_ZPL`.
- If printing fails, check that the printer is online and that this works in Terminal:

```bash
cat /path/to/file.zpl | lpr -P "YourPrinter" -l
```

- Preview requires internet access (Labelary API).
