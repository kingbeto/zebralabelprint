# Zebra Label Print

Print `.zpl` label files to your Zebra printer from macOS.

![Zebra Label Print — choose a ZPL file, pick your printer, preview labels, and print](docs/screenshot.png)

## Requirements

- macOS 13 or later
- Mac with Apple silicon (M1 or later). Intel Macs are not supported.
- The Zebra **CUPS driver** installed on your Mac. This is required — the app prints through CUPS and will not work without it. Follow [Zebra’s guide to install the CUPS driver on macOS](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false).
- Your Zebra printer added in **System Settings → Printers & Scanners**

## Install

### 1. Set up the Zebra CUPS driver (required)

Zebra Label Print prints through **CUPS**. Before installing the app, make sure your Zebra printer is set up with the official Zebra CUPS driver.

**Check from Terminal** — you should see at least one Zebra printer queue:

```bash
lpstat -a | grep -i zebra
```

Example output when it is set up:

```
Zebra_Technologies_ZTC_ZD410-203dpi_ZPL accepting requests since ...
```

If that command prints nothing, CUPS is not ready for Zebra yet. Install the driver and add your printer following [Zebra’s guide to install the CUPS driver on macOS](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false), then add the printer in **System Settings → Printers & Scanners**.

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
2. Choose a `.zpl` file (the file picker opens on launch).
3. Pick your printer from the dropdown if needed. The app remembers your choice. On first launch it tries to select a printer whose name contains “zebra”.
4. Check the preview on the right.
5. Click **Print**.

## Preview

The preview shows how your labels should look. It needs an internet connection. Physical output may differ slightly from the preview.

If your file has several labels, use the arrows below the preview to browse them.

## Label size

Choose the size that matches your label roll. This sets the preview proportions. The default is 2″ × 1″.

## Horizontal offset

If labels print slightly off-center, use the **Horizontal offset** slider (in millimeters). Positive values shift content to the right; negative values shift left. Your setting is saved automatically.

## First launch

macOS may block the app the first time you open it because it is not signed by Apple. Right-click the app, choose **Open**, then click **Open** again. You can also allow it in **System Settings → Privacy & Security**.

## Troubleshooting

- **No printers listed** — Add your Zebra printer in **System Settings → Printers & Scanners** and make sure it is online.
- **Print fails** — Confirm the printer is connected and has labels loaded. Try printing a test page from System Settings.
- **No preview** — Check your internet connection. Preview uses an online rendering service.

## For developers

Build instructions, architecture notes, and command-line details are in [TECHNICAL.md](TECHNICAL.md).

## License

GPL-3.0 — see [LICENSE](LICENSE).

## Author

**Alberto Pardo Saleme** — [LinkedIn](https://www.linkedin.com/in/alberto-pardo-saleme/)
