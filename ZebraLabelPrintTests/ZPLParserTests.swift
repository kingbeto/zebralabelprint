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
}
