import XCTest
@testable import ZebraLabelPrint

final class ZPLModifierTests: XCTestCase {
    func testApplyHorizontalOffsetShiftsFO() {
        let zpl = "^XA^FO100,50^FDTest^FS^XZ"
        let shifted = ZPLModifier.applyHorizontalOffset(to: zpl, offsetMM: 1, dpmm: 8)
        XCTAssertTrue(shifted.contains("^FO108,50"))
    }

    func testApplyHorizontalOffsetZeroIsNoOp() {
        let zpl = "^XA^FO100,50^FDTest^FS^XZ"
        XCTAssertEqual(
            ZPLModifier.applyHorizontalOffset(to: zpl, offsetMM: 0, dpmm: 8),
            zpl
        )
    }

    func testApplyHorizontalOffsetClampsNegativeAtZero() {
        // -5 mm × 8 dpmm = -40 dots; x=10 would go negative, so it clamps to 0 (never off-label).
        let zpl = "^XA^FO10,50^FDTest^FS^XZ"
        let shifted = ZPLModifier.applyHorizontalOffset(to: zpl, offsetMM: -5, dpmm: 8)
        XCTAssertTrue(shifted.contains("^FO0,50"))
    }
}
