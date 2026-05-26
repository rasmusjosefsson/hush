import XCTest
import GRDB
@testable import HushCore

final class DatabaseManagerTests: XCTestCase {

    func testInMemoryDatabaseCreates() throws {
        let manager = try DatabaseManager()
        XCTAssertNotNil(manager.dbQueue)
    }

    func testMigrationsCreateTables() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("dictations"))
            XCTAssertTrue(try db.tableExists("transcriptions"))
            // dictations_fts was dropped in v0.5-drop-unused-fts (never queried, wasted write overhead)
            XCTAssertFalse(try db.tableExists("dictations_fts"))
        }
    }

    func testMigrationsCreateIndexes() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            let dictationIndexes = try db.indexes(on: "dictations")
            XCTAssertTrue(dictationIndexes.contains { $0.name == "idx_dictations_created_at" })

            let transcriptionIndexes = try db.indexes(on: "transcriptions")
            XCTAssertTrue(transcriptionIndexes.contains { $0.name == "idx_transcriptions_created_at" })
        }
    }

    func testSourceURLColumnExists() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            let columns = try db.columns(in: "transcriptions")
            let columnNames = columns.map(\.name)
            XCTAssertTrue(columnNames.contains("sourceURL"), "transcriptions should have sourceURL column")
        }
    }

    func testVideoMetadataColumnsExist() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            let columns = try db.columns(in: "transcriptions").map(\.name)
            XCTAssertTrue(columns.contains("thumbnailURL"), "transcriptions should have thumbnailURL column")
            XCTAssertTrue(columns.contains("channelName"), "transcriptions should have channelName column")
            XCTAssertTrue(columns.contains("videoDescription"), "transcriptions should have videoDescription column")
            XCTAssertTrue(columns.contains("isFavorite"), "transcriptions should have isFavorite column")
        }
    }

    func testMigrationsAreIdempotent() throws {
        // Running migrations twice on the SAME database file should not error
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("idempotent_test_\(UUID().uuidString).db").path

        // First run — creates tables and indexes
        let manager1 = try DatabaseManager(path: dbPath)
        try manager1.dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("dictations"))
            XCTAssertTrue(try db.tableExists("transcriptions"))
        }

        // Second run on the SAME file — migrations should be skipped gracefully
        let manager2 = try DatabaseManager(path: dbPath)
        try manager2.dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("dictations"))
            XCTAssertTrue(try db.tableExists("transcriptions"))
        }

        // Clean up
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    func testDictationReprocessColumnsExistWithOriginDefault() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.read { db in
            let columns = try db.columns(in: "dictations").map(\.name)
            XCTAssertTrue(columns.contains("derivedFromDictationId"))
            XCTAssertTrue(columns.contains("processingOrigin"))
            XCTAssertTrue(columns.contains("wordTimestamps"))
            XCTAssertTrue(columns.contains("speakers"))
            XCTAssertTrue(columns.contains("speakerCount"))
            XCTAssertTrue(columns.contains("diarizationSegments"))
        }
    }

    func testDictationProcessingOriginDefaultsToOriginal() throws {
        let manager = try DatabaseManager()
        try manager.dbQueue.write { db in
            let id = UUID().uuidString
            let now = ISO8601DateFormatter().string(from: Date())
            try db.execute(
                sql: """
                    INSERT INTO dictations (id, createdAt, durationMs, rawTranscript, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [id, now, 1000, "hello", now]
            )
            let origin: String? = try String.fetchOne(
                db,
                sql: "SELECT processingOrigin FROM dictations WHERE id = ?",
                arguments: [id]
            )
            XCTAssertEqual(origin, "original")
        }
    }
}
