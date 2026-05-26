import CoreAudio
import Foundation
import OSLog
@preconcurrency import AVFoundation

/// Unified audio processor that handles both microphone capture and file conversion.
/// When `captureSystemAudio` is true, also records system audio via Core Audio Taps
/// and mixes both streams into the output file.
public actor AudioProcessor: AudioProcessorProtocol {
    private let recorder: AudioRecorder
    private let converter: AudioFileConverter
    private let preferredDeviceID: @Sendable () -> AudioDeviceID?
    private let captureSystemAudio: @Sendable () -> Bool
    private let logger = Logger(subsystem: "com.hush.core", category: "AudioProcessor")

    private var systemTap: (any Sendable)? // SystemAudioTap (macOS 14.2+), type-erased for availability
    private var systemAudioURL: URL?
    /// Lock-protected state for the nonisolated audio write callback.
    private let systemState = SystemAudioWriteState()

    public init(
        preferredDeviceID: (@Sendable () -> AudioDeviceID?)? = nil,
        captureSystemAudio: (@Sendable () -> Bool)? = nil
    ) {
        self.recorder = AudioRecorder()
        self.converter = AudioFileConverter()
        self.preferredDeviceID = preferredDeviceID ?? { nil }
        self.captureSystemAudio = captureSystemAudio ?? { false }
    }

    public var audioLevel: Float {
        get async { await recorder.audioLevel }
    }

    public var isRecording: Bool {
        get async { await recorder.isRecording }
    }

    public var recordingDeviceInfo: RecordingDeviceInfo? {
        get async { await recorder.deviceInfo }
    }

    public func convert(fileURL: URL) async throws -> URL {
        try await converter.convert(fileURL: fileURL)
    }

    public func startCapture() async throws {
        try await recorder.start(preferredDeviceID: preferredDeviceID())

        // Start system audio capture if enabled
        guard captureSystemAudio() else { return }
        guard #available(macOS 14.2, *) else {
            throw AudioProcessorError.recordingFailed(
                "System audio capture requires macOS 14.2 or later."
            )
        }

        // Check Screen Recording permission before attempting capture
        if !CGPreflightScreenCaptureAccess() {
            // Prompt the user for permission
            CGRequestScreenCaptureAccess()
            // Check again after prompt
            if !CGPreflightScreenCaptureAccess() {
                throw AudioProcessorError.recordingFailed(
                    "Screen & System Audio Recording permission is required to capture system audio. Grant it in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
                )
            }
        }

        do {
            let tap = SystemAudioTap()
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("hush", isDirectory: true)
            if !FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            }
            let url = tempDir.appendingPathComponent("system-\(UUID().uuidString).wav")

            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            ) else {
                logger.warning("system_audio_capture failed to create output format")
                return
            }

            let file = try AVAudioFile(forWriting: url, settings: outputFormat.settings)
            systemState.lock.withLock {
                systemState.file = file
                systemState.converter = nil
                systemState.writtenFrames = 0
            }
            self.systemAudioURL = url

            try tap.start { [weak self] buffer, _ in
                self?.writeSystemBuffer(buffer, to: file, targetFormat: outputFormat)
            }
            self.systemTap = tap
            logger.info("system_audio_capture started")
        } catch {
            logger.warning("system_audio_capture_failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    public func stopCapture() async throws -> URL {
        // Stop system audio tap
        if #available(macOS 14.2, *), let tap = systemTap as? SystemAudioTap {
            tap.stop()
        }
        systemTap = nil
        systemState.lock.withLock { systemState.file = nil; systemState.converter = nil }
        let sysURL = systemAudioURL
        systemAudioURL = nil
        let sysFrames = systemState.lock.withLock { systemState.writtenFrames }
        systemState.lock.withLock { systemState.writtenFrames = 0 }

        // Stop mic recording
        let micURL = try await recorder.stop()

        // If we captured system audio, mix the two into one file
        if let sysURL, sysFrames > 0 {
            let tempDir = micURL.deletingLastPathComponent()
            let mixedM4A = tempDir.appendingPathComponent("mixed-\(UUID().uuidString).m4a")
            do {
                // Mix mic + system into M4A, then convert to 16kHz mono WAV for STT
                try await converter.mixToM4A(inputURLs: [micURL, sysURL], outputURL: mixedM4A)
                let mixedWAV = try await converter.convert(fileURL: mixedM4A)
                try? FileManager.default.removeItem(at: micURL)
                try? FileManager.default.removeItem(at: sysURL)
                try? FileManager.default.removeItem(at: mixedM4A)
                logger.info("system_audio_mixed mic+system → \(mixedWAV.lastPathComponent)")
                return mixedWAV
            } catch {
                logger.warning("system_audio_mix_failed error=\(error.localizedDescription, privacy: .public) — using mic only")
                try? FileManager.default.removeItem(at: sysURL)
                try? FileManager.default.removeItem(at: mixedM4A)
                return micURL
            }
        } else {
            if let sysURL { try? FileManager.default.removeItem(at: sysURL) }
            return micURL
        }
    }

    /// Write a system audio buffer to the WAV file, converting format if needed.
    /// Called from the Core Audio tap thread — must be fast and non-blocking.
    nonisolated private func writeSystemBuffer(
        _ buffer: AVAudioPCMBuffer,
        to file: AVAudioFile,
        targetFormat: AVAudioFormat
    ) {
        let needsConversion = buffer.format.sampleRate != targetFormat.sampleRate
            || buffer.format.channelCount != targetFormat.channelCount
            || buffer.format.commonFormat != targetFormat.commonFormat

        let writeBuffer: AVAudioPCMBuffer
        if needsConversion {
            let converter: AVAudioConverter? = systemState.lock.withLock {
                if let existing = self.systemState.converter, existing.inputFormat.sampleRate == buffer.format.sampleRate {
                    return existing
                }
                let conv = AVAudioConverter(from: buffer.format, to: targetFormat)
                self.systemState.converter = conv
                return conv
            }
            guard let converter else { return }

            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            var provided = false
            let status = converter.convert(to: output, error: nil) { _, outStatus in
                if provided { outStatus.pointee = .noDataNow; return nil }
                provided = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard status == .haveData else { return }
            writeBuffer = output
        } else {
            writeBuffer = buffer
        }

        systemState.lock.withLock {
            do {
                try file.write(from: writeBuffer)
                self.systemState.writtenFrames += Int64(writeBuffer.frameLength)
            } catch {
                // Audio thread — can't log, just drop the buffer
            }
        }
    }
}

/// Thread-safe state for system audio writing from the Core Audio tap callback.
private final class SystemAudioWriteState: @unchecked Sendable {
    let lock = NSLock()
    var file: AVAudioFile?
    var converter: AVAudioConverter?
    var writtenFrames: Int64 = 0

    func reset() {
        lock.withLock {
            file = nil
            converter = nil
            writtenFrames = 0
        }
    }
}
