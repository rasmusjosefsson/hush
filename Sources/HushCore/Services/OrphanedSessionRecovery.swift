import AVFAudio
import Foundation

public struct OrphanedSession: Sendable {
    public let sessionID: UUID
    public let startedAt: Date
    public let folderURL: URL
    public let availableAudioURLs: [URL]
}

public enum OrphanedSessionRecovery {
    /// Check for an orphaned recording session. Returns the session info if recoverable audio exists.
    /// Always cleans up the journal file regardless of outcome.
    public static func check(journalPath: String = AppPaths.sessionJournalPath) -> OrphanedSession? {
        guard let entry = RecordingSessionJournal.load(from: journalPath) else { return nil }
        RecordingSessionJournal.delete(at: journalPath)

        let fm = FileManager.default
        let folderURL = URL(fileURLWithPath: entry.folderPath)
        guard fm.fileExists(atPath: entry.folderPath) else { return nil }

        let candidatePaths = [entry.microphoneAudioPath, entry.systemAudioPath]
        var validURLs: [URL] = []
        for path in candidatePaths {
            let url = URL(fileURLWithPath: path)
            guard fm.fileExists(atPath: path) else { continue }
            guard let audioFile = try? AVAudioFile(forReading: url), audioFile.length > 0 else { continue }
            validURLs.append(url)
        }

        guard !validURLs.isEmpty else { return nil }

        return OrphanedSession(
            sessionID: entry.sessionID,
            startedAt: entry.startedAt,
            folderURL: folderURL,
            availableAudioURLs: validURLs
        )
    }
}
