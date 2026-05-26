import Foundation

public struct RecordingSessionEntry: Codable, Sendable {
    public let sessionID: UUID
    public let startedAt: Date
    public let folderPath: String
    public let microphoneAudioPath: String
    public let systemAudioPath: String

    public init(
        sessionID: UUID,
        startedAt: Date,
        folderPath: String,
        microphoneAudioPath: String,
        systemAudioPath: String
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.folderPath = folderPath
        self.microphoneAudioPath = microphoneAudioPath
        self.systemAudioPath = systemAudioPath
    }
}

public enum RecordingSessionJournal {
    /// Write journal entry when recording starts. Overwrites any existing entry.
    public static func write(_ entry: RecordingSessionEntry, to path: String = AppPaths.sessionJournalPath) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        let url = URL(fileURLWithPath: path)
        try data.write(to: url, options: .atomic)
    }

    /// Load journal entry if one exists (means previous session didn't finish cleanly).
    public static func load(from path: String = AppPaths.sessionJournalPath) -> RecordingSessionEntry? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RecordingSessionEntry.self, from: data)
    }

    /// Delete journal file (call on clean stop/cancel).
    public static func delete(at path: String = AppPaths.sessionJournalPath) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
