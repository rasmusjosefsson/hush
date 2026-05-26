import XCTest
@testable import HushCore

final class RecordingSessionJournalTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private var journalPath: String {
        tempDir.appendingPathComponent("recording_session.json").path
    }

    private func makeEntry(
        sessionID: UUID = UUID(),
        folderPath: String = "/tmp/session",
        micPath: String = "/tmp/session/mic.caf",
        sysPath: String = "/tmp/session/sys.caf"
    ) -> RecordingSessionEntry {
        RecordingSessionEntry(
            sessionID: sessionID,
            startedAt: Date(),
            folderPath: folderPath,
            microphoneAudioPath: micPath,
            systemAudioPath: sysPath
        )
    }

    func testWriteAndLoad() throws {
        let id = UUID()
        let entry = RecordingSessionEntry(
            sessionID: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            folderPath: "/tmp/sess",
            microphoneAudioPath: "/tmp/sess/mic.caf",
            systemAudioPath: "/tmp/sess/sys.caf"
        )
        try RecordingSessionJournal.write(entry, to: journalPath)
        let loaded = RecordingSessionJournal.load(from: journalPath)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionID, id)
        XCTAssertEqual(loaded?.startedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(loaded?.folderPath, "/tmp/sess")
        XCTAssertEqual(loaded?.microphoneAudioPath, "/tmp/sess/mic.caf")
        XCTAssertEqual(loaded?.systemAudioPath, "/tmp/sess/sys.caf")
    }

    func testDeleteRemovesFile() throws {
        let entry = makeEntry()
        try RecordingSessionJournal.write(entry, to: journalPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalPath))
        RecordingSessionJournal.delete(at: journalPath)
        XCTAssertNil(RecordingSessionJournal.load(from: journalPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalPath))
    }

    func testLoadReturnsNilWhenNoFile() {
        let missing = tempDir.appendingPathComponent("nope.json").path
        XCTAssertNil(RecordingSessionJournal.load(from: missing))
    }

    func testLoadReturnsNilForCorruptFile() throws {
        try Data("not json".utf8).write(to: URL(fileURLWithPath: journalPath))
        XCTAssertNil(RecordingSessionJournal.load(from: journalPath))
    }

    func testOverwritesPreviousEntry() throws {
        let a = makeEntry(sessionID: UUID())
        let bID = UUID()
        let b = makeEntry(sessionID: bID)
        try RecordingSessionJournal.write(a, to: journalPath)
        try RecordingSessionJournal.write(b, to: journalPath)
        let loaded = RecordingSessionJournal.load(from: journalPath)
        XCTAssertEqual(loaded?.sessionID, bID)
    }
}
