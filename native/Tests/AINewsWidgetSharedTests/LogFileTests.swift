import XCTest
@testable import AINewsWidgetShared

final class LogFileTests: XCTestCase {
    private func tempFile() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("test.log")
    }

    func testAppendKeepsFileUnderCapAndEndsWithNewestLine() throws {
        let url = try tempFile()
        for index in 0..<500 {
            let line = "line-\(String(format: "%04d", index)) \(String(repeating: "x", count: 40))\n"
            try LogFile.append(Data(line.utf8), to: url, maxBytes: 4_000, keepBytes: 2_000)
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertLessThanOrEqual(contents.utf8.count, 4_000)
        XCTAssertTrue(contents.hasSuffix("line-0499 \(String(repeating: "x", count: 40))\n"))
        // Trimmed on a line boundary: the first line is a whole entry.
        XCTAssertTrue(contents.hasPrefix("line-"))
    }

    func testOversizedExistingFileIsTrimmedOnNextAppend() throws {
        let url = try tempFile()
        let big = (0..<1_000).map { "old-\($0)\n" }.joined()
        try Data(big.utf8).write(to: url)
        try LogFile.append(Data("new\n".utf8), to: url, maxBytes: 1_000, keepBytes: 500)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertLessThanOrEqual(contents.utf8.count, 500)
        XCTAssertTrue(contents.hasSuffix("new\n"))
        XCTAssertTrue(contents.hasPrefix("old-"))
    }

    func testSmallFileIsLeftAlone() throws {
        let url = try tempFile()
        try LogFile.append(Data("a\n".utf8), to: url)
        try LogFile.append(Data("b\n".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a\nb\n")
    }
}
