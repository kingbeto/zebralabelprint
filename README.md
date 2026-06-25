# Zebra Label Print

Print `.zpl` label files to your Zebra printer from macOS.

## Requirements

- macOS 13 or later
- Mac with Apple silicon (M1 or later). Intel Macs are not supported.
- The Zebra **CUPS driver** installed on your Mac. This is required — the app prints through CUPS and will not work without it. Follow [Zebra’s guide to install the CUPS driver on macOS](https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false).
- Your Zebra printer added in **System Settings → Printers & Scanners**

## Install

Copy **ZebraLabelPrint.app** to your **Applications** folder (`/Applications/`). That is the standard place for macOS apps and keeps it available in Launchpad and Spotlight.

For a quick test, you can run it from **Downloads** instead — but move it to Applications when you plan to keep using it.

If you received the app as a download (for example from a GitHub release), do not put the built app inside this source folder. Use Applications on each Mac where you want to run it.

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
