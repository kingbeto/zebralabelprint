import AppKit
import Foundation

enum SetupRequirementStatus {
    case passed
    case failed
    case warning
}

struct SetupRequirement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let status: SetupRequirementStatus
    let blocksPrinting: Bool
}

enum SetupLinks {
    static let zebraCUPSDriverGuide = URL(
        string: "https://support.zebra.com/article/Install-CUPS-Driver-for-Zebra-Printer-in-Mac-OS?redirect=false"
    )!

    static func openZebraDriverGuide() {
        NSWorkspace.shared.open(zebraCUPSDriverGuide)
    }

    static func openPrinterSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.printfax",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

enum SetupRequirementsChecker {
    static func evaluate(
        cupsRunning: Bool,
        zebraPrinters: [String],
        selectedPrinter: String,
        printerQueueStatus: PrinterQueueStatus?
    ) -> [SetupRequirement] {
        var items: [SetupRequirement] = []

        items.append(
            SetupRequirement(
                id: "cups",
                title: "CUPS print system",
                detail: cupsRunning
                    ? "Print scheduler is running."
                    : "CUPS is not running. Use the ↻ button to restart it (administrator password required).",
                status: cupsRunning ? .passed : .failed,
                blocksPrinting: true
            )
        )

        let hasZebraQueue = !zebraPrinters.isEmpty
        items.append(
            SetupRequirement(
                id: "zebra_queue",
                title: "Zebra printer in macOS",
                detail: hasZebraQueue
                    ? "Found: \(zebraPrinters.joined(separator: ", "))"
                    : "No Zebra queue yet. Install Zebra’s CUPS driver and add the printer in System Settings — this is required by Zebra, not by this app.",
                status: hasZebraQueue ? .passed : .failed,
                blocksPrinting: true
            )
        )

        let hasPrinter = !selectedPrinter.isEmpty
        items.append(
            SetupRequirement(
                id: "printer_selected",
                title: "Printer selected",
                detail: hasPrinter
                    ? selectedPrinter
                    : "Pick the Zebra queue to print to.",
                status: hasPrinter ? .passed : .failed,
                blocksPrinting: true
            )
        )

        if hasPrinter, let queueStatus = printerQueueStatus {
            let requirementStatus: SetupRequirementStatus
            switch queueStatus {
            case .ready:
                requirementStatus = .passed
            case .paused, .offline:
                requirementStatus = .failed
            case .unknown:
                requirementStatus = .warning
            }

            items.append(
                SetupRequirement(
                    id: "printer_ready",
                    title: "Print queue",
                    detail: "\(queueStatus.shortLabel). \(queueStatus.detail)",
                    status: requirementStatus,
                    blocksPrinting: queueStatus.blocksPrinting
                )
            )
        }

        return items
    }

    static func canPrint(_ requirements: [SetupRequirement], isPrinting: Bool) -> Bool {
        guard !isPrinting else { return false }
        return requirements.allSatisfy { requirement in
            !requirement.blocksPrinting || requirement.status == .passed
        }
    }

    static func printBlockedReason(_ requirements: [SetupRequirement]) -> String? {
        requirements
            .first(where: { $0.blocksPrinting && $0.status != .passed })
            .map(\.detail)
    }
}
