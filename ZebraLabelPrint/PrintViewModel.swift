import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PrintViewModel: ObservableObject {
    @Published var selectedFileURL: URL?
    @Published var printers: [String] = []
    @Published var selectedPrinter = ""
    @Published var statusMessage = ""
    @Published var isPrinting = false
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var errorMessage = ""
    @Published var previewImages: [NSImage] = []
    @Published var previewLabelSizeInches = CGSize(width: 2, height: 1)
    @Published var isLoadingPreview = false
    @Published var previewError = ""
    @Published var previewLabelInfo = ""
    @Published var previewLimitMessage = ""
    @Published var labelsToPrintCount = 0
    @Published var horizontalOffsetMM: Double = 0
    @Published var printDefinitionInfo = ""
    @Published var selectedLabelSizeId: String = ZebraLabelSizeOption.defaultSize.id
    @Published var requirements: [SetupRequirement] = []
    @Published var isCheckingRequirements = false
    @Published var isPollingSetupStatus = false
    @Published var isRestartingCUPS = false
    @Published var printerQueueStatus: PrinterQueueStatus = .unknown

    private var previewLabels: [String] = []
    private var offsetPreviewTask: Task<Void, Never>?
    private var setupRefreshTask: Task<Void, Never>?

    // Printer wake-up after power-on can take several seconds; poll before giving up.
    private static let setupRefreshPollIntervalNanoseconds: UInt64 = 2_500_000_000
    private static let setupRefreshTimeoutNanoseconds: UInt64 = 15_000_000_000

    private let lastPrinterKey = "lastSelectedPrinter"
    private let horizontalOffsetKey = "horizontalOffsetMM"
    private let labelSizeKey = "selectedLabelSizeId"
    // case-insensitive match — queue names are all over the place
    private static let zebraPrinterPattern = try? NSRegularExpression(pattern: "(?i)zebra")

    var selectedLabelSize: ZebraLabelSizeOption {
        ZebraLabelSizeOption.option(id: selectedLabelSizeId)
    }

    var canPrint: Bool {
        selectedFileURL != nil
            && SetupRequirementsChecker.canPrint(requirements, isPrinting: isPrinting)
    }

    var isSetupChecklistComplete: Bool {
        SetupRequirementsChecker.canPrint(requirements, isPrinting: false)
    }

    var printBlockedReason: String? {
        if selectedFileURL == nil {
            return "Choose a label file first."
        }
        return SetupRequirementsChecker.printBlockedReason(requirements)
    }

    var needsZebraSetupHelp: Bool {
        requirements.contains { $0.id == "zebra_queue" && $0.status == .failed }
    }

    var labelsToPrintSummary: String {
        guard labelsToPrintCount > 0 else { return "" }
        if labelsToPrintCount == 1 {
            return "Will print 1 label."
        }
        return "Will print \(labelsToPrintCount) labels."
    }

    init() {
        horizontalOffsetMM = UserDefaults.standard.double(forKey: horizontalOffsetKey)
        if let savedSizeId = UserDefaults.standard.string(forKey: labelSizeKey),
           ZebraLabelSizeOption.standardSizes.contains(where: { $0.id == savedSizeId }) {
            selectedLabelSizeId = savedSizeId
        }
    }

    func onAppear() {
        refreshRequirements()
        // open file picker straight away, thats the whole point of the app
        if selectedFileURL == nil {
            selectFile()
        }
    }

    func refreshRequirements() {
        isCheckingRequirements = true
        defer { isCheckingRequirements = false }
        applyRequirementsCheck()
    }

    /// Poll setup status for up to ~15 s so a printer that was just turned on can come online.
    func refreshSetupStatus() {
        setupRefreshTask?.cancel()
        setupRefreshTask = Task {
            isCheckingRequirements = true
            isPollingSetupStatus = false
            defer {
                isCheckingRequirements = false
                isPollingSetupStatus = false
            }

            applyRequirementsCheck()

            guard !selectedPrinter.isEmpty else {
                statusMessage = ""
                return
            }

            if isSetupChecklistComplete {
                statusMessage = "Setup looks good."
                return
            }

            isPollingSetupStatus = true
            let started = ContinuousClock.now

            while ContinuousClock.now - started < .nanoseconds(Int64(Self.setupRefreshTimeoutNanoseconds)) {
                try? await Task.sleep(nanoseconds: Self.setupRefreshPollIntervalNanoseconds)
                guard !Task.isCancelled else { return }

                applyRequirementsCheck()

                if isSetupChecklistComplete {
                    statusMessage = "Setup looks good."
                    return
                }
            }

            statusMessage = setupStatusSummaryAfterTimeout()
        }
    }

    private func applyRequirementsCheck() {
        let cupsRunning = CUPSPrinterService.isSchedulerRunning()
        loadPrinters()

        printerQueueStatus = selectedPrinter.isEmpty
            ? .unknown
            : CUPSPrinterService.printerQueueStatus(selectedPrinter)

        requirements = SetupRequirementsChecker.evaluate(
            cupsRunning: cupsRunning,
            zebraPrinters: CUPSPrinterService.zebraPrinterNames(),
            selectedPrinter: selectedPrinter,
            printerQueueStatus: selectedPrinter.isEmpty ? nil : printerQueueStatus
        )
    }

    private func setupStatusSummaryAfterTimeout() -> String {
        if isSetupChecklistComplete {
            return "Setup looks good."
        }
        switch printerQueueStatus {
        case .ready:
            return "Printer queue is ready. Complete the remaining checklist items."
        case .offline:
            return "Printer still offline after 15 seconds. Check power and USB/Wi‑Fi, then refresh again."
        case .paused:
            return "Queue is still paused. Tap Resume if the printer is on."
        case .unknown:
            return "Queue status unclear after 15 seconds. Try refresh again."
        }
    }

    func openZebraDriverGuide() {
        SetupLinks.openZebraDriverGuide()
    }

    func openPrinterSettings() {
        SetupLinks.openPrinterSettings()
    }

    func restartCUPS() {
        guard !isRestartingCUPS else { return }

        isRestartingCUPS = true
        defer { isRestartingCUPS = false }

        switch CUPSPrinterService.restartCUPSScheduler() {
        case .success:
            statusMessage = "CUPS restarted."
            refreshRequirements()
        case .failure(let error):
            if case CUPSPrinterService.AdminCommandError.cancelled = error {
                statusMessage = ""
                return
            }
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    func refreshCUPSChecklistItem() {
        let cupsRunning = requirements.first(where: { $0.id == "cups" })?.status == .passed
            || CUPSPrinterService.isSchedulerRunning()

        if cupsRunning {
            refreshRequirements()
            statusMessage = "CUPS status refreshed."
            return
        }

        restartCUPS()
    }

    func resumeSelectedPrinter() {
        guard !selectedPrinter.isEmpty else { return }

        if CUPSPrinterService.resumePrinterQueue(selectedPrinter) {
            statusMessage = "Printer queue resumed."
            refreshRequirements()
        } else {
            errorMessage = "Could not resume \"\(selectedPrinter)\". Open Printer settings and clear Pause, or check that the printer is connected."
            showErrorAlert = true
        }
    }

    func resetHorizontalOffset() {
        horizontalOffsetMM = 0
        persistHorizontalOffset()
        Task { await loadPreview() }
    }

    func persistLabelSize() {
        UserDefaults.standard.set(selectedLabelSizeId, forKey: labelSizeKey)
    }

    func persistHorizontalOffset() {
        UserDefaults.standard.set(horizontalOffsetMM, forKey: horizontalOffsetKey)
    }

    func schedulePreviewRefresh() {
        offsetPreviewTask?.cancel()
        // Debounce slider changes; each loadPreview still waits 200 ms inside ZPLPreviewService.
        offsetPreviewTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await loadPreview()
        }
    }

    private func preparedZPL(from zpl: String) -> String {
        let dpmm = ZPLLabelSize.dpmm(forPrinter: selectedPrinter)
        return ZPLModifier.applyHorizontalOffset(
            to: zpl,
            offsetMM: horizontalOffsetMM,
            dpmm: dpmm
        )
    }

    func loadPrinters() {
        printers = CUPSPrinterService.printerNames()

        if printers.isEmpty {
            selectedPrinter = ""
            return
        }

        if let savedPrinter = UserDefaults.standard.string(forKey: lastPrinterKey),
           printers.contains(savedPrinter) {
            selectedPrinter = savedPrinter
            updatePrintDefinition()
            return
        }

        // no saved printer — grab first zebra-ish queue if we can
        if let zebraPrinter = printers.first(where: Self.matchesZebra) {
            selectedPrinter = zebraPrinter
            persistPrinter(zebraPrinter)
            updatePrintDefinition()
            return
        }

        selectedPrinter = ""
        updatePrintDefinition()
    }

    func updatePrintDefinition(for labelZPL: String? = nil) {
        let dpmm = ZPLLabelSize.dpmm(forPrinter: selectedPrinter)
        let dpi = Int((Double(dpmm) * 25.4).rounded())
        let size = selectedLabelSize

        guard labelZPL != nil else {
            printDefinitionInfo = """
            DPMM: \(dpmm) · \(dpi) dpi
            Label size: \(size.name)
            """
            return
        }

        let widthMM = size.widthInches * 25.4
        let heightMM = size.heightInches * 25.4
        let widthDots = Int((size.widthInches * Double(dpi)).rounded())
        let heightDots = Int((size.heightInches * Double(dpi)).rounded())

        printDefinitionInfo = """
        DPMM: \(dpmm) · \(dpi) dpi
        Label size: \(size.name)
        Label: \(String(format: "%.1f", widthMM)) × \(String(format: "%.1f", heightMM)) mm
        Dots: \(widthDots) × \(heightDots) (^PW × ^LL)
        """
    }

    func persistPrinter(_ printer: String) {
        guard !printer.isEmpty else { return }
        UserDefaults.standard.set(printer, forKey: lastPrinterKey)
    }

    private static func matchesZebra(_ printerName: String) -> Bool {
        let range = NSRange(printerName.startIndex..., in: printerName)
        return zebraPrinterPattern?.firstMatch(in: printerName, range: range) != nil
    }

    func selectFile() {
        let panel = NSOpenPanel()
        panel.title = "Select ZPL File"
        panel.message = "Choose the ZPL file you want to print."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zpl, .plainText, .data]

        guard panel.runModal() == .OK, let url = panel.url else {
            if selectedFileURL == nil {
                statusMessage = "No file selected."
            }
            refreshRequirements()
            return
        }

        selectedFileURL = url
        statusMessage = ""
        previewLabels = []
        refreshLabelsToPrintCount()
        refreshRequirements()
        Task { await loadPreview() }
    }

    private func refreshLabelsToPrintCount() {
        guard let fileURL = selectedFileURL,
              let zpl = readZPL(from: fileURL) else {
            labelsToPrintCount = 0
            return
        }
        labelsToPrintCount = ZPLParser.labelCount(from: preparedZPL(from: zpl))
    }

    private func readZPL(from fileURL: URL) -> String? {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: fileURL),
              !data.isEmpty,
              let zpl = String(data: data, encoding: .utf8) else {
            return nil
        }
        return zpl
    }

    func loadPreview() async {
        guard let fileURL = selectedFileURL else {
            previewImages = []
            previewError = ""
            previewLabelInfo = ""
            previewLimitMessage = ""
            labelsToPrintCount = 0
            return
        }

        isLoadingPreview = true
        previewError = ""
        previewLimitMessage = ""
        defer { isLoadingPreview = false }

        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let zplData: Data
        do {
            zplData = try Data(contentsOf: fileURL)
        } catch {
            previewImages = []
            previewError = "Could not read file: \(error.localizedDescription)"
            return
        }

        guard !zplData.isEmpty else {
            previewImages = []
            previewError = "The selected file is empty."
            labelsToPrintCount = 0
            return
        }

        guard let zpl = String(data: zplData, encoding: .utf8) else {
            previewImages = []
            previewError = "The ZPL file could not be read as text."
            labelsToPrintCount = 0
            return
        }

        let adjustedZPL = preparedZPL(from: zpl)
        previewLabels = ZPLParser.splitLabels(from: adjustedZPL)
        labelsToPrintCount = ZPLParser.labelCount(from: adjustedZPL)

        do {
            let dpmm = ZPLLabelSize.dpmm(forPrinter: selectedPrinter)
            let labelSize = selectedLabelSize.sizeInches
            previewLabelSizeInches = labelSize
            updatePrintDefinition(for: previewLabels.first)
            // First label only; ZPLPreviewService sleeps 200 ms before each Labelary POST (rate limit).
            previewImages = try await ZPLPreviewService.renderLabels(
                zpl: adjustedZPL,
                printerName: selectedPrinter,
                labelSizeInches: labelSize,
                startIndex: 0,
                count: 1
            )

            if labelsToPrintCount > 1 {
                previewLimitMessage = "Showing the first label of \(labelsToPrintCount)."
            } else {
                previewLimitMessage = "This is the only label in the file."
            }

            let dimensions = String(
                format: "%@ @ %d dpmm",
                selectedLabelSize.name,
                dpmm
            )
            previewLabelInfo = dimensions
            if horizontalOffsetMM != 0 {
                previewLabelInfo += String(format: " · offset %+.1f mm", horizontalOffsetMM)
            }
        } catch {
            previewImages = []
            previewLabelInfo = ""
            previewLimitMessage = ""
            previewError = error.localizedDescription
        }
    }

    func printFile() {
        guard canPrint else {
            errorMessage = printBlockedReason ?? "Complete the setup checklist before printing."
            showErrorAlert = true
            return
        }

        guard let fileURL = selectedFileURL else {
            errorMessage = "Select a ZPL file first."
            showErrorAlert = true
            return
        }

        guard !selectedPrinter.isEmpty else {
            errorMessage = "Select a printer first."
            showErrorAlert = true
            return
        }

        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let zplData: Data
        do {
            zplData = try Data(contentsOf: fileURL)
        } catch {
            errorMessage = "Could not read \"\(fileURL.lastPathComponent)\": \(error.localizedDescription)"
            statusMessage = ""
            showErrorAlert = true
            return
        }

        guard !zplData.isEmpty else {
            errorMessage = "The selected file is empty."
            statusMessage = ""
            showErrorAlert = true
            return
        }

        guard let zpl = String(data: zplData, encoding: .utf8) else {
            errorMessage = "The ZPL file could not be read as text."
            statusMessage = ""
            showErrorAlert = true
            return
        }

        let adjustedData = Data(preparedZPL(from: zpl).utf8)

        isPrinting = true
        statusMessage = "Sending to printer…"
        defer { isPrinting = false }

        persistPrinter(selectedPrinter)

        switch CUPSPrinterService.printRaw(zplData: adjustedData, to: selectedPrinter) {
        case .success(let result):
            refreshRequirements()
            switch result {
            case .sent:
                statusMessage = "Print job sent successfully."
            case .queuedWhilePaused:
                statusMessage = "Job queued, but the printer was paused. It has been resumed — check the printer if nothing prints."
            }
            showSuccessAlert = true
        case .failure(let error):
            errorMessage = error.localizedDescription
            statusMessage = ""
            showErrorAlert = true
        }
    }
}

private extension UTType {
    static let zpl = UTType(filenameExtension: "zpl") ?? .plainText
}
