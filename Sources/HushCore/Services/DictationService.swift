import Foundation
import OSLog

public enum DictationState: Sendable {
    case idle
    case recording
    case processing
    case success(Dictation)
    case cancelled
    case error(String)
}

public enum DictationTrigger: String, Sendable, Equatable {
    case hotkey
    case pillClick = "pill_click"
    case menuBar = "menu_bar"
}

public enum DictationMode: String, Sendable, Equatable {
    case hold
    case persistent
}

public enum DictationCancelReason: String, Sendable, Equatable {
    case escape
    case hotkey
    case ui
}

public protocol DictationServiceProtocol: Sendable {
    func startRecording() async throws
    func stopRecording() async throws -> Dictation
    func reprocessWithSpeakers(dictationID: UUID, onProgress: (@Sendable (ReprocessingProgress) -> Void)?) async throws -> Dictation
    func cancelRecording(reason: DictationCancelReason?) async
    func confirmCancel() async
    func undoCancel() async throws -> Dictation
    var state: DictationState { get async }
    var audioLevel: Float { get async }
}

extension DictationServiceProtocol {
    public func reprocessWithSpeakers(dictationID: UUID) async throws -> Dictation {
        try await reprocessWithSpeakers(dictationID: dictationID, onProgress: nil)
    }
}

extension DictationServiceProtocol {
    public func cancelRecording() async {
        await cancelRecording(reason: nil)
    }
}

public actor DictationService: DictationServiceProtocol {
    private let logger = Logger(subsystem: "com.hush.core", category: "DictationService")
    private let audioProcessor: AudioProcessorProtocol
    private let sttClient: STTClientProtocol
    private let dictationRepo: DictationRepositoryProtocol
    private let shouldSaveAudio: (@Sendable () -> Bool)?
    private let shouldSaveDictationHistory: (@Sendable () -> Bool)?
    private let customWordRepo: CustomWordRepositoryProtocol?
    private let snippetRepo: TextSnippetRepositoryProtocol?
    private let processingMode: @Sendable () -> Dictation.ProcessingMode
    private let textRefinementService: TextRefinementService
    private let diarizationService: DiarizationServiceProtocol?
    private let selectedModelName: @Sendable () -> String?
    private let cancelWindow: Duration

    private var _state: DictationState = .idle
    private var cancelResetTask: Task<Void, Never>?
    private var cancelGeneration: Int = 0
    private var pendingCancelledAudioURL: URL?
    private var recordingStartedAt: Date?

    public var state: DictationState {
        _state
    }

    public var audioLevel: Float {
        get async { await audioProcessor.audioLevel }
    }

    public init(
        audioProcessor: AudioProcessorProtocol,
        sttClient: STTClientProtocol,
        dictationRepo: DictationRepositoryProtocol,
        shouldSaveAudio: (@Sendable () -> Bool)? = nil,
        shouldSaveDictationHistory: (@Sendable () -> Bool)? = nil,
        customWordRepo: CustomWordRepositoryProtocol? = nil,
        snippetRepo: TextSnippetRepositoryProtocol? = nil,
        processingMode: (@Sendable () -> Dictation.ProcessingMode)? = nil,
        diarizationService: DiarizationServiceProtocol? = nil,
        selectedModelName: (@Sendable () -> String?)? = nil,
        cancelWindow: Duration = .seconds(5)
    ) {
        self.audioProcessor = audioProcessor
        self.sttClient = sttClient
        self.dictationRepo = dictationRepo
        self.shouldSaveAudio = shouldSaveAudio
        self.shouldSaveDictationHistory = shouldSaveDictationHistory
        self.customWordRepo = customWordRepo
        self.snippetRepo = snippetRepo
        self.processingMode = processingMode ?? { .raw }
        self.textRefinementService = TextRefinementService()
        self.diarizationService = diarizationService
        self.selectedModelName = selectedModelName ?? { nil }
        self.cancelWindow = cancelWindow
    }

    public func startRecording() async throws {
        logger.debug("startRecording requested state=\(self.debugStateLabel(self._state), privacy: .public)")

        switch _state {
        case .idle, .cancelled:
            break
        default:
            return
        }

        discardPendingCancelledAudio()

        cancelResetTask?.cancel()
        cancelResetTask = nil

        _state = .recording
        do {
            try await audioProcessor.startCapture()
            guard case .recording = _state else {
                let _ = try? await audioProcessor.stopCapture()
                recordingStartedAt = nil
                return
            }
            recordingStartedAt = Date()
            logger.debug("startRecording capture started")
        } catch {
            _state = .idle
            recordingStartedAt = nil
            logger.error("startRecording failed error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func stopRecording() async throws -> Dictation {
        guard case .recording = _state else {
            logger.warning("stopRecording rejected state=\(self.debugStateLabel(self._state), privacy: .public)")
            throw DictationServiceError.notRecording
        }

        _state = .processing
        logger.debug("stopRecording processing begin")

        do {
            let audioURL = try await audioProcessor.stopCapture()
            logger.debug("stopRecording capture stopped url=\(audioURL.path, privacy: .public)")
            let dictation = try await processCapturedAudio(audioURL: audioURL)
            _state = .success(dictation)
            logger.debug("stopRecording success rawChars=\(dictation.rawTranscript.count) cleanChars=\(dictation.cleanTranscript?.count ?? 0)")
            try? await Task.sleep(for: .milliseconds(500))
            _state = .idle
            recordingStartedAt = nil
            return dictation
        } catch {
            _state = .idle
            recordingStartedAt = nil
            logger.error("stopRecording failed error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func cancelRecording(reason: DictationCancelReason? = nil) async {
        guard case .recording = _state else { return }

        cancelGeneration += 1
        let generation = cancelGeneration

        let audioURL = try? await audioProcessor.stopCapture()
        pendingCancelledAudioURL = audioURL
        _state = .cancelled

        cancelResetTask?.cancel()
        cancelResetTask = Task { [generation] in
            try? await Task.sleep(for: cancelWindow)
            resetAfterCancelIfStillCurrent(generation: generation)
        }
    }

    public func confirmCancel() async {
        cancelGeneration += 1
        cancelResetTask?.cancel()
        cancelResetTask = nil
        discardPendingCancelledAudio()

        if case .recording = _state {
            if let url = try? await audioProcessor.stopCapture() {
                try? FileManager.default.removeItem(at: url)
            }
        }

        recordingStartedAt = nil
        _state = .idle
    }

    public func undoCancel() async throws -> Dictation {
        guard case .cancelled = _state else {
            throw DictationServiceError.notCancelled
        }
        guard let audioURL = pendingCancelledAudioURL else {
            _state = .idle
            throw DictationServiceError.noPendingCancelledAudio
        }

        cancelGeneration += 1
        cancelResetTask?.cancel()
        cancelResetTask = nil
        pendingCancelledAudioURL = nil

        _state = .processing
        do {
            let dictation = try await processCapturedAudio(audioURL: audioURL)
            _state = .success(dictation)
            try? await Task.sleep(for: .milliseconds(500))
            _state = .idle
            recordingStartedAt = nil
            return dictation
        } catch {
            _state = .idle
            recordingStartedAt = nil
            throw error
        }
    }

    /// Pause recording: stop audio capture and save the audio URL for potential
    /// resume or transcription. Used for the stop-with-undo countdown.
    public func pauseRecording() async {
        guard case .recording = _state else { return }

        let audioURL = try? await audioProcessor.stopCapture()
        pendingCancelledAudioURL = audioURL
        _state = .cancelled
    }

    /// Resume recording after a pause (undo during stop countdown).
    /// Restarts audio capture without resetting elapsed time.
    public func resumeRecording() async throws {
        // Accept both cancelled and idle states after a pause
        guard case .cancelled = _state else {
            logger.warning("resumeRecording rejected state=\(self.debugStateLabel(self._state), privacy: .public)")
            return
        }

        // Discard the paused audio — we're continuing, not transcribing it
        discardPendingCancelledAudio()

        _state = .recording
        do {
            try await audioProcessor.startCapture()
            guard case .recording = _state else {
                let _ = try? await audioProcessor.stopCapture()
                return
            }
            logger.debug("resumeRecording capture restarted")
        } catch {
            _state = .idle
            recordingStartedAt = nil
            logger.error("resumeRecording failed error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Transcribe paused audio (stop countdown expired without undo).
    public func transcribePausedAudio() async throws -> Dictation {
        guard let audioURL = pendingCancelledAudioURL else {
            _state = .idle
            throw DictationServiceError.noPendingCancelledAudio
        }

        pendingCancelledAudioURL = nil
        _state = .processing
        do {
            let dictation = try await processCapturedAudio(audioURL: audioURL)
            _state = .success(dictation)
            try? await Task.sleep(for: .milliseconds(500))
            _state = .idle
            recordingStartedAt = nil
            return dictation
        } catch {
            _state = .idle
            recordingStartedAt = nil
            throw error
        }
    }

    public func reprocessWithSpeakers(dictationID: UUID, onProgress: (@Sendable (ReprocessingProgress) -> Void)? = nil) async throws -> Dictation {
        guard var original = try dictationRepo.fetch(id: dictationID) else {
            throw DictationServiceError.dictationNotFound
        }
        guard let audioPath = original.audioPath, !audioPath.isEmpty else {
            throw DictationServiceError.missingAudioPath
        }

        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw DictationServiceError.audioFileMissing
        }
        guard let diarizationService else {
            throw DictationServiceError.diarizationUnavailable
        }

        // Phase 1: Transcription (0% – 55%)
        onProgress?(ReprocessingProgress(phase: .transcribing, fractionCompleted: 0.0))
        let result = try await sttClient.transcribe(audioPath: audioURL.path) { current, total in
            let frac = total > 0 ? Double(current) / Double(total) : 0.0
            onProgress?(ReprocessingProgress(phase: .transcribing, fractionCompleted: frac * 0.55))
        }
        onProgress?(ReprocessingProgress(phase: .transcribing, fractionCompleted: 0.55))
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DictationServiceError.emptyTranscript
        }

        let words = result.words.map {
            WordTimestamp(
                word: $0.word,
                startMs: $0.startMs,
                endMs: $0.endMs,
                confidence: $0.confidence
            )
        }

        // Phase 2: Speaker diarization (55% – 90%)
        onProgress?(ReprocessingProgress(phase: .analyzingSpeakers, fractionCompleted: 0.55))
        let diarization = try await diarizationService.diarize(audioURL: audioURL)
        onProgress?(ReprocessingProgress(phase: .analyzingSpeakers, fractionCompleted: 0.90))
        let mergedWords = SpeakerMerger.mergeWordTimestampsWithSpeakers(
            words: words,
            segments: diarization.segments
        )

        let mode = original.processingMode
        var customWords: [CustomWord] = []
        var snippets: [TextSnippet] = []
        if mode.usesDeterministicPipeline {
            do { customWords = try customWordRepo?.fetchEnabled() ?? [] }
            catch { logger.error("Failed to fetch custom words: \(error.localizedDescription, privacy: .public)") }
            do { snippets = try snippetRepo?.fetchEnabled() ?? [] }
            catch { logger.error("Failed to fetch snippets: \(error.localizedDescription, privacy: .public)") }
        }

        // Phase 3: Finalizing (90% – 100%)
        onProgress?(ReprocessingProgress(phase: .finalizing, fractionCompleted: 0.90))

        let refinement = await textRefinementService.refine(
            rawText: result.text,
            mode: mode,
            customWords: customWords,
            snippets: snippets
        )

        let finalText = refinement.text ?? result.text

        // Update in-place: enrich the original row with speaker data.
        original.rawTranscript = result.text
        original.cleanTranscript = refinement.text
        original.durationMs = computeDurationMs(from: result)
        original.wordCount = finalText.split(whereSeparator: \.isWhitespace).count
        original.wordTimestamps = mergedWords
        original.speakerCount = diarization.speakerCount
        original.speakers = diarization.speakers
        original.diarizationSegments = diarization.segments.map {
            DiarizationSegmentRecord(speakerId: $0.speakerId, startMs: $0.startMs, endMs: $0.endMs)
        }
        original.updatedAt = Date()

        try dictationRepo.save(original)
        onProgress?(ReprocessingProgress(phase: .finalizing, fractionCompleted: 1.0))

        if !refinement.expandedSnippetIDs.isEmpty {
            try? snippetRepo?.incrementUseCount(ids: refinement.expandedSnippetIDs)
        }

        return original
    }

    // MARK: - Private

    private func discardPendingCancelledAudio() {
        if let url = pendingCancelledAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        pendingCancelledAudioURL = nil
    }

    private func processCapturedAudio(audioURL: URL) async throws -> Dictation {
        var audioConsumed = false
        defer {
            if !audioConsumed {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }

        let result = try await sttClient.transcribe(audioPath: audioURL.path)
        logger.debug("processCapturedAudio transcription complete chars=\(result.text.count)")

        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.warning("processCapturedAudio empty transcript")
            throw DictationServiceError.emptyTranscript
        }

        let mode = processingMode()
        var words: [CustomWord] = []
        var snippets: [TextSnippet] = []
        if mode.usesDeterministicPipeline {
            do { words = try customWordRepo?.fetchEnabled() ?? [] }
            catch { logger.error("Failed to load custom words: \(error.localizedDescription)") }
            do { snippets = try snippetRepo?.fetchEnabled() ?? [] }
            catch { logger.error("Failed to load text snippets: \(error.localizedDescription)") }
        }
        let refinement = await textRefinementService.refine(
            rawText: result.text,
            mode: mode,
            customWords: words,
            snippets: snippets
        )
        let cleanTranscript = refinement.text
        let expandedSnippetIDs = refinement.expandedSnippetIDs

        let finalText = cleanTranscript ?? result.text
        let wc = finalText.split(whereSeparator: \.isWhitespace).count
        let saveHistory = shouldSaveDictationHistory?() ?? true

        var dictation = Dictation(
            durationMs: computeDurationMs(from: result),
            rawTranscript: result.text,
            cleanTranscript: cleanTranscript,
            processingMode: mode,
            status: .completed,
            hidden: !saveHistory,
            wordCount: wc,
            sttModelName: selectedModelName()
        )

        if saveHistory, shouldSaveAudio?() ?? false {
            do { try AppPaths.ensureDirectories() }
            catch { logger.error("Failed to create directories: \(error.localizedDescription, privacy: .public)") }
            let destURL = URL(fileURLWithPath: AppPaths.dictationsDir, isDirectory: true)
                .appendingPathComponent("\(dictation.id.uuidString).wav")

            let fm = FileManager.default
            let sourceExists = fm.fileExists(atPath: audioURL.path)
            logger.debug("save_audio source_exists=\(sourceExists, privacy: .public) src=\(audioURL.path, privacy: .public) dst=\(destURL.path, privacy: .public)")

            if sourceExists {
                do {
                    try fm.moveItem(at: audioURL, to: destURL)
                    dictation.audioPath = destURL.path
                    audioConsumed = true
                } catch {
                    logger.warning("save_audio move_failed error=\(error.localizedDescription, privacy: .public) — trying copy")
                    do {
                        try fm.copyItem(at: audioURL, to: destURL)
                        dictation.audioPath = destURL.path
                        audioConsumed = true
                    } catch {
                        logger.error("save_audio copy_failed error=\(error.localizedDescription, privacy: .public)")
                    }
                }
            } else {
                logger.error("save_audio source_file_missing — cannot persist audio")
            }
        }

        if saveHistory {
            try dictationRepo.save(dictation)
        } else {
            var privateCopy = dictation
            privateCopy.rawTranscript = ""
            privateCopy.cleanTranscript = nil
            try dictationRepo.save(privateCopy)
        }

        if !expandedSnippetIDs.isEmpty {
            try? snippetRepo?.incrementUseCount(ids: refinement.expandedSnippetIDs)
        }

        return dictation
    }

    private func computeDurationMs(from result: STTResult) -> Int {
        if let lastWord = result.words.last {
            return lastWord.endMs
        }
        return result.text.split(separator: " ").count * 150
    }

    private func resetAfterCancelIfStillCurrent(generation: Int) {
        guard generation == cancelGeneration else { return }
        if case .cancelled = _state {
            discardPendingCancelledAudio()
            recordingStartedAt = nil
            _state = .idle
        }
        cancelResetTask = nil
    }

    private func debugStateLabel(_ state: DictationState) -> String {
        switch state {
        case .idle: return "idle"
        case .recording: return "recording"
        case .processing: return "processing"
        case .success: return "success"
        case .cancelled: return "cancelled"
        case .error: return "error"
        }
    }
}

public enum DictationServiceError: Error, LocalizedError {
    case notRecording
    case notCancelled
    case noPendingCancelledAudio
    case emptyTranscript
    case dictationNotFound
    case missingAudioPath
    case audioFileMissing
    case diarizationUnavailable

    public var errorDescription: String? {
        switch self {
        case .notRecording: return "Not currently recording"
        case .notCancelled: return "Not currently in the cancel window"
        case .noPendingCancelledAudio: return "No cancelled recording to process"
        case .emptyTranscript: return "Couldn't hear you — try speaking closer to the microphone."
        case .dictationNotFound: return "Dictation not found"
        case .missingAudioPath: return "No saved audio for this dictation"
        case .audioFileMissing: return "Saved audio file no longer exists"
        case .diarizationUnavailable: return "Speaker analysis is not available"
        }
    }
}
