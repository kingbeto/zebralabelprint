# Zebra Label Print

Print ZPL label files to your Zebra printer from macOS. Files can be `.zpl` or `.txt` — what matters is that the content is valid ZPL, not the extension.

![Zebra Label Print — choose a ZPL file, pick your printer, preview labels, and print](docs/screenshot.png)

## Requirements

- macOS 13 or later
- Mac with Apple silicon (M1 or later). Intel Macs are not supported.
- The Zebra **CUPS driver** installed on your Mac — this is a **Zebra / macOS printer requirement**, not something Zebra Label Print installs or enforces. Zebra requires their driver for printing on macOS; this app simply sends jobs to printers that are already set up in CUPS. Follow [Zebra’s guide to install the CUPS driver on macOS](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false).
- Your Zebra printer added in **System Settings → Printers & Scanners**

## Install

**TL;DR** — Apple silicon Mac (macOS 13+). First, set up your printer the way **Zebra** requires: [install their CUPS driver](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false) and add the printer in System Settings (this is not part of installing Zebra Label Print). Then download the [`.dmg` release](https://github.com/kingbeto/zebralabelprint/releases/latest), drag **ZebraLabelPrint.app** to **Applications**, open it, pick a `.zpl` or `.txt` file with ZPL inside, click **Print**.

### 1. Set up your Zebra printer in CUPS (required by Zebra, not this app)

Zebra Label Print does not install drivers or configure printers. It only lists printers that macOS already exposes through **CUPS** and sends ZPL to the queue you pick. That only works if you have already completed Zebra’s own setup: install their official CUPS driver and add the printer in **System Settings → Printers & Scanners**.

**Check from Terminal** — you should see at least one Zebra printer queue:

```bash
lpstat -a | grep -i zebra
```

Example output when it is set up:

```
Zebra_Technologies_ZTC_ZD410-203dpi_ZPL accepting requests since ...
```

If that command prints nothing, your Mac is not ready to print to Zebra yet — follow [Zebra’s guide to install the CUPS driver on macOS](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false) and add the printer in **System Settings → Printers & Scanners**. That step comes from Zebra’s printing stack, not from Zebra Label Print.

To confirm the CUPS print system itself is running:

```bash
lpstat -r
```

You should see `scheduler is running`.

### 2. Install Zebra Label Print

Download **`ZebraLabelPrint-arm64.dmg`** from the [latest GitHub release](https://github.com/kingbeto/zebralabelprint/releases/latest), then:

1. Open the `.dmg` file.
2. Drag **ZebraLabelPrint.app** to the **Applications** folder.
3. Eject the disk image.

The app is now in your **Applications** folder (`/Applications/`), available from Launchpad and Spotlight.

For a quick test, you can run the app directly from the mounted disk image — but drag it to Applications when you plan to keep using it.

## How to use

1. Open **Zebra Label Print**.
2. Choose your label file (`.zpl` or `.txt` — the file picker opens on launch). The content must be ZPL; the extension is only for convenience.
3. Pick your printer from the dropdown if needed. The app remembers your choice. On first launch it tries to select a printer whose name contains “zebra”.
4. Check the preview on the right.
5. Click **Print**.

## Preview

The preview shows how your labels should look, whether your file is named `.zpl` or `.txt`. It needs an internet connection. Physical output may differ slightly from the preview.

Preview shows the first label only (Labelary rate limits). Printing still sends every label in the file.

## Label size

Choose the size that matches your label roll. This sets the preview proportions. The default is 2″ × 1″.

## Horizontal offset

If labels print slightly off-center, use the **Horizontal offset** slider (in millimeters). Positive values shift content to the right; negative values shift left. Your setting is saved automatically.

## First launch

macOS may block the app the first time you open it because it is not signed by Apple. Right-click the app, choose **Open**, then click **Open** again. You can also allow it in **System Settings → Privacy & Security**.

## Troubleshooting

- **No printers listed** — Zebra Label Print only shows queues already in CUPS. Install [Zebra’s CUPS driver](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false) and add your printer in **System Settings → Printers & Scanners**.
- **Print fails** — Confirm the printer is connected and has labels loaded. Try printing a test page from System Settings.
- **No preview** — Check your internet connection. Preview uses an online rendering service.
- **File won’t open or preview fails** — Make sure the file contains ZPL commands (e.g. `^XA` … `^XZ`), even if it uses a `.txt` extension.

## For developers

Build instructions, architecture notes, and command-line details are in [TECHNICAL.md](TECHNICAL.md).

## License

GPL-3.0 — see [LICENSE](LICENSE).

## Author

**Alberto Pardo Saleme** — [LinkedIn](https://www.linkedin.com/in/alberto-pardo-saleme/)
