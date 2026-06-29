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
        return PrinterDpmm.fromPrinterName(printerName)
    }
}

enum ZPLParser {
    private static let splitLabelsRegex = try! NSRegularExpression(pattern: "(?is)\\^XA.*?\\^XZ")
    private static let printQuantityRegex = try! NSRegularExpression(pattern: "(?i)\\^PQ(\\d+)")
    private static let normalizePQRegex = try! NSRegularExpression(pattern: "(?i)\\^PQ\\d+")
    private static let hasFormatStartRegex = try! NSRegularExpression(pattern: "(?i)\\^XA")

    /// Splits a ZPL file into individual label definitions (`^XA` … `^XZ`).
    static func splitLabels(from zpl: String) -> [String] {
        let matches = splitLabelsRegex.matches(in: zpl, range: NSRange(zpl.startIndex..., in: zpl))
        if matches.isEmpty {
            return [zpl]
        }

        return matches.compactMap { match in
            guard let range = Range(match.range, in: zpl) else { return nil }
            return String(zpl[range])
        }
    }

    private static func printQuantity(in zpl: String) -> Int {
        guard let match = printQuantityRegex.firstMatch(in: zpl, range: NSRange(zpl.startIndex..., in: zpl)),
              let valueRange = Range(match.range(at: 1), in: zpl),
              let quantity = Int(zpl[valueRange]),
              quantity > 0 else {
            return 1
        }
        return quantity
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

        return expanded
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
        let trimmed = zpl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        guard hasFormatStartRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil else {
            return 0
        }
        return expandedLabelZPLBlocks(from: trimmed).count
    }

    private static func normalizeToSingleCopy(_ block: String) -> String {
        let range = NSRange(block.startIndex..., in: block)
        return normalizePQRegex.stringByReplacingMatches(in: block, range: range, withTemplate: "^PQ1")
    }
}

enum ZPLModifier {
    private static let foRegex = try! NSRegularExpression(pattern: #"(?i)(\^FO)(\d+),(\d+)"#)
    private static let ftRegex = try! NSRegularExpression(pattern: #"(?i)(\^FT)(\d+),(\d+)"#)
    private static let gbRegex = try! NSRegularExpression(pattern: #"(?i)(\^GB)(\d+),(\d+),(\d+),(\d+)"#)
    private static let gcRegex = try! NSRegularExpression(pattern: #"(?i)(\^GC)(\d+),(\d+),(\d+)"#)

    /// Shifts label content horizontally by adjusting field coordinates.
    /// Positive `offsetMM` moves content to the right; negative moves left.
    static func applyHorizontalOffset(to zpl: String, offsetMM: Double, dpmm: Int) -> String {
        guard offsetMM != 0 else { return zpl }

        let offsetDots = Int((offsetMM * Double(dpmm)).rounded())
        guard offsetDots != 0 else { return zpl }

        var result = zpl
        result = shiftCommandCoordinates(in: result, regex: foRegex, offsetDots: offsetDots)
        result = shiftCommandCoordinates(in: result, regex: ftRegex, offsetDots: offsetDots)
        result = shiftCommandCoordinates(in: result, regex: gbRegex, offsetDots: offsetDots, xGroup: 2)
        result = shiftCommandCoordinates(in: result, regex: gcRegex, offsetDots: offsetDots, xGroup: 2)
        return result
    }

    private static func shiftCommandCoordinates(
        in zpl: String,
        regex: NSRegularExpression,
        offsetDots: Int,
        xGroup: Int = 2
    ) -> String {
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
