import Foundation
import os

/// Append-only file logger that persists key events to disk.
/// Supplements OSLog so users can diagnose issues like lost recordings across app restarts.
public final class FileLogger: Sendable {
    public enum Level: String, Sendable {
        case info, warning, error
    }

    public enum Category: String, Sendable {
        case recording, capture, crash, app
    }

    public static let shared = FileLogger()

    private let state: LockedState

    public init(directory: String = AppPaths.logsDir, maxFileSize: Int = 5_000_000) {
        self.state = LockedState(directory: directory, maxFileSize: maxFileSize)
    }

    public func log(_ message: String, level: Level = .info, category: Category = .app) {
        state.write(message, level: level, category: category)
    }
}

// MARK: - Thread-safe mutable state

private final class LockedState: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let directory: String
    private let maxFileSize: Int
    private let formatter: ISO8601DateFormatter
    private var fileHandle: FileHandle?
    private var currentSize: Int = 0
    private var directoryCreated = false

    var logPath: String { "\(directory)/hush.log" }
    var rotatedPath: String { "\(directory)/hush.log.1" }

    init(directory: String, maxFileSize: Int) {
        self.directory = directory
        self.maxFileSize = maxFileSize
        self.formatter = ISO8601DateFormatter()
        self.formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func write(_ message: String, level: FileLogger.Level, category: FileLogger.Category) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try ensureHandle()
            guard let handle = fileHandle else { return }

            let timestamp = formatter.string(from: Date())
            let line = "[\(timestamp)] [\(level.rawValue.uppercased())] [\(category.rawValue)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            handle.write(data)
            currentSize += data.count

            if currentSize >= maxFileSize {
                try rotate()
            }
        } catch {
            // Never crash -- silently skip the write
        }
    }

    private func ensureHandle() throws {
        if fileHandle != nil { return }

        let fm = FileManager.default
        if !directoryCreated {
            if !fm.fileExists(atPath: directory) {
                try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
            }
            directoryCreated = true
        }

        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: nil)
            currentSize = 0
        } else {
            let attrs = try fm.attributesOfItem(atPath: logPath)
            currentSize = (attrs[.size] as? Int) ?? 0
        }

        fileHandle = FileHandle(forWritingAtPath: logPath)
        fileHandle?.seekToEndOfFile()
    }

    private func rotate() throws {
        fileHandle?.closeFile()
        fileHandle = nil

        let fm = FileManager.default
        if fm.fileExists(atPath: rotatedPath) {
            try fm.removeItem(atPath: rotatedPath)
        }
        try fm.moveItem(atPath: logPath, toPath: rotatedPath)

        fm.createFile(atPath: logPath, contents: nil)
        currentSize = 0
        fileHandle = FileHandle(forWritingAtPath: logPath)
    }
}
