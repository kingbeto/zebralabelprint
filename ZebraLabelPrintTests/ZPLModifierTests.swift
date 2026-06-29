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
}
