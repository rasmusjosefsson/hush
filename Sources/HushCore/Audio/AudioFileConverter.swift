import Foundation
import os

public protocol AudioFileConverting: Sendable {
    func convert(fileURL: URL) async throws -> URL
    func mixToM4A(inputURLs: [URL], outputURL: URL) async throws
}

/// Converts audio/video files to 16kHz mono WAV using FFmpeg subprocess.
public final class AudioFileConverter: AudioFileConverting, Sendable {
    public init() {}
    /// Supported audio extensions
    public static let supportedAudioExtensions: Set<String> = [
        "mp3", "wav", "m4a", "flac", "ogg", "opus"
    ]

    /// Supported video extensions (audio will be extracted)
    public static let supportedVideoExtensions: Set<String> = [
        "mp4", "mov", "mkv", "webm", "avi"
    ]

    /// All supported extensions
    public static var supportedExtensions: Set<String> {
        supportedAudioExtensions.union(supportedVideoExtensions)
    }

    /// Check if a file extension is supported
    public static func isSupported(extension ext: String) -> Bool {
        supportedExtensions.contains(ext.lowercased())
    }

    /// Convert any supported audio/video file to 16kHz mono WAV.
    /// Returns the path to the converted WAV file in the temp directory.
    public func convert(fileURL: URL) async throws -> URL {
        let ext = fileURL.pathExtension.lowercased()
        guard Self.isSupported(extension: ext) else {
            throw AudioProcessorError.unsupportedFormat(ext)
        }

        let tempDir = try ensureTempDir()
        let ffmpegPath = try findFFmpeg()

        return try await runFFmpegConversion(
            ffmpegPath: ffmpegPath, inputURL: fileURL, tempDir: tempDir
        )
    }

    // MARK: - Private

    private func runFFmpegConversion(
        ffmpegPath: String, inputURL: URL, tempDir: URL
    ) async throws -> URL {
        let outputURL = tempDir.appendingPathComponent("\(UUID().uuidString).wav")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-nostdin",
            "-i", inputURL.path,
            "-ar", "16000",
            "-ac", "1",
            "-f", "wav",
            "-acodec", "pcm_f32le",
            "-y",
            outputURL.path
        ]

        let stderrURL = tempDir.appendingPathComponent("ffmpeg-stderr-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: stderrURL) }
        FileManager.default.createFile(atPath: stderrURL.path, contents: Data())
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer { stderrHandle.closeFile() }

        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrHandle

        try await runProcessAndWait(process, timeout: 600)

        if process.terminationStatus != 0 {
            stderrHandle.synchronizeFile()
            let stderrStr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? "Unknown error"
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioProcessorError.conversionFailed(stderrStr)
        }

        return outputURL
    }

    private func ensureTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hush", isDirectory: true)
        if !FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        }
        return tempDir
    }

    private func findFFmpeg() throws -> String {
        // Check environment variable first
        if let envPath = ProcessInfo.processInfo.environment["FFMPEG_PATH"],
           FileManager.default.isExecutableFile(atPath: envPath) {
            return envPath
        }
        // Check common paths
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        throw AudioProcessorError.conversionFailed(
            "FFmpeg not found. Install via `brew install ffmpeg` or set FFMPEG_PATH."
        )
    }

    private func runProcessAndWait(_ process: Process, timeout: TimeInterval) async throws {
        try process.run()

        let resumed = OSAllocatedUnfairLock(initialState: false)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let timeoutItem = DispatchWorkItem {
                    let shouldResume = resumed.withLock { done -> Bool in
                        guard !done else { return false }
                        done = true
                        return true
                    }
                    if shouldResume {
                        process.terminate()
                        continuation.resume(
                            throwing: AudioProcessorError.conversionFailed("FFmpeg conversion timed out")
                        )
                    }
                }

                process.terminationHandler = { _ in
                    let shouldResume = resumed.withLock { done -> Bool in
                        guard !done else { return false }
                        done = true
                        return true
                    }
                    if shouldResume {
                        continuation.resume()
                        timeoutItem.cancel()
                    }
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

                if !process.isRunning {
                    let shouldResume = resumed.withLock { done -> Bool in
                        guard !done else { return false }
                        done = true
                        return true
                    }
                    if shouldResume {
                        continuation.resume()
                        timeoutItem.cancel()
                    }
                }
            }
        } onCancel: {
            process.terminate()
        }

        try Task.checkCancellation()
    }

    public func mixToM4A(inputURLs: [URL], outputURL: URL) async throws {
        guard !inputURLs.isEmpty else {
            throw AudioProcessorError.conversionFailed("No audio files to mix")
        }

        let ffmpegPath = try findFFmpeg()
        var args = ["-nostdin"]
        for url in inputURLs {
            args.append(contentsOf: ["-i", url.path])
        }

        if inputURLs.count == 2 {
            args.append(contentsOf: [
                "-filter_complex",
                "[0:a]pan=stereo|c0=c0|c1=0*c0[a0];[1:a]pan=stereo|c0=0*c0|c1=c0[a1];[a0][a1]amix=inputs=2:duration=longest:normalize=0[a]",
                "-map", "[a]",
                "-ar", "48000", "-ac", "2", "-c:a", "aac", "-b:a", "128k",
            ])
        } else {
            let inputRefs = inputURLs.indices.map { "[\($0):a]" }.joined()
            args.append(contentsOf: [
                "-filter_complex",
                "\(inputRefs)amix=inputs=\(inputURLs.count):duration=longest:normalize=1",
                "-ar", "16000", "-ac", "1", "-c:a", "aac", "-b:a", "64k",
            ])
        }
        args.append(contentsOf: ["-y", outputURL.path])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try await runProcessAndWait(process, timeout: 600)

        if process.terminationStatus != 0 {
            throw AudioProcessorError.conversionFailed("FFmpeg mix failed (exit \(process.terminationStatus))")
        }
    }
}
