import XCTest
@testable import HushCore

final class FileLoggerTests: XCTestCase {
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "hush-filelogger-test-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    func testWritesLogLine() throws {
        let logger = FileLogger(directory: tempDir)
        logger.log("hello world", level: .info, category: .app)

        let content = try String(contentsOfFile: tempDir + "/hush.log", encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 1)

        let line = String(lines[0])
        XCTAssertTrue(line.contains("[INFO]"), "Expected [INFO] in: \(line)")
        XCTAssertTrue(line.contains("[app]"), "Expected [app] in: \(line)")
        XCTAssertTrue(line.contains("hello world"), "Expected message in: \(line)")
        // Verify ISO8601 timestamp prefix
        XCTAssertTrue(line.hasPrefix("[20"), "Expected ISO8601 timestamp prefix in: \(line)")
    }

    func testAppendsMultipleLines() throws {
        let logger = FileLogger(directory: tempDir)
        logger.log("one", level: .info, category: .recording)
        logger.log("two", level: .warning, category: .capture)
        logger.log("three", level: .error, category: .crash)

        let content = try String(contentsOfFile: tempDir + "/hush.log", encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("one"))
        XCTAssertTrue(lines[1].contains("[WARNING]"))
        XCTAssertTrue(lines[2].contains("[ERROR]"))
    }

    func testRotatesAtSizeLimit() throws {
        let logger = FileLogger(directory: tempDir, maxFileSize: 500)
        let message = String(repeating: "x", count: 80)

        // Write enough to exceed 500 bytes
        for _ in 0..<20 {
            logger.log(message, level: .info, category: .app)
        }

        let fm = FileManager.default
        let rotatedPath = tempDir + "/hush.log.1"
        XCTAssertTrue(fm.fileExists(atPath: rotatedPath), "Rotated file should exist")

        let currentSize = try fm.attributesOfItem(atPath: tempDir + "/hush.log")[.size] as? Int ?? 0
        XCTAssertLessThan(currentSize, 500, "Current log should be smaller than max after rotation")
    }

    func testConcurrentWrites() throws {
        let logger = FileLogger(directory: tempDir)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<100 {
            group.enter()
            queue.async {
                logger.log("msg-\(i)", level: .info, category: .app)
                group.leave()
            }
        }
        group.wait()

        let content = try String(contentsOfFile: tempDir + "/hush.log", encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 100, "All 100 lines should be present")
    }

    func testHandlesMissingDirectory() {
        let bogusDir = "/tmp/hush-nonexistent-\(UUID().uuidString)/deep/nested"
        let logger = FileLogger(directory: bogusDir)
        // Should not crash
        logger.log("test", level: .error, category: .crash)

        // The logger should have created the directory and written
        let content = try? String(contentsOfFile: bogusDir + "/hush.log", encoding: .utf8)
        XCTAssertNotNil(content, "Logger should create missing directories")
        try? FileManager.default.removeItem(atPath: "/tmp/hush-nonexistent-\(bogusDir.split(separator: "/")[2])")
    }
}
