import Foundation

enum PrinterDpmm {
    /// Infers dots-per-millimeter from a CUPS queue name (e.g. `ZD410-203dpi` → 8).
    static func fromPrinterName(_ printerName: String) -> Int {
        let name = printerName.lowercased()
        if name.contains("600") { return 24 }
        if name.contains("300") { return 12 }
        return 8
    }
}
