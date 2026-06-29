import Foundation

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
