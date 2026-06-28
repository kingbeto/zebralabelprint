# Zebra Label Print — print ZPL labels on Mac from your Zebra printer

**Free, open-source macOS app to print ZPL label files to Zebra thermal printers** — ZD410, ZD620, GK420d, ZT series, and any other Zebra queue set up in macOS **CUPS**. Pick a `.zpl` or `.txt` file, preview the label, and send raw ZPL to the printer. Built for **Apple silicon Macs** (macOS 13+).

Looking for a way to **print shipping labels, barcode labels, or warehouse labels on a Mac** without Windows-only tools? This app sends **ZPL (Zebra Programming Language)** straight to your printer queue — the same format Zebra Design Studio, ERP systems, and shipping platforms export.

**[Download Zebra Label Print for Mac (DMG)](https://github.com/kingbeto/zebralabelprint/releases/latest)** · [Releases](https://github.com/kingbeto/zebralabelprint/releases) · [Source & build notes](TECHNICAL.md)

![Zebra Label Print macOS app — select a ZPL file, choose your Zebra printer, preview the label, and print on Mac](docs/screenshot.png)

## Features

- **Print ZPL on macOS** — send full label jobs to CUPS (`lpr`); works with multi-label files and `^PQ` quantities
- **Live label preview** — renders the first label via [Labelary](http://labelary.com) before you print
- **Setup checklist** — CUPS, Zebra driver, printer queue, and “ready to print” status in one place
- **Horizontal offset** — fix labels that print slightly off-center (millimeter slider)
- **Printer wake-up refresh** — polls for up to 15 seconds after you power the printer on so status turns green without repeated clicks
- **Remembers** your printer, label size, and offset between launches

## Requirements

- **macOS 13** or later
- **Apple silicon Mac** (M1 or later). Intel Macs are not supported.
- The Zebra **CUPS driver** installed on your Mac — this is a **Zebra / macOS printer requirement**, not something Zebra Label Print installs or enforces. Zebra requires their driver for printing on macOS; this app simply sends jobs to printers that are already set up in CUPS. Follow [Zebra’s guide to install the CUPS driver on macOS](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false).
- Your Zebra printer added in **System Settings → Printers & Scanners**

## Install

**TL;DR** — Apple silicon Mac (macOS 13+). First, set up your printer the way **Zebra** requires: [install their CUPS driver](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false) and add the printer in System Settings (this is not part of installing Zebra Label Print). Then download **[ZebraLabelPrint-arm64.dmg](https://github.com/kingbeto/zebralabelprint/releases/download/v1.2.0/ZebraLabelPrint-arm64.dmg)**, drag **ZebraLabelPrint.app** to **Applications**, open it, pick a `.zpl` or `.txt` file with ZPL inside, click **Print**.

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

Download **[ZebraLabelPrint-arm64.dmg](https://github.com/kingbeto/zebralabelprint/releases/download/v1.2.0/ZebraLabelPrint-arm64.dmg)** (v1.2.0), then:

1. Open the `.dmg` file.
2. Drag **ZebraLabelPrint.app** to the **Applications** folder.
3. Eject the disk image.

The app is now in your **Applications** folder (`/Applications/`), available from Launchpad and Spotlight.

For a quick test, you can run the app directly from the mounted disk image — but drag it to Applications when you plan to keep using it.

## How to use

1. Open **Zebra Label Print**.
2. Review the **setup checklist** at the bottom of the sidebar. It collapses when everything is green; expand it to see details or use **Check again**.
3. Choose your label file (`.zpl` or `.txt` — the file picker opens on launch). The content must be ZPL; the extension is only for convenience.
4. Pick your printer from the dropdown if needed. The app remembers your choice. On first launch it tries to select a printer whose name contains “zebra”.
5. Check the preview on the right.
6. Click **Print**.

The app shows how many labels will print (including `^PQ` copies and multi-label files). Preview renders only the first label.

## Setup checklist

Before printing, the app checks:

- **CUPS print system** — use the ↻ button to refresh status or restart CUPS (administrator password required if CUPS is down)
- **Zebra printer in macOS** — driver installed and queue visible to CUPS
- **Printer selected** — queue chosen in the app
- **Print queue** — ready, paused, or offline; use **Resume** if the queue is paused

When all checks pass, the checklist collapses to a compact green bar. **Print** stays disabled until a label file is selected and the checklist is clear.

## Preview

The preview shows how your labels should look, whether your file is named `.zpl` or `.txt`. It needs an internet connection. Physical output may differ slightly from the preview.

Preview shows the first label only (Labelary rate limits). Printing still sends every label in the file.

## Label size

Choose the size that matches your label roll. This sets the preview proportions. The default is 2″ × 1″.

## Horizontal offset

If labels print slightly off-center, use the **Horizontal offset** slider (in millimeters). Positive values shift content to the right; negative values shift left. Your setting is saved automatically.

## First launch

macOS may block the app the first time you open it because it is not signed by Apple. Right-click the app, choose **Open**, then click **Open** again. You can also allow it in **System Settings → Privacy & Security**.

## Frequently asked questions

### How do I print ZPL files on a Mac?

Install [Zebra’s CUPS driver](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false), add your printer in **System Settings → Printers & Scanners**, then use **Zebra Label Print** to open a `.zpl` or `.txt` file and click **Print**. The app sends raw ZPL to the printer through CUPS — no Windows VM required.

### Does this work with my Zebra printer (ZD410, ZD620, etc.)?

Yes, if macOS lists the printer in CUPS (see `lpstat -a | grep -i zebra`). Common desktop models such as **ZD410**, **ZD420**, **ZD620**, and **GK420d** work when the official Zebra macOS driver is installed.

### Can I print `.txt` files that contain ZPL?

Yes. The file extension does not matter; the content must be valid **ZPL** (`^XA` … `^XZ` blocks).

### Do I need Zebra Setup Utilities on Mac?

You still need Zebra’s **CUPS driver** and a printer queue in macOS. This app is a lightweight alternative for **day-to-day ZPL printing and preview** — not a driver installer.

### Is Zebra Label Print free?

Yes. Open source under [GPL-3.0](LICENSE). Download the DMG from [GitHub Releases](https://github.com/kingbeto/zebralabelprint/releases/latest).

### Why Apple silicon only?

The distributed build is **arm64** only. See [TECHNICAL.md](TECHNICAL.md) if you want to compile for other targets yourself.

## Troubleshooting

- **No printers listed** — Zebra Label Print only shows queues already in CUPS. Install [Zebra’s CUPS driver](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false) and add your printer in **System Settings → Printers & Scanners**.
- **Setup checklist stays red** — Expand the checklist for details. Restart CUPS with ↻ if needed, or open **Printer settings** from the help links. After turning the printer on, tap **Refresh** and wait — the app polls for up to 15 seconds.
- **Print succeeds but nothing prints** — The queue may be paused. Expand the checklist and tap **Resume**, or resume the printer in System Settings.
- **Print fails** — Confirm the printer is connected and has labels loaded. Try printing a test page from System Settings.
- **No preview** — Check your internet connection. Preview uses an online rendering service (Labelary). Wait a moment after moving the offset slider — requests are paced to avoid rate limits.
- **File won’t open or preview fails** — Make sure the file contains ZPL commands (e.g. `^XA` … `^XZ`), even if it uses a `.txt` extension.

## For developers

Build instructions, architecture notes, and command-line details are in [TECHNICAL.md](TECHNICAL.md). Recommended GitHub **description and topics** for discoverability: [.github/REPOSITORY.md](.github/REPOSITORY.md).

## License

GPL-3.0 — see [LICENSE](LICENSE).

## Author

**Alberto Pardo Saleme** — [LinkedIn](https://www.linkedin.com/in/alberto-pardo-saleme/)
