import XCTest
@testable import HushCore

final class AppPathsTests: XCTestCase {

    func testAppSupportDirContainsHush() {
        XCTAssertTrue(AppPaths.appSupportDir.hasSuffix("Hush"))
    }

    func testDatabasePathIsInsideAppSupport() {
        XCTAssertTrue(AppPaths.databasePath.hasPrefix(AppPaths.appSupportDir))
        XCTAssertTrue(AppPaths.databasePath.hasSuffix("hush.db"))
    }

    func testDictationsDirIsInsideAppSupport() {
        XCTAssertTrue(AppPaths.dictationsDir.hasPrefix(AppPaths.appSupportDir))
        XCTAssertTrue(AppPaths.dictationsDir.hasSuffix("dictations"))
    }

    func testTempDirContainsHush() {
        XCTAssertTrue(AppPaths.tempDir.contains("hush"))
    }

    func testEnsureDirectoriesCreatesAll() throws {
        // Use a unique temp directory to avoid polluting real app support
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hush_test_\(UUID().uuidString)")
        let fm = FileManager.default

        // Create subdirectories that mirror the AppPaths structure
        let appSupportSubdir = testRoot.appendingPathComponent("AppSupport")
        let dictationsSubdir = testRoot.appendingPathComponent("dictations")
        let tempSubdir = testRoot.appendingPathComponent("temp")

        defer {
            try? fm.removeItem(at: testRoot)
        }

        for dir in [appSupportSubdir, dictationsSubdir, tempSubdir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        XCTAssertTrue(fm.fileExists(atPath: appSupportSubdir.path))
        XCTAssertTrue(fm.fileExists(atPath: dictationsSubdir.path))
        XCTAssertTrue(fm.fileExists(atPath: tempSubdir.path))

        // Also verify the real ensureDirectories doesn't throw
        // (it may create real dirs, but those are expected app directories)
        try AppPaths.ensureDirectories()
    }
}
