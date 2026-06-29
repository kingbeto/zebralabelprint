import AppKit
import Foundation

struct ZebraLabelSizeOption: Identifiable, Hashable {
    let id: String
    let name: String
    let widthInches: Double
    let heightInches: Double

    var sizeInches: CGSize {
        CGSize(width: widthInches, height: heightInches)
    }

    static let defaultSize = standardSizes[0]

    static func option(id: String) -> ZebraLabelSizeOption {
        standardSizes.first { $0.id == id } ?? defaultSize
    }

    static let standardSizes: [ZebraLabelSizeOption] = [
        ZebraLabelSizeOption(id: "2x1", name: "2\" × 1\" (51 × 25 mm)", widthInches: 2.0, heightInches: 1.0),
        ZebraLabelSizeOption(id: "2x0.75", name: "2\" × 0.75\" (51 × 19 mm)", widthInches: 2.0, heightInches: 0.75),
        ZebraLabelSizeOption(id: "2.25x1.25", name: "2.25\" × 1.25\" (57 × 32 mm)", widthInches: 2.25, heightInches: 1.25),
        ZebraLabelSizeOption(id: "2x2", name: "2\" × 2\" (51 × 51 mm)", widthInches: 2.0, heightInches: 2.0),
        ZebraLabelSizeOption(id: "3x1", name: "3\" × 1\" (76 × 25 mm)", widthInches: 3.0, heightInches: 1.0),
        ZebraLabelSizeOption(id: "3x2", name: "3\" × 2\" (76 × 51 mm)", widthInches: 3.0, heightInches: 2.0),
        ZebraLabelSizeOption(id: "4x1", name: "4\" × 1\" (102 × 25 mm)", widthInches: 4.0, heightInches: 1.0),
        ZebraLabelSizeOption(id: "4x2", name: "4\" × 2\" (102 × 51 mm)", widthInches: 4.0, heightInches: 2.0),
        ZebraLabelSizeOption(id: "4x3", name: "4\" × 3\" (102 × 76 mm)", widthInches: 4.0, heightInches: 3.0),
        ZebraLabelSizeOption(id: "4x4", name: "4\" × 4\" (102 × 102 mm)", widthInches: 4.0, heightInches: 4.0),
        ZebraLabelSizeOption(id: "4x6", name: "4\" × 6\" (102 × 152 mm)", widthInches: 4.0, heightInches: 6.0),
        ZebraLabelSizeOption(id: "4x8", name: "4\" × 8\" (102 × 203 mm)", widthInches: 4.0, heightInches: 8.0),
        ZebraLabelSizeOption(id: "6x4", name: "6\" × 4\" (152 × 102 mm)", widthInches: 6.0, heightInches: 4.0),
    ]
}

struct ZebraPrintResolutionOption: Identifiable, Hashable {
    let id: String
    let dpmm: Int?
    let name: String

    static let defaultOption = allOptions[0]

    static func option(id: String) -> ZebraPrintResolutionOption {
        allOptions.first { $0.id == id } ?? defaultOption
    }

    /// `dpmm` is nil for Auto — resolved from the printer queue name.
    static let allOptions: [ZebraPrintResolutionOption] = [
        ZebraPrintResolutionOption(id: "auto", dpmm: nil, name: "Auto (from printer name)"),
        ZebraPrintResolutionOption(id: "8", dpmm: 8, name: "203 dpi · 8 dpmm"),
        ZebraPrintResolutionOption(id: "12", dpmm: 12, name: "300 dpi · 12 dpmm"),
        ZebraPrintResolutionOption(id: "24", dpmm: 24, name: "600 dpi · 24 dpmm"),
    ]

    static func resolvedDpmm(optionId: String, printerName: String) -> Int {
        let option = option(id: optionId)
        if let dpmm = option.dpmm {
            return dpmm
        }
        return ZPLLabelSize.dpmm(forPrinter: printerName)
    }
}

struct ZPLLabelSize {
    let dpmm: Int
    let widthInches: Double
    let heightInches: Double

    var sizeInches: CGSize {
        CGSize(width: widthInches, height: heightInches)
    }

    static func from(zpl: String, dpmm: Int = 8) -> ZPLLabelSize {
        let dotsPerInch = Double(dpmm) * 25.4
        let pw = extractInt(from: zpl, command: "PW")
        let ll = extractInt(from: zpl, command: "LL")

        if let pw, let ll, pw > 0, ll > 0 {
            return ZPLLabelSize(
                dpmm: dpmm,
                widthInches: Double(pw) / dotsPerInch,
                heightInches: Double(ll) / dotsPerInch
            )
        }

        let inferred = inferSizeDots(from: zpl)
        let widthDots = pw ?? inferred.width
        let heightDots = ll ?? inferred.height

        return ZPLLabelSize(
            dpmm: dpmm,
            widthInches: max(0.25, Double(widthDots) / dotsPerInch),
            heightInches: max(0.25, Double(heightDots) / dotsPerInch)
        )
    }

    static func dpmm(forPrinter printerName: String) -> Int {
        // parsed from queue name — bit hacky but it works for ZD series
        let name = printerName.lowercased()
        if name.contains("600") { return 24 }
        if name.contains("300") { return 12 }
        return 8
    }

    private static func inferSizeDots(from zpl: String) -> (width: Int, height: Int) {
        var maxX = 0
        var maxY = 0
        var fbWidth = 0
        var fbLines = 2
        var fontHeight = 28
        var barcodeHeight = 50

        if let foRegex = try? NSRegularExpression(pattern: "(?i)\\^FO(\\d+),(\\d+)") {
            for match in foRegex.matches(in: zpl, range: NSRange(zpl.startIndex..., in: zpl)) {
                guard let xRange = Range(match.range(at: 1), in: zpl),
                      let yRange = Range(match.range(at: 2), in: zpl),
                      let x = Int(zpl[xRange]),
                      let y = Int(zpl[yRange]) else { continue }
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        if let fbRegex = try? NSRegularExpression(pattern: "(?i)\\^FB(\\d+),(\\d+)") {
            if let match = fbRegex.firstMatch(in: zpl, range: NSRange(zpl.startIndex..., in: zpl)),
               let widthRange = Range(match.range(at: 1), in: zpl),
               let linesRange = Range(match.range(at: 2), in: zpl),
               let width = Int(zpl[widthRange]),
               let lines = Int(zpl[linesRange]) {
                fbWidth = width
                fbLines = max(lines, 1)
            }
        }

        if let fontRegex = try? NSRegularExpression(pattern: "(?i)\\^A0N,(\\d+)") {
            if let match = fontRegex.firstMatch(in: zpl, range: NSRange(zpl.startIndex..., in: zpl)),
               let heightRange = Range(match.range(at: 1), in: zpl),
               let height = Int(zpl[heightRange]) {
                fontHeight = height
            }
        }

        if let bcRegex = try? NSRegularExpression(pattern: "(?i)\\^BCN,(\\d+)") {
            if let match = bcRegex.firstMatch(in: zpl, range: NSRange(zpl.startIndex..., in: zpl)),
               let heightRange = Range(match.range(at: 1), in: zpl),
               let height = Int(zpl[heightRange]) {
                barcodeHeight = height
            }
        }

        if let gbRegex = try? NSRegularExpression(pattern: "(?i)\\^GB(\\d+),(\\d+)") {
            if let match = gbRegex.firstMatch(in: zpl, range: NSRange(zpl.startIndex..., in: zpl)),
               let widthRange = Range(match.range(at: 1), in: zpl),
               let heightRange = Range(match.range(at: 2), in: zpl),
               let width = Int(zpl[widthRange]),
               let height = Int(zpl[heightRange]) {
                maxX = max(maxX, width)
                maxY = max(maxY, height)
            }
        }

        let contentWidth = max(maxX + max(fbWidth, 80), 160)
        let contentHeight = max(
            maxY + barcodeHeight + fbLines * fontHeight + 24,
            maxY + 80
        )

        // Typical small label fallback when content is compact.
        // 406x203 = 2x1 @ 203dpi, wich is what most of our rolls are
        if contentWidth <= 500, contentHeight <= 300 {
            return (width: max(contentWidth, 406), height: max(contentHeight, 203))
        }

        return (width: contentWidth, height: contentHeight)
    }

    private static func extractInt(from zpl: String, command: String) -> Int? {
        let pattern = "\\^\(command)(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: zpl, range: NSRange(zpl.startIndex..., in: zpl)),
              let valueRange = Range(match.range(at: 1), in: zpl) else {
            return nil
        }
        return Int(zpl[valueRange])
    }
}

enum ZPLParser {
    /// Splits a ZPL file into individual label definitions (`^XA` … `^XZ`).
    static func splitLabels(from zpl: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?is)\\^XA.*?\\^XZ") else {
            return [zpl]
        }

        let matches = regex.matches(in: zpl, range: NSRange(zpl.startIndex..., in: zpl))
        if matches.isEmpty {
            return [zpl]
        }

        return matches.compactMap { match in
            guard let range = Range(match.range, in: zpl) else { return nil }
            return String(zpl[range])
        }
    }

    /// Labels that will actually print: honors `^PQ` copies and `^XA` starts beyond `^XA…^XZ` pairs.
    static func labelCount(from zpl: String) -> Int {
        let blocks = splitLabels(from: zpl)
        let sections = blocks.isEmpty ? [zpl] : blocks
        let blockCount = max(sections.count, 1)

        let pqSum = sections.reduce(0) { $0 + printQuantity(in: $1) }
        if pqSum > blockCount {
            return pqSum
        }

        let formatStarts = countFormatStarts(in: zpl)
        if formatStarts > blockCount {
            return formatStarts
        }

        return blockCount
    }

    private static func printQuantity(in zpl: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\^PQ(\\d+)"),
              let match = regex.firstMatch(in: zpl, range: NSRange(zpl.startIndex..., in: zpl)),
              let valueRange = Range(match.range(at: 1), in: zpl),
              let quantity = Int(zpl[valueRange]),
              quantity > 0 else {
            return 1
        }
        return quantity
    }

    private static func countFormatStarts(in zpl: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\^XA") else { return 0 }
        return regex.numberOfMatches(in: zpl, range: NSRange(zpl.startIndex..., in: zpl))
    }

    /// One ZPL block per printed label, expanding `^PQ` copies.
    static func expandedLabelZPLBlocks(from zpl: String) -> [String] {
        let blocks = splitLabels(from: zpl)
        let sections = blocks.isEmpty ? [zpl] : blocks
        var expanded: [String] = []

        for block in sections {
            let quantity = printQuantity(in: block)
            let singleCopy = normalizeToSingleCopy(block)
            for _ in 0..<quantity {
                expanded.append(singleCopy)
            }
        }

        if !expanded.isEmpty {
            return expanded
        }
        return [zpl]
    }

    static func buildPrintZPL(from zpl: String, oneBasedIndices: [Int]) -> String {
        let expanded = expandedLabelZPLBlocks(from: zpl)
        let parts = oneBasedIndices.compactMap { index -> String? in
            guard index >= 1, index <= expanded.count else { return nil }
            return expanded[index - 1]
        }
        return parts.joined(separator: "\n")
    }

    /// Labels you can target when printing (one entry per physical output).
    static func printableLabelCount(from zpl: String) -> Int {
        max(expandedLabelZPLBlocks(from: zpl).count, 1)
    }

    private static func normalizeToSingleCopy(_ block: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\^PQ\\d+") else {
            return block
        }
        let range = NSRange(block.startIndex..., in: block)
        return regex.stringByReplacingMatches(in: block, range: range, withTemplate: "^PQ1")
    }
}

enum ZPLModifier {
    /// Shifts label content horizontally by adjusting field coordinates.
    /// Positive `offsetMM` moves content to the right; negative moves left.
    static func applyHorizontalOffset(to zpl: String, offsetMM: Double, dpmm: Int) -> String {
        guard offsetMM != 0 else { return zpl }

        let offsetDots = Int((offsetMM * Double(dpmm)).rounded())
        guard offsetDots != 0 else { return zpl }

        var result = zpl
        result = shiftCommandCoordinates(in: result, pattern: #"(?i)(\^FO)(\d+),(\d+)"#, offsetDots: offsetDots)
        result = shiftCommandCoordinates(in: result, pattern: #"(?i)(\^FT)(\d+),(\d+)"#, offsetDots: offsetDots)
        result = shiftCommandCoordinates(in: result, pattern: #"(?i)(\^GB)(\d+),(\d+),(\d+),(\d+)"#, offsetDots: offsetDots, xGroup: 2)
        result = shiftCommandCoordinates(in: result, pattern: #"(?i)(\^GC)(\d+),(\d+),(\d+)"#, offsetDots: offsetDots, xGroup: 2)
        return result
    }

    private static func shiftCommandCoordinates(
        in zpl: String,
        pattern: String,
        offsetDots: Int,
        xGroup: Int = 2
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return zpl }

        let nsRange = NSRange(zpl.startIndex..., in: zpl)
        let matches = regex.matches(in: zpl, range: nsRange)
        guard !matches.isEmpty else { return zpl }

        var result = zpl
        for match in matches.reversed() {
            guard let xValueRange = Range(match.range(at: xGroup), in: result),
                  let x = Int(result[xValueRange]) else {
                continue
            }

            let shiftedX = max(0, x + offsetDots)
            result.replaceSubrange(xValueRange, with: String(shiftedX))
        }

        return result
    }
}

enum ZPLPreviewService {
    /// Labelary’s free API throttles rapid requests (HTTP 429). We only preview one
    /// label per refresh and pause before each HTTP call so slider tweaks don’t trip the limit.
    static let previewStripCount = 1

    /// 200 ms between Labelary calls — space out requests when the user moves offset/size sliders.
    private static let labelaryRequestDelayNanoseconds: UInt64 = 200_000_000

    // hits labelary over http — needs ATS exception in Info.plist
    static func renderLabels(
        zpl: String,
        printerName: String = "",
        labelSizeInches: CGSize,
        startIndex: Int = 0,
        count: Int = previewStripCount
    ) async throws -> [NSImage] {
        let labels = ZPLParser.splitLabels(from: zpl)
        guard !labels.isEmpty else {
            throw PreviewError.invalidZPL
        }

        let safeStart = min(max(startIndex, 0), labels.count - 1)
        let end = min(safeStart + count, labels.count)
        var images: [NSImage] = []

        for index in safeStart..<end {
            images.append(
                try await renderLabel(
                    labels[index],
                    dpmm: ZPLLabelSize.dpmm(forPrinter: printerName),
                    labelSizeInches: labelSizeInches
                )
            )
        }

        return images
    }

    static func render(
        zpl: String,
        printerName: String = "",
        labelIndex: Int = 0,
        labelSizeInches: CGSize
    ) async throws -> NSImage {
        let labels = ZPLParser.splitLabels(from: zpl)
        guard !labels.isEmpty else {
            throw PreviewError.invalidZPL
        }

        let safeIndex = min(max(labelIndex, 0), labels.count - 1)
        return try await renderLabel(
            labels[safeIndex],
            dpmm: ZPLLabelSize.dpmm(forPrinter: printerName),
            labelSizeInches: labelSizeInches
        )
    }

    /// Renders one printable label by number (1-based), using the same expansion as print.
    static func renderExpandedLabel(
        atOneBasedIndex index: Int,
        zpl: String,
        dpmm: Int,
        labelSizeInches: CGSize
    ) async throws -> NSImage {
        let blocks = ZPLParser.expandedLabelZPLBlocks(from: zpl)
        guard index >= 1, index <= blocks.count else {
            throw PreviewError.invalidZPL
        }
        return try await renderLabel(
            blocks[index - 1],
            dpmm: dpmm,
            labelSizeInches: labelSizeInches
        )
    }

    private static func renderLabel(
        _ labelZPL: String,
        dpmm: Int,
        labelSizeInches: CGSize
    ) async throws -> NSImage {
        // Pace every Labelary POST — renderLabel is the single entry point for HTTP previews.
        try await Task.sleep(nanoseconds: labelaryRequestDelayNanoseconds)

        guard let zplData = labelZPL.data(using: .utf8) else {
            throw PreviewError.invalidZPL
        }

        let urlString = String(
            format: "http://api.labelary.com/v1/printers/%ddpmm/labels/%.3fx%.3f/0/",
            dpmm,
            labelSizeInches.width,
            labelSizeInches.height
        )

        guard let url = URL(string: urlString) else {
            throw PreviewError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = zplData
        request.setValue("image/png", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PreviewError.unexpectedResponse
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PreviewError.apiError(httpResponse.statusCode, message)
        }

        guard let image = NSImage(data: data) else {
            throw PreviewError.invalidImage
        }

        return image
    }

    enum PreviewError: LocalizedError {
        case invalidZPL
        case invalidURL
        case unexpectedResponse
        case invalidImage
        case apiError(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidZPL:
                return "The ZPL file could not be read as text."
            case .invalidURL:
                return "Could not build the preview request."
            case .unexpectedResponse:
                return "The preview service returned an unexpected response."
            case .invalidImage:
                return "The preview image could not be decoded."
            case .apiError(let code, let message):
                if let message, !message.isEmpty {
                    return "Preview failed (\(code)): \(message)"
                }
                return "Preview failed with status \(code)."
            }
        }
    }
}
