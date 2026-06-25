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
    @Published var previewLabelIndex = 0
    @Published var previewLabelCount = 0
    @Published var horizontalOffsetMM: Double = 0
    @Published var printDefinitionInfo = ""
    @Published var selectedLabelSizeId: String = ZebraLabelSizeOption.defaultSize.id

    private var previewLabels: [String] = []
    private var offsetPreviewTask: Task<Void, Never>?

    private let lastPrinterKey = "lastSelectedPrinter"
    private let horizontalOffsetKey = "horizontalOffsetMM"
    private let labelSizeKey = "selectedLabelSizeId"
    // case-insensitive match — queue names are all over the place
    private static let zebraPrinterPattern = try? NSRegularExpression(pattern: "(?i)zebra")

    var selectedLabelSize: ZebraLabelSizeOption {
        ZebraLabelSizeOption.option(id: selectedLabelSizeId)
    }

    init() {
        horizontalOffsetMM = UserDefaults.standard.double(forKey: horizontalOffsetKey)
        if let savedSizeId = UserDefaults.standard.string(forKey: labelSizeKey),
           ZebraLabelSizeOption.standardSizes.contains(where: { $0.id == savedSizeId }) {
            selectedLabelSizeId = savedSizeId
        }
    }

    func onAppear() {
        loadPrinters()
        // open file picker straight away, thats the whole point of the app
        if selectedFileURL == nil {
            selectFile()
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
        // small debounce — slider onChange fires like crazy
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
            statusMessage = "No printers found. Add a printer in System Settings."
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
            return
        }

        selectedFileURL = url
        statusMessage = ""
        previewLabelIndex = 0
        previewLabels = []
        Task { await loadPreview() }
    }

    func showPreviousPreviewLabel() {
        guard previewLabelIndex > 0 else { return }
        previewLabelIndex -= 1
        Task { await loadPreview() }
    }

    func showNextPreviewLabel() {
        guard previewLabelIndex < previewLabelCount - 1 else { return }
        previewLabelIndex += 1
        Task { await loadPreview() }
    }

    func loadPreview() async {
        guard let fileURL = selectedFileURL else {
            previewImages = []
            previewError = ""
            previewLabelInfo = ""
            return
        }

        isLoadingPreview = true
        previewError = ""
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
            previewLabelCount = 0
            return
        }

        guard let zpl = String(data: zplData, encoding: .utf8) else {
            previewImages = []
            previewError = "The ZPL file could not be read as text."
            previewLabelCount = 0
            return
        }

        let adjustedZPL = preparedZPL(from: zpl)
        previewLabels = ZPLParser.splitLabels(from: adjustedZPL)
        previewLabelCount = previewLabels.count
        previewLabelIndex = min(previewLabelIndex, max(previewLabelCount - 1, 0))

        do {
            let dpmm = ZPLLabelSize.dpmm(forPrinter: selectedPrinter)
            let labelSize = selectedLabelSize.sizeInches
            previewLabelSizeInches = labelSize
            updatePrintDefinition(for: previewLabels[previewLabelIndex])
            // cap at 5 labels — labelary gets unhappy with huge batches
            previewImages = try await ZPLPreviewService.renderLabels(
                zpl: adjustedZPL,
                printerName: selectedPrinter,
                labelSizeInches: labelSize,
                startIndex: previewLabelIndex,
                count: ZPLPreviewService.previewStripCount
            )

            let stripEnd = previewLabelIndex + previewImages.count
            let dimensions = String(
                format: "%@ @ %d dpmm",
                selectedLabelSize.name,
                dpmm
            )
            if previewLabelCount > 1 {
                previewLabelInfo = "Labels \(previewLabelIndex + 1)–\(stripEnd) of \(previewLabelCount) · \(dimensions)"
            } else {
                previewLabelInfo = "\(dimensions)"
            }
            if horizontalOffsetMM != 0 {
                previewLabelInfo += String(format: " · offset %+.1f mm", horizontalOffsetMM)
            }
        } catch {
            previewImages = []
            previewLabelInfo = ""
            previewError = error.localizedDescription
        }
    }

    func printFile() {
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
        case .success:
            statusMessage = "Print job sent successfully."
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
