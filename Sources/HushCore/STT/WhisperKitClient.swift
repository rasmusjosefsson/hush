// Sources/HushCore/STT/WhisperKitClient.swift
import Foundation
import WhisperKit
import os

/// STT backend backed by WhisperKit CoreML/ANE runtime (Whisper models).
public actor WhisperKitClient: STTClientProtocol {
    private var whisperKit: WhisperKit?
    private var initializationTask: Task<Void, Error>?
    private var warmUpProgressHandler: (@Sendable (String) -> Void)?
    private let modelVariant: String

    /// - Parameter modelVariant: e.g. "large-v3-turbo", "large-v3", "small"
    public init(modelVariant: String = "large-v3-turbo") {
        self.modelVariant = modelVariant
    }

    public func transcribe(audioPath: String, job: STTJobKind = .dictation, onProgress: (@Sendable (Int, Int) -> Void)?) async throws -> STTResult {
        try await ensureInitialized()

        guard let kit = whisperKit else {
            throw STTError.modelNotLoaded
        }

        onProgress?(0, 100)

        do {
            let options = DecodingOptions(wordTimestamps: true)
            let results: [TranscriptionResult] = try await kit.transcribe(audioPath: audioPath, decodeOptions: options)
            guard let result = results.first else {
                throw STTError.invalidResponse
            }

            let words = result.allWords.map { wordTiming in
                TimestampedWord(
                    word: wordTiming.word,
                    startMs: Int((Double(wordTiming.start) * 1_000).rounded()),
                    endMs: Int((Double(wordTiming.end) * 1_000).rounded()),
                    confidence: Double(wordTiming.probability)
                )
            }

            onProgress?(100, 100)
            return STTResult(text: result.text, words: words)
        } catch let error as STTError {
            throw error
        } catch {
            throw STTError.transcriptionFailed(error.localizedDescription)
        }
    }

    public func warmUp(onProgress: (@Sendable (String) -> Void)?) async throws {
        warmUpProgressHandler = onProgress
        defer { warmUpProgressHandler = nil }
        do {
            try await ensureInitialized()
            onProgress?("Ready")
        } catch {
            throw STTError.engineStartFailed(error.localizedDescription)
        }
    }

    public func isReady() async -> Bool {
        whisperKit != nil
    }

    public func shutdown() async {
        initializationTask?.cancel()
        initializationTask = nil
        whisperKit = nil
    }

    public func clearModelCache() async {
        await shutdown()
    }

    public func backgroundWarmUp() async {
        try? await warmUp(onProgress: nil)
    }

    public func observeWarmUpProgress() async -> (id: UUID, stream: AsyncStream<STTWarmUpState>) {
        let id = UUID()
        let stream = AsyncStream<STTWarmUpState> { continuation in
            continuation.yield(.ready)
            continuation.finish()
        }
        return (id, stream)
    }

    public func removeWarmUpObserver(id: UUID) async {
    }

    /// Check if a WhisperKit model variant is already downloaded on disk.
    public nonisolated static func isModelCached(variant: String) -> Bool {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelDir = documents
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(variant)
        return FileManager.default.fileExists(atPath: modelDir.path)
    }

    // MARK: - Private

    private func ensureInitialized() async throws {
        if whisperKit != nil { return }

        if let task = initializationTask {
            try await task.value
            return
        }

        let variant = modelVariant
        let progressHandler = warmUpProgressHandler
        let task = Task {
            // Phase 1: Download model with progress reporting
            progressHandler?("Downloading Whisper model... 0%")
            let lastProgressUpdate = OSAllocatedUnfairLock(initialState: Date.distantPast)
            let modelFolder = try await WhisperKit.download(
                variant: variant
            ) { progress in
                let percent = Int(progress.fractionCompleted * 100)
                let message = "Downloading Whisper model... \(percent)%"
                let now = Date()
                let shouldEmit = lastProgressUpdate.withLock { lastUpdate in
                    guard now.timeIntervalSince(lastUpdate) >= 0.25 else { return false }
                    lastUpdate = now
                    return true
                }
                guard shouldEmit else { return }
                progressHandler?(message)
            }

            // Phase 2: Load model from downloaded folder
            progressHandler?("Loading Whisper model...")
            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,
                download: false
            )
            let kit = try await WhisperKit(config)
            await completeInitialization(kit: kit)
        }

        initializationTask = task

        do {
            try await task.value
        } catch {
            initializationTask = nil
            throw error
        }
    }

    private func completeInitialization(kit: WhisperKit) async {
        guard !Task.isCancelled else { return }
        self.whisperKit = kit
        self.initializationTask = nil
    }
}
