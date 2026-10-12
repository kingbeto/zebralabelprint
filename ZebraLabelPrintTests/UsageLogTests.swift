import XCTest
@testable import ZebraLabelPrint

final class UsageLogTests: XCTestCase {
    func testLineSortsKeysAndOmitsEmptyFields() {
        let date = ISO8601DateFormatter().date(from: "2026-10-12T14:00:00Z")!
        let line = UsageLog.line(event: "print", fields: ["ok": "1", "why": "", "n": "2"], at: date)
        XCTAssertEqual(line, #"{"e":"print","n":"2","ok":"1","t":"2026-10-12T14:00:00Z"}"#)
    }

    func testRecordAppendsOneJSONLinePerEvent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("usage.jsonl")
        let previous = UsageLog.fileURL
        UsageLog.fileURL = url
        defer {
            UsageLog.fileURL = previous
            try? FileManager.default.removeItem(at: dir)
        }

        UsageLog.record("launch")
        UsageLog.record("print", ["ok": "1"])

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }.count, 2)
        XCTAssertTrue(text.contains(#""e":"launch""#))
        XCTAssertTrue(text.contains(#""e":"print""#))
    }
}
