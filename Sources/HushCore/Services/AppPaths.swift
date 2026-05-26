import Foundation

/// Centralized path management for Hush runtime files.
public enum AppPaths {
    /// Application Support directory
    public static var appSupportDir: String {
        let path = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .path
            ?? (NSHomeDirectory() + "/Library/Application Support")
        return path + "/Hush"
    }

    /// Database file path
    public static var databasePath: String {
        "\(appSupportDir)/hush.db"
    }

    /// Audio storage directory for dictations
    public static var dictationsDir: String {
        "\(appSupportDir)/dictations"
    }

    /// Meeting recordings storage
    public static var meetingRecordingsDir: String {
        "\(appSupportDir)/meetings"
    }

    /// Diagnostic logs directory
    public static var logsDir: String {
        "\(appSupportDir)/logs"
    }

    /// Crash report file (written by signal handler, consumed on next launch)
    public static var crashReportPath: String {
        "\(appSupportDir)/crash_report.txt"
    }

    /// Recording session journal (exists only while a recording is in progress)
    public static var sessionJournalPath: String {
        "\(appSupportDir)/recording_session.json"
    }

    /// Temp directory for audio processing
    public static var tempDir: String {
        "\(NSTemporaryDirectory())hush"
    }

    /// Ensure all required directories exist
    public static func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [appSupportDir, dictationsDir, meetingRecordingsDir, logsDir, tempDir] {
            if !fm.fileExists(atPath: dir) {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
    }
}
