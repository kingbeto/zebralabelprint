import XCTest
@testable import ZebraLabelPrint

final class ZPLParserTests: XCTestCase {
    func testSplitLabelsTwoBlocks() {
        let zpl = "^XA^FO10,10^FDHi^FS^XZ\n^XA^FO10,10^FDBye^FS^XZ"
        let labels = ZPLParser.splitLabels(from: zpl)
        XCTAssertEqual(labels.count, 2)
    }

    func testExpandedLabelZPLBlocksExpandsPQ() {
        let zpl = "^XA^FO10,10^FDTest^FS^PQ3^XZ"
        let blocks = ZPLParser.expandedLabelZPLBlocks(from: zpl)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertTrue(blocks.allSatisfy { $0.contains("^PQ1") })
    }

    func testBuildPrintZPLSelectsSecondLabel() {
        let zpl = "^XA^FO10,10^FDA^FS^XZ^XA^FO10,10^FDB^FS^XZ"
        let result = ZPLParser.buildPrintZPL(from: zpl, oneBasedIndices: [2])
        XCTAssertTrue(result.contains("FDB"))
        XCTAssertFalse(result.contains("FDA"))
    }

    func testPrintableLabelCountWithPQ() {
        let zpl = "^XA^FO10,10^FDTest^FS^PQ3^XZ"
        XCTAssertEqual(ZPLParser.printableLabelCount(from: zpl), 3)
    }

    func testPrintableLabelCountZeroWithoutFormatStart() {
        let zpl = "not zpl at all"
        XCTAssertEqual(ZPLParser.printableLabelCount(from: zpl), 0)
    }

    func testPrintableLabelCountZeroWhenEmpty() {
        XCTAssertEqual(ZPLParser.printableLabelCount(from: ""), 0)
        XCTAssertEqual(ZPLParser.printableLabelCount(from: "   "), 0)
    }

    func testSplitLabelsWithoutClosingTagReturnsWhole() {
        // No complete ^XA…^XZ pair — splitLabels returns the input as a single block.
        let zpl = "^XA^FO10,10^FDOrphan^FS"
        XCTAssertEqual(ZPLParser.splitLabels(from: zpl), [zpl])
    }
}

final class PrinterResolutionTests: XCTestCase {
    func testNominalDpiMatchesZebraNaming() {
        XCTAssertEqual(ZebraPrintResolutionOption.nominalDpi(forDpmm: 8), 203)
        XCTAssertEqual(ZebraPrintResolutionOption.nominalDpi(forDpmm: 12), 300)
        XCTAssertEqual(ZebraPrintResolutionOption.nominalDpi(forDpmm: 24), 600)
        XCTAssertEqual(ZebraPrintResolutionOption.nominalDpi(forDpmm: 6), 152)
    }

    func testNominalDpiFallsBackToExactConversion() {
        // 16 dpmm has no marketing name — fall back to the exact 16 × 25.4 ≈ 406 conversion.
        XCTAssertEqual(ZebraPrintResolutionOption.nominalDpi(forDpmm: 16), 406)
    }

    func testFromPrinterNameInfersDpmm() {
        XCTAssertEqual(PrinterDpmm.fromPrinterName("Zebra_ZD410-203dpi_ZPL"), 8)
        XCTAssertEqual(PrinterDpmm.fromPrinterName("Zebra_ZD420-300dpi"), 12)
        XCTAssertEqual(PrinterDpmm.fromPrinterName("Zebra_ZT610-600dpi"), 24)
        XCTAssertEqual(PrinterDpmm.fromPrinterName("Generic_Label_Printer"), 8)
    }
}
