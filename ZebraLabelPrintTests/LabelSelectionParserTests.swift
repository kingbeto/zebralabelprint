import XCTest
@testable import ZebraLabelPrint

final class LabelSelectionParserTests: XCTestCase {
    func testParseLabelPagesListAndRange() {
        let result = LabelSelectionParser.parseLabelPages("1, 5, 10-20", maxLabel: 25)
        guard case .success(let indices) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(indices, [1, 5, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
    }

    func testParseLabelPagesRejectsOutOfBounds() {
        let result = LabelSelectionParser.parseLabelPages("1, 30", maxLabel: 10)
        guard case .failure(let error) = result else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(error, .labelOutOfBounds(30, 10))
    }

    func testResolvedIndicesAll() {
        let result = LabelSelectionParser.resolvedIndices(
            scope: .all,
            labelsToPrintCount: 5,
            printRangeFrom: 1,
            printRangeTo: 5,
            printPagesText: ""
        )
        guard case .success(let indices) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(indices, [1, 2, 3, 4, 5])
    }

    func testResolvedIndicesRange() {
        let result = LabelSelectionParser.resolvedIndices(
            scope: .range,
            labelsToPrintCount: 10,
            printRangeFrom: 3,
            printRangeTo: 5,
            printPagesText: ""
        )
        guard case .success(let indices) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(indices, [3, 4, 5])
    }
}
