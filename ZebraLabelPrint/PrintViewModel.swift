import AppKit
import Foundation
import UniformTypeIdentifiers

enum PrintLabelScope: String, CaseIterable, Identifiable {
    case all
    case range
    case pages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All labels"
        case .range:
            return "From … to …"
        case .pages:
            return "Labels"
        }
    }
}

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
    @Published var previewLabelNumber = 1
    @Published var labelsToPrintCount = 0
    @Published var horizontalOffsetMM: Double = 0
    @Published var selectedLabelSizeId: String = ZebraLabelSizeOption.defaultSize.id
    @Published var selectedResolutionId: String = ZebraPrintResolutionOption.defaultOption.id
    @Published var requirements: [SetupRequirement] = []
    @Published var isCheckingRequirements = false
    @Published var isPollingSetupStatus = false
    @Published var isRestartingCUPS = false
    @Published var printerQueueStatus: PrinterQueueStatus = .unknown
    @Published var pendingJobCount = 0
    @Published var printScope: PrintLabelScope = PrintLabelScope.all
    @Published var printRangeFrom = 1
    @Published var printRangeTo = 1
    @Published var printPagesText = ""
    @Published var lastPrintedLabelCount = 0

    private var offsetPreviewTask: Task<Void, Never>?
    private var previewLabelTask: Task<Void, Never>?
    private var setupRefreshTask: Task<Void, Never>?
    private var requirementsRefreshTask: Task<Void, Never>?

    // Monotonic tokens so an out-of-order async result can't overwrite a newer one.
    private var requirementsGeneration = 0
    private var previewGeneration = 0

    // Printer wake-up after power-on can take several seconds; poll before giving up.
    private static let setupRefreshPollIntervalNanoseconds: UInt64 = 2_500_000_000
    private static let setupRefreshTimeoutNanoseconds: UInt64 = 15_000_000_000

    private let lastPrinterKey = "lastSelectedPrinter"
    private let horizontalOffsetKey = "horizontalOffsetMM"
    private let labelSizeKey = "selectedLabelSizeId"
    private let resolutionKey = "selectedPrintResolutionId"
    private let hasCompletedFirstLaunchKey = "hasCompletedFirstLaunch"
    // case-insensitive match — queue names are all over the place
    private static let zebraPrinterPattern = try? NSRegularExpression(pattern: "(?i)zebra")

    var selectedLabelSize: ZebraLabelSizeOption {
        ZebraLabelSizeOption.option(id: selectedLabelSizeId)
    }

    var resolvedDpmm: Int {
        ZebraPrintResolutionOption.resolvedDpmm(
            optionId: selectedResolutionId,
            printerName: selectedPrinter
        )
    }

    var resolutionSummary: String {
        let dpmm = resolvedDpmm
        let dpi = ZebraPrintResolutionOption.nominalDpi(forDpmm: dpmm)
        if selectedResolutionId == ZebraPrintResolutionOption.defaultOption.id {
            return "Using \(dpi) dpi · \(dpmm) dpmm, detected from printer."
        }
        return "Using \(dpi) dpi · \(dpmm) dpmm."
    }

    var canPrint: Bool {
        selectedFileURL != nil
            && labelsToPrintCount > 0
            && hasValidPrintSelection
            && SetupRequirementsChecker.canPrint(requirements, isPrinting: isPrinting)
    }

    var hasValidPrintSelection: Bool {
        guard labelsToPrintCount > 0 else { return false }
        if case .success = resolvedPrintIndices() {
            return true
        }
        return false
    }

    var isSetupChecklistComplete: Bool {
        SetupRequirementsChecker.canPrint(requirements, isPrinting: false)
    }

    var printBlockedReason: String? {
        if selectedFileURL == nil {
            return "Choose a label file first."
        }
        if labelsToPrintCount == 0 {
            return "No printable labels found in this file."
        }
        if case .failure(let error) = resolvedPrintIndices() {
            return error.localizedDescription
        }
        return SetupRequirementsChecker.printBlockedReason(requirements)
    }

    var printersForPicker: [String] {
        let zebra = printers.filter { Self.matchesZebra($0) }
        let other = printers.filter { !Self.matchesZebra($0) }
        return zebra + other
    }

    func printerDisplayName(_ printer: String) -> String {
        Self.matchesZebra(printer) ? printer : "\(printer) (non-Zebra)"
    }

    var needsZebraSetupHelp: Bool {
        requirements.contains { $0.id == "zebra_queue" && $0.status == .failed }
    }

    var labelsToPrintSummary: String {
        guard labelsToPrintCount > 0 else { return "" }
        let selected = selectedPrintLabelCount
        if printScope == PrintLabelScope.all || selected == labelsToPrintCount {
            if labelsToPrintCount == 1 {
                return "Will print 1 label."
            }
            return "Will print \(labelsToPrintCount) labels."
        }
        if selected == 1 {
            return "Will print 1 of \(labelsToPrintCount) labels."
        }
        return "Will print \(selected) of \(labelsToPrintCount) labels."
    }

    var selectedPrintLabelCount: Int {
        guard labelsToPrintCount > 0 else { return 0 }
        switch resolvedPrintIndices() {
        case .success(let indices):
            return indices.count
        case .failure:
            return 0
        }
    }

    var isPrintLabelSelectionEnabled: Bool {
        selectedFileURL != nil && labelsToPrintCount > 1
    }

    var printSelectionHint: String {
        if selectedFileURL == nil {
            return "Choose a ZPL file first."
        }
        if labelsToPrintCount == 1 {
            return "This file contains only one label."
        }
        if labelsToPrintCount == 0 {
            if isLoadingPreview {
                return "Loading label count…"
            }
            return "No printable labels found in this file."
        }
        switch printScope {
        case PrintLabelScope.all:
            return ""
        case PrintLabelScope.range:
            return "Prints labels \(printRangeFrom) through \(printRangeTo)."
        case PrintLabelScope.pages:
            return "Examples: 1 · 10 · 1, 5, 10-20"
        }
    }

    private func resolvedPrintIndices() -> Result<[Int], LabelSelectionError> {
        LabelSelectionParser.resolvedIndices(
            scope: printScope,
            labelsToPrintCount: labelsToPrintCount,
            printRangeFrom: printRangeFrom,
            printRangeTo: printRangeTo,
            printPagesText: printPagesText
        )
    }

    init() {
        horizontalOffsetMM = UserDefaults.standard.double(forKey: horizontalOffsetKey)
        if let savedSizeId = UserDefaults.standard.string(forKey: labelSizeKey),
           ZebraLabelSizeOption.standardSizes.contains(where: { $0.id == savedSizeId }) {
            selectedLabelSizeId = savedSizeId
        }
        if let savedResolutionId = UserDefaults.standard.string(forKey: resolutionKey),
           ZebraPrintResolutionOption.allOptions.contains(where: { $0.id == savedResolutionId }) {
            selectedResolutionId = savedResolutionId
        }
    }

    func onAppear() {
        refreshRequirements()
        guard !UserDefaults.standard.bool(forKey: hasCompletedFirstLaunchKey) else { return }
        UserDefaults.standard.set(true, forKey: hasCompletedFirstLaunchKey)
        if selectedFileURL == nil {
            selectFile()
        }
    }

    func refreshRequirements() {
        let printer = selectedPrinter
        requirementsRefreshTask?.cancel()
        requirementsGeneration += 1
        let generation = requirementsGeneration
        isCheckingRequirements = true
        requirementsRefreshTask = Task {
            let snapshot = await Task.detached(priority: .utility) {
                SetupRequirementsSnapshot.gather(selectedPrinter: printer)
            }.value
            // Only the latest refresh applies its snapshot and clears the spinner — a superseded
            // task returns without touching shared state, so a stale gather can't overwrite a
            // newer one and a cancelled task can't leave the spinner stuck on.
            guard generation == requirementsGeneration else { return }
            applyRequirementsCheck(snapshot)
            isCheckingRequirements = false
        }
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

            let printer = selectedPrinter
            let snapshot = await Task.detached(priority: .utility) {
                SetupRequirementsSnapshot.gather(selectedPrinter: printer)
            }.value
            applyRequirementsCheck(snapshot)

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

                let pollPrinter = selectedPrinter
                applyRequirementsCheck(await Task.detached(priority: .utility) {
                    SetupRequirementsSnapshot.gather(selectedPrinter: pollPrinter)
                }.value)

                if isSetupChecklistComplete {
                    statusMessage = "Setup looks good."
                    return
                }
            }

            statusMessage = setupStatusSummaryAfterTimeout()
        }
    }

    private func applyRequirementsCheck(_ snapshot: SetupRequirementsSnapshot) {
        printers = snapshot.printers
        let printerBefore = selectedPrinter
        reconcileSelectedPrinter()

        if selectedPrinter.isEmpty {
            printerQueueStatus = .unknown
            pendingJobCount = 0
        } else if selectedPrinter == printerBefore, selectedPrinter == snapshot.gatheredForPrinter {
            printerQueueStatus = snapshot.printerQueueStatus
            pendingJobCount = snapshot.pendingJobCount
        } else {
            printerQueueStatus = CUPSPrinterService.printerQueueStatus(selectedPrinter)
            pendingJobCount = CUPSPrinterService.pendingJobCount(for: selectedPrinter)
        }

        requirements = SetupRequirementsChecker.evaluate(
            cupsRunning: snapshot.cupsRunning,
            zebraPrinters: snapshot.zebraPrinters,
            selectedPrinter: selectedPrinter,
            printerQueueStatus: selectedPrinter.isEmpty ? nil : printerQueueStatus
        )
    }

    private func reconcileSelectedPrinter() {
        if printers.isEmpty {
            selectedPrinter = ""
            return
        }

        if !selectedPrinter.isEmpty, printers.contains(selectedPrinter) {
            return
        }

        if let savedPrinter = UserDefaults.standard.string(forKey: lastPrinterKey),
           printers.contains(savedPrinter) {
            selectedPrinter = savedPrinter
            return
        }

        if let zebraPrinter = printers.first(where: Self.matchesZebra) {
            selectedPrinter = zebraPrinter
            persistPrinter(zebraPrinter)
            return
        }

        selectedPrinter = ""
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

    func pauseSelectedPrinter() {
        guard !selectedPrinter.isEmpty else { return }

        if CUPSPrinterService.pausePrinterQueue(selectedPrinter) {
            statusMessage = "Printer queue paused."
            refreshRequirements()
        } else {
            errorMessage = "Could not pause \"\(selectedPrinter)\"."
            showErrorAlert = true
        }
    }

    func cancelSelectedPrinterJobs() {
        guard !selectedPrinter.isEmpty else { return }

        if CUPSPrinterService.cancelAllJobs(on: selectedPrinter) {
            statusMessage = "Queued jobs cancelled."
            refreshRequirements()
        } else {
            errorMessage = "Could not cancel jobs on \"\(selectedPrinter)\"."
            showErrorAlert = true
        }
    }

    func clampPrintRange() {
        guard labelsToPrintCount > 0 else {
            printRangeFrom = 1
            printRangeTo = 1
            return
        }
        printRangeFrom = min(max(printRangeFrom, 1), labelsToPrintCount)
        printRangeTo = min(max(printRangeTo, 1), labelsToPrintCount)
        if printRangeFrom > printRangeTo {
            swap(&printRangeFrom, &printRangeTo)
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

    func persistResolution() {
        UserDefaults.standard.set(selectedResolutionId, forKey: resolutionKey)
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

    func schedulePreviewLabelRefresh() {
        previewLabelTask?.cancel()
        // One Labelary call per label jump — debounce typing in the number field.
        previewLabelTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await loadPreview()
        }
    }

    func stepPreviewLabel(by delta: Int) {
        guard labelsToPrintCount > 0 else { return }
        previewLabelNumber = min(max(previewLabelNumber + delta, 1), labelsToPrintCount)
        schedulePreviewLabelRefresh()
    }

    func clampPreviewLabelNumber() {
        guard labelsToPrintCount > 0 else {
            previewLabelNumber = 1
            return
        }
        previewLabelNumber = min(max(previewLabelNumber, 1), labelsToPrintCount)
    }

    private func preparedZPL(from zpl: String) -> String {
        return ZPLModifier.applyHorizontalOffset(
            to: zpl,
            offsetMM: horizontalOffsetMM,
            dpmm: resolvedDpmm
        )
    }

    func loadPrinters() {
        refreshRequirements()
    }

    /// Accurate ZPL dot dimensions (^PW × ^LL) for the selected label at the resolved density.
    /// Dots are computed from dpmm directly — the printer images at mm × dpmm, not nominal dpi.
    private var labelDotsSummary: String {
        let size = selectedLabelSize
        let widthDots = Int((size.widthInches * 25.4 * Double(resolvedDpmm)).rounded())
        let heightDots = Int((size.heightInches * 25.4 * Double(resolvedDpmm)).rounded())
        return "\(widthDots) × \(heightDots) dots"
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
        previewLabelNumber = 1
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
        labelsToPrintCount = ZPLParser.printableLabelCount(from: preparedZPL(from: zpl))
        clampPrintRange()
        clampPreviewLabelNumber()
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
              let zpl = Self.decodeZPL(data) else {
            return nil
        }
        return zpl
    }

    /// ZPL is usually ASCII but legacy exports are often Latin-1 (CP1252-ish), not UTF-8.
    /// Try UTF-8 first, then fall back to Latin-1, which decodes any byte sequence — so a
    /// non-UTF-8 file renders instead of failing silently.
    private static func decodeZPL(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
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

        previewGeneration += 1
        let generation = previewGeneration

        isLoadingPreview = true
        previewError = ""
        previewLimitMessage = ""
        // Only the latest preview request clears the spinner, so an out-of-order older
        // request can't hide it while a newer one is still rendering.
        defer { if generation == previewGeneration { isLoadingPreview = false } }

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

        guard let zpl = Self.decodeZPL(zplData) else {
            previewImages = []
            previewError = "The ZPL file could not be read as text."
            labelsToPrintCount = 0
            return
        }

        let adjustedZPL = preparedZPL(from: zpl)
        labelsToPrintCount = ZPLParser.printableLabelCount(from: adjustedZPL)
        clampPrintRange()
        clampPreviewLabelNumber()

        do {
            let dpmm = resolvedDpmm
            let labelSize = selectedLabelSize.sizeInches
            previewLabelSizeInches = labelSize
            let image = try await ZPLPreviewService.renderExpandedLabel(
                atOneBasedIndex: previewLabelNumber,
                zpl: adjustedZPL,
                dpmm: dpmm,
                labelSizeInches: labelSize
            )
            // A newer request started while this one was on the network — drop this result.
            guard generation == previewGeneration else { return }
            previewImages = [image]

            if labelsToPrintCount > 1 {
                previewLimitMessage = "One Labelary request per preview (rate limit)."
            } else {
                previewLimitMessage = "This is the only label in the file."
            }

            let dpi = ZebraPrintResolutionOption.nominalDpi(forDpmm: dpmm)
            previewLabelInfo = "\(selectedLabelSize.name) · \(dpi) dpi · \(dpmm) dpmm · \(labelDotsSummary)"
            if horizontalOffsetMM != 0 {
                previewLabelInfo += String(format: " · offset %+.1f mm", horizontalOffsetMM)
            }
        } catch {
            guard generation == previewGeneration else { return }
            previewImages = []
            previewLabelInfo = ""
            previewLimitMessage = ""
            previewError = error.localizedDescription
        }
    }

    func printFile() async {
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

        let printer = selectedPrinter
        guard !printer.isEmpty else {
            errorMessage = "Select a printer first."
            showErrorAlert = true
            return
        }

        // Read and prepare on the main actor (fast, in-memory), then hand the finished bytes to a
        // detached task — only the lpr subprocess (up to 30 s) runs off the main thread, so the UI
        // stays responsive while printing.
        guard let adjustedData = preparePrintData(from: fileURL, printer: printer) else {
            return
        }

        isPrinting = true
        statusMessage = "Sending to printer…"
        defer { isPrinting = false }

        persistPrinter(printer)

        let result = await Task.detached(priority: .userInitiated) {
            CUPSPrinterService.printRaw(zplData: adjustedData, to: printer)
        }.value

        switch result {
        case .success(let submission):
            refreshRequirements()
            switch submission {
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

    /// Reads the file, applies the offset, and resolves the selected labels into print-ready bytes.
    /// Returns nil after surfacing an error alert when anything is unreadable or empty.
    private func preparePrintData(from fileURL: URL, printer: String) -> Data? {
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
            return nil
        }

        guard !zplData.isEmpty else {
            errorMessage = "The selected file is empty."
            statusMessage = ""
            showErrorAlert = true
            return nil
        }

        guard let zpl = Self.decodeZPL(zplData) else {
            errorMessage = "The ZPL file could not be read as text."
            statusMessage = ""
            showErrorAlert = true
            return nil
        }

        let adjustedZPL = preparedZPL(from: zpl)

        let indices: [Int]
        switch resolvedPrintIndices() {
        case .success(let selected):
            indices = selected
        case .failure(let error):
            errorMessage = error.localizedDescription
            statusMessage = ""
            showErrorAlert = true
            return nil
        }

        let printZPL = ZPLParser.buildPrintZPL(from: adjustedZPL, oneBasedIndices: indices)
        guard !printZPL.isEmpty else {
            errorMessage = "No label data matched your selection."
            statusMessage = ""
            showErrorAlert = true
            return nil
        }

        lastPrintedLabelCount = indices.count
        return Data(printZPL.utf8)
    }
}

enum LabelSelectionError: LocalizedError, Equatable {
    case empty
    case invalidRange
    case invalidPages(String)
    case labelOutOfBounds(Int, Int)
    case noLabels

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter label numbers."
        case .invalidRange:
            return "Enter a valid from/to range."
        case .invalidPages(let detail):
            return detail
        case .labelOutOfBounds(let label, let max):
            return "Label \(label) exceeds total (\(max))."
        case .noLabels:
            return "No labels selected."
        }
    }
}

enum LabelSelectionParser {
    static func resolvedIndices(
        scope: PrintLabelScope,
        labelsToPrintCount: Int,
        printRangeFrom: Int,
        printRangeTo: Int,
        printPagesText: String
    ) -> Result<[Int], LabelSelectionError> {
        guard labelsToPrintCount > 0 else { return .failure(.noLabels) }

        switch scope {
        case .all:
            return .success(Array(1...labelsToPrintCount))

        case .range:
            let from = min(printRangeFrom, printRangeTo)
            let to = max(printRangeFrom, printRangeTo)
            guard from >= 1, to <= labelsToPrintCount, from <= to else {
                return .failure(.invalidRange)
            }
            return .success(Array(from...to))

        case .pages:
            return parseLabelPages(printPagesText, maxLabel: labelsToPrintCount)
        }
    }

    /// Parses macOS-style lists: `1`, `10`, `1, 5, 10-20`.
    static func parseLabelPages(_ text: String, maxLabel: Int) -> Result<[Int], LabelSelectionError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        var indices = Set<Int>()

        for part in trimmed.split(separator: ",") {
            let segment = part.trimmingCharacters(in: .whitespaces)
            if segment.isEmpty { continue }

            if segment.contains("-") {
                let bounds = segment.split(separator: "-", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard bounds.count == 2,
                      let low = Int(bounds[0]),
                      let high = Int(bounds[1]),
                      low >= 1,
                      high >= low else {
                    return .failure(.invalidPages("Invalid range: \(segment)"))
                }
                for number in low...high {
                    guard number <= maxLabel else {
                        return .failure(.labelOutOfBounds(number, maxLabel))
                    }
                    indices.insert(number)
                }
            } else {
                guard let number = Int(segment), number >= 1 else {
                    return .failure(.invalidPages("Invalid label: \(segment)"))
                }
                guard number <= maxLabel else {
                    return .failure(.labelOutOfBounds(number, maxLabel))
                }
                indices.insert(number)
            }
        }

        guard !indices.isEmpty else { return .failure(.noLabels) }
        return .success(indices.sorted())
    }
}

private extension UTType {
    static let zpl = UTType(filenameExtension: "zpl") ?? .plainText
}
