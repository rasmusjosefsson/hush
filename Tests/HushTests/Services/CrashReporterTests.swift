import XCTest
@testable import HushCore

final class CrashReporterTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "CrashReporterTests-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    private var tempFile: String { tempDir + "/crash_report.txt" }

    // MARK: - Tests

    func testParseValidSignalReport() {
        let content = """
        crash_type: signal
        signal: 11
        name: SIGSEGV
        timestamp: 1700000000
        app_ver: 1.0.0
        os_ver: 14.2.0
        uuid: AABBCCDD-1122-3344-5566-778899AABBCC
        slide: 0x100000
        --- stack ---
        0x1000abcde
        0x1000fghij
        0x100012345
        """
        try! content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: tempFile)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.crashType, "signal")
        XCTAssertEqual(report?.signal, "11")
        XCTAssertEqual(report?.name, "SIGSEGV")
        XCTAssertEqual(report?.timestamp, "1700000000")
        XCTAssertEqual(report?.appVersion, "1.0.0")
        XCTAssertEqual(report?.osVersion, "14.2.0")
        XCTAssertEqual(report?.uuid, "AABBCCDD-1122-3344-5566-778899AABBCC")
        XCTAssertEqual(report?.slide, "0x100000")
        XCTAssertNil(report?.reason)
        XCTAssertEqual(report?.stackTrace.count, 3)
        XCTAssertEqual(report?.stackTrace.first, "0x1000abcde")
    }

    func testParseTruncatedReport() {
        // Missing app_ver — required field, should return nil
        let truncated = """
        crash_type: signal
        signal: 6
        name: SIGABRT
        """
        try! truncated.write(toFile: tempFile, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: tempFile)
        XCTAssertNil(report, "Truncated report missing required fields should return nil")
    }

    func testMissingFileReturnsNil() {
        let report = CrashReporter.loadPendingReport(from: tempDir + "/nonexistent.txt")
        XCTAssertNil(report)
    }

    func testParseExceptionReport() {
        let content = """
        crash_type: exception
        signal: exception
        name: NSInvalidArgumentException
        timestamp: 1700000001
        app_ver: 1.0.0
        os_ver: 14.2.0
        uuid: AABBCCDD-1122-3344-5566-778899AABBCC
        slide: 0x100000
        reason: unrecognized selector sent to instance 0x600000\\nmore detail
        --- stack ---
        0x1000abcde
        0x1000fghij
        """
        try! content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        let report = CrashReporter.loadPendingReport(from: tempFile)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.crashType, "exception")
        XCTAssertEqual(report?.name, "NSInvalidArgumentException")
        XCTAssertEqual(report?.reason, "unrecognized selector sent to instance 0x600000\nmore detail")
        XCTAssertEqual(report?.stackTrace.count, 2)
    }

    func testDeleteRemovesFile() {
        let content = "crash_type: signal\nsignal: 11\nname: SIGSEGV\ntimestamp: 0\napp_ver: 1.0\n"
        try! content.write(toFile: tempFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile))

        CrashReporter.deletePendingReport(at: tempFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile))
    }
}
