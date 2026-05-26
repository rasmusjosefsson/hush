import Foundation
import OSLog

public enum TranscriptionSource: String, Sendable, Equatable {
    case file
    case dragDrop = "drag_drop"
}

public protocol TranscriptionServiceProtocol: Sendable {
    func transcribe(
        fileURL: URL,
        source: TranscriptionSource,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription

    func transcribeMeeting(
        recording: MeetingRecordingOutput,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription
}

extension TranscriptionServiceProtocol {
    public func transcribe(fileURL: URL) async throws -> Transcription {
        try await transcribe(fileURL: fileURL, source: .file, onProgress: nil)
    }

    public func transcribe(
        fileURL: URL,
        source: TranscriptionSource
    ) async throws -> Transcription {
        try await transcribe(fileURL: fileURL, source: source, onProgress: nil)
    }
}

public actor TranscriptionService: TranscriptionServiceProtocol {
    private let logger = Logger(subsystem: "com.hush.core", category: "TranscriptionService")
    private let audioProcessor: AudioProcessorProtocol
    private let sttClient: STTClientProtocol
    private let transcriptionRepo: TranscriptionRepositoryProtocol
    private let customWordRepo: CustomWordRepositoryProtocol?
    private let snippetRepo: TextSnippetRepositoryProtocol?
    private let processingMode: @Sendable () -> Dictation.ProcessingMode
    private let textRefinementService: TextRefinementService
    private let diarizationService: DiarizationServiceProtocol?

    public init(
        audioProcessor: AudioProcessorProtocol,
        sttClient: STTClientProtocol,
        transcriptionRepo: TranscriptionRepositoryProtocol,
        customWordRepo: CustomWordRepositoryProtocol? = nil,
        snippetRepo: TextSnippetRepositoryProtocol? = nil,
        processingMode: (@Sendable () -> Dictation.ProcessingMode)? = nil,
        diarizationService: DiarizationServiceProtocol? = nil
    ) {
        self.audioProcessor = audioProcessor
        self.sttClient = sttClient
        self.transcriptionRepo = transcriptionRepo
        self.customWordRepo = customWordRepo
        self.snippetRepo = snippetRepo
        self.processingMode = processingMode ?? { .raw }
        self.textRefinementService = TextRefinementService()
        self.diarizationService = diarizationService
    }

    public func transcribe(
        fileURL: URL,
        source: TranscriptionSource = .file,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)? = nil
    ) async throws -> Transcription {
        let fileName = fileURL.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int).flatMap { $0 }

        var transcription = Transcription(
            fileName: fileName,
            filePath: fileURL.path,
            fileSizeBytes: fileSize,
            status: .processing
        )
        try transcriptionRepo.save(transcription)

        var wavURL: URL?
        do {
            onProgress?(.converting)
            wavURL = try await audioProcessor.convert(fileURL: fileURL)

            guard let wavURL else {
                throw AudioProcessorError.conversionFailed("Failed to produce WAV output")
            }

            onProgress?(.transcribing(percent: 0))
            let sttProgress: (@Sendable (Int, Int) -> Void)? = onProgress.map { callback in
                { @Sendable current, total in
                    let pct = total > 0 ? Int(Double(current) / Double(total) * 100) : 0
                    callback(.transcribing(percent: min(pct, 99)))
                }
            }
            let result = try await sttClient.transcribe(audioPath: wavURL.path, onProgress: sttProgress)

            let words = result.words.map { word in
                WordTimestamp(
                    word: word.word,
                    startMs: word.startMs,
                    endMs: word.endMs,
                    confidence: word.confidence
                )
            }

            transcription.rawTranscript = result.text
            transcription.wordTimestamps = words
            transcription.durationMs = result.words.last?.endMs

            if let diarizationService {
                do {
                    onProgress?(.identifyingSpeakers)
                    let diarResult = try await diarizationService.diarize(audioURL: wavURL)
                    if !diarResult.segments.isEmpty {
                        let mergedWords = SpeakerMerger.mergeWordTimestampsWithSpeakers(
                            words: words,
                            segments: diarResult.segments
                        )
                        transcription.wordTimestamps = mergedWords
                        transcription.speakerCount = diarResult.speakerCount
                        transcription.speakers = diarResult.speakers
                        transcription.diarizationSegments = diarResult.segments.map {
                            DiarizationSegmentRecord(speakerId: $0.speakerId, startMs: $0.startMs, endMs: $0.endMs)
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    logger.error("diarization_failed error=\(error.localizedDescription, privacy: .public)")
                }
            }

            let mode = processingMode()
            var customWords: [CustomWord] = []
            var snippets: [TextSnippet] = []
            if mode.usesDeterministicPipeline {
                do { customWords = try customWordRepo?.fetchEnabled() ?? [] }
                catch { logger.error("Failed to fetch custom words: \(error.localizedDescription, privacy: .public)") }
                do { snippets = try snippetRepo?.fetchEnabled() ?? [] }
                catch { logger.error("Failed to fetch snippets: \(error.localizedDescription, privacy: .public)") }
            }
            let refinement = await textRefinementService.refine(
                rawText: result.text,
                mode: mode,
                customWords: customWords,
                snippets: snippets
            )
            transcription.cleanTranscript = refinement.text

            if !refinement.expandedSnippetIDs.isEmpty {
                try? snippetRepo?.incrementUseCount(ids: refinement.expandedSnippetIDs)
            }

            transcription.status = .completed
            transcription.updatedAt = Date()
            try transcriptionRepo.save(transcription)
            FileLogger.shared.log("Transcription completed: \(fileName)", level: .info, category: .recording)
        FileLogger.shared.log("Transcription started: \(fileName)", level: .info, category: .recording)

            try? FileManager.default.removeItem(at: wavURL)
            return transcription
        } catch {
            if let wavURL { try? FileManager.default.removeItem(at: wavURL) }
            FileLogger.shared.log("Transcription failed: \(fileName) -- \(error.localizedDescription)", level: .error, category: .recording)

            let txID = transcription.id
            if error is CancellationError {
                do {
                    try transcriptionRepo.updateStatus(id: txID, status: .cancelled, errorMessage: nil)
                } catch let dbError {
                    logger.error("failed_to_update_cancelled_status id=\(txID) dbError=\(dbError.localizedDescription, privacy: .public)")
                }
            } else {
                do {
                    try transcriptionRepo.updateStatus(id: txID, status: .error, errorMessage: error.localizedDescription)
                } catch let dbError {
                    logger.error("failed_to_update_error_status id=\(txID) dbError=\(dbError.localizedDescription, privacy: .public)")
                }
            }
            throw error
        }
    }

    public func transcribeMeeting(
        recording: MeetingRecordingOutput,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription {
        let mixedURL = recording.mixedAudioURL
        let result = try await sttClient.transcribe(audioPath: mixedURL.path, job: .meetingFinalize, onProgress: { current, total in
            onProgress?(.transcribing(percent: total > 0 ? (current * 100) / total : 0))
        })

        let transcription = Transcription(
            fileName: "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))",
            filePath: mixedURL.path,
            durationMs: Int(recording.durationSeconds * 1000),
            rawTranscript: result.text,
            wordTimestamps: result.words.map { WordTimestamp(word: $0.word, startMs: $0.startMs, endMs: $0.endMs, confidence: $0.confidence) },
            status: .completed,
            sourceType: .meeting
        )

        try transcriptionRepo.save(transcription)
        return transcription
    }
}
