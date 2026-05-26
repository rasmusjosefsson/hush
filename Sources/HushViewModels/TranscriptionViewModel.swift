import Foundation
import HushCore
import OSLog
import SwiftUI
import AppKit
import UniformTypeIdentifiers

public protocol PasteboardClient: Sendable {
    func write(_ text: String)
}

public protocol SavePanelClient: Sendable {
    func chooseSaveURL(defaultFileName: String, contentType: UTType) -> URL?
}

public struct SystemPasteboardClient: PasteboardClient, Sendable {
    public init() {}

    public func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

public struct SystemSavePanelClient: SavePanelClient, Sendable {
    public init() {}

    public func chooseSaveURL(defaultFileName: String, contentType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFileName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
@Observable
public final class TranscriptionViewModel {
    public enum ProgressPhase: Int, CaseIterable, Sendable {
        case preparing
        case converting
        case transcribing
        case identifyingSpeakers
        case finalizing
    }

    public var transcriptions: [Transcription] = []
    public var currentTranscription: Transcription?
    public var pendingDeleteTranscription: Transcription?
    public var isTranscribing = false
    public var progress: String = ""
    public var transcriptionProgress: Double?
    public private(set) var progressPhase: ProgressPhase = .preparing
    public private(set) var progressHeadline: String = "Preparing transcription pipeline"
    public private(set) var progressSubline: String? = nil
    public var errorMessage: String?
    public private(set) var transcribingFileName: String = ""
    public var isDragging = false
    public var onTranscribingChanged: ((Bool) -> Void)?

    private var transcriptionService: TranscriptionServiceProtocol?
    private var transcriptionRepo: TranscriptionRepositoryProtocol?
    private var exportService: ExportServiceProtocol = ExportService()
    private var pasteboardClient: PasteboardClient = SystemPasteboardClient()
    private var savePanelClient: SavePanelClient = SystemSavePanelClient()
    private var transcriptionTask: Task<Void, Never>?
    private var activeTranscriptionTaskID: UUID?
    private var activeDropRequestID: UUID?
    private var dropPendingCount = 0
    private var dropAccepted = false
    private let logger = Logger(subsystem: "com.hush.viewmodels", category: "TranscriptionViewModel")

    public init() {}

    public func configure(
        transcriptionService: TranscriptionServiceProtocol,
        transcriptionRepo: TranscriptionRepositoryProtocol,
        exportService: ExportServiceProtocol,
        pasteboardClient: PasteboardClient = SystemPasteboardClient(),
        savePanelClient: SavePanelClient = SystemSavePanelClient()
    ) {
        self.transcriptionService = transcriptionService
        self.transcriptionRepo = transcriptionRepo
        self.exportService = exportService
        self.pasteboardClient = pasteboardClient
        self.savePanelClient = savePanelClient
        loadTranscriptions()
    }

    public func configure(
        transcriptionService: TranscriptionServiceProtocol,
        transcriptionRepo: TranscriptionRepositoryProtocol
    ) {
        configure(
            transcriptionService: transcriptionService,
            transcriptionRepo: transcriptionRepo,
            exportService: ExportService()
        )
    }

    public func copyToClipboard(_ transcription: Transcription) {
        let text = exportService.formatForClipboard(transcription: transcription)
        pasteboardClient.write(text)
    }

    public func downloadTranscriptionAsTxt(_ transcription: Transcription) {
        saveTranscription(transcription, contentType: .plainText, fileExtension: "txt") { exportService, url in
            try exportService.exportToTxt(transcription: transcription, url: url)
        }
    }

    public func downloadTranscriptionAsMarkdown(_ transcription: Transcription) {
        let markdownType = UTType(filenameExtension: "md") ?? .plainText
        saveTranscription(transcription, contentType: markdownType, fileExtension: "md") { exportService, url in
            try exportService.exportToMarkdown(transcription: transcription, url: url)
        }
    }

    public func loadTranscriptions() {
        guard let repo = transcriptionRepo else { return }
        do {
            transcriptions = try repo.fetchAll(limit: 50)
        } catch {
            logger.error("Failed to load transcriptions: \(error.localizedDescription, privacy: .public)")
            transcriptions = []
        }
    }

    public func transcribeFile(url: URL, source: TranscriptionSource = .file) {
        guard let service = transcriptionService else { return }
        let taskID = beginNewTranscription(fileName: url.lastPathComponent)

        transcriptionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await service.transcribe(fileURL: url, source: source) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.updateProgress(with: progress, taskID: taskID)
                    }
                }
                completeSuccessfulTranscription(taskID: taskID, result: result)
            } catch is CancellationError {
                completeCancelledTranscription(taskID: taskID)
            } catch {
                completeFailedTranscription(taskID: taskID, error: error)
            }
        }
    }

    public func handleFileDrop(
        providers: [NSItemProvider],
        onAccepted: (() -> Void)? = nil
    ) -> Bool {
        guard !isTranscribing else { return false }
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
        guard !fileProviders.isEmpty else { return false }

        let requestID = UUID()
        activeDropRequestID = requestID
        dropPendingCount = fileProviders.count
        dropAccepted = false

        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                let droppedURL: URL?
                if let data = item as? Data {
                    droppedURL = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    droppedURL = nil
                }

                Task { @MainActor in
                    guard self.activeDropRequestID == requestID else { return }
                    defer {
                        self.dropPendingCount -= 1
                        if self.dropPendingCount == 0 {
                            if !self.dropAccepted {
                                self.errorMessage = self.unsupportedDropMessage
                            }
                            self.activeDropRequestID = nil
                        }
                    }

                    guard let droppedURL else { return }
                    let ext = droppedURL.pathExtension.lowercased()
                    guard AudioFileConverter.supportedExtensions.contains(ext) else { return }
                    guard !self.dropAccepted, !self.isTranscribing else { return }

                    self.dropAccepted = true
                    self.errorMessage = nil
                    onAccepted?()
                    self.transcribeFile(url: droppedURL, source: .dragDrop)
                }
            }
        }
        return true
    }

    private var unsupportedDropMessage: String {
        let formats = AudioFileConverter.supportedExtensions
            .sorted()
            .map { $0.uppercased() }
            .joined(separator: ", ")
        return "Unsupported file type. Supported formats: \(formats)."
    }

    public func retranscribe(_ original: Transcription) {
        guard let service = transcriptionService,
              let filePath = original.filePath,
              FileManager.default.fileExists(atPath: filePath) else { return }

        let url = URL(fileURLWithPath: filePath)
        let originalID = original.id
        let taskID = beginNewTranscription(fileName: original.fileName, clearCurrent: true)

        transcriptionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var result = try await service.transcribe(fileURL: url, source: .file) { [weak self] phase in
                    Task { @MainActor [weak self] in
                        self?.updateProgress(with: phase, taskID: taskID)
                    }
                }
                result.fileName = original.fileName
                result.sourceURL = original.sourceURL
                do {
                    try transcriptionRepo?.save(result)
                    _ = try? transcriptionRepo?.delete(id: originalID)
                } catch {
                    logger.error("Failed to save transcription result error=\(error.localizedDescription, privacy: .public)")
                }
                completeSuccessfulTranscription(taskID: taskID, result: result)
            } catch is CancellationError {
                completeCancelledTranscription(taskID: taskID)
            } catch {
                completeFailedTranscription(taskID: taskID, error: error)
            }
        }
    }

    public func cancelTranscription() {
        transcriptionTask?.cancel()
    }

    public func confirmDelete() {
        guard let transcription = pendingDeleteTranscription else { return }
        pendingDeleteTranscription = nil
        deleteTranscription(transcription)
    }

    public func deleteTranscription(_ transcription: Transcription) {
        guard let repo = transcriptionRepo else { return }
        if let audioPath = transcription.filePath {
            try? FileManager.default.removeItem(atPath: audioPath)
        }
        do { _ = try repo.delete(id: transcription.id) }
        catch { logger.error("Failed to delete transcription: \(error.localizedDescription, privacy: .public)") }
        if currentTranscription?.id == transcription.id {
            currentTranscription = nil
        }
        loadTranscriptions()
    }

    // MARK: - Progress State

    private func beginNewTranscription(fileName: String, clearCurrent: Bool = false) -> UUID {
        transcriptionTask?.cancel()

        let taskID = UUID()
        activeTranscriptionTaskID = taskID
        transcribingFileName = fileName
        isTranscribing = true
        onTranscribingChanged?(true)
        progress = "Preparing..."
        transcriptionProgress = nil
        progressPhase = .preparing
        progressHeadline = Self.headline(for: .preparing)
        progressSubline = nil
        errorMessage = nil

        if clearCurrent {
            currentTranscription = nil
        }

        return taskID
    }

    private func completeSuccessfulTranscription(taskID: UUID, result: Transcription) {
        guard activeTranscriptionTaskID == taskID else { return }
        transcriptionTask = nil
        activeTranscriptionTaskID = nil
        endTranscription()
        currentTranscription = result
        loadTranscriptions()
    }

    private func completeFailedTranscription(taskID: UUID, error: Error) {
        guard activeTranscriptionTaskID == taskID else { return }
        transcriptionTask = nil
        activeTranscriptionTaskID = nil
        errorMessage = error.localizedDescription
        endTranscription()
        loadTranscriptions()
    }

    private func completeCancelledTranscription(taskID: UUID) {
        guard activeTranscriptionTaskID == taskID else { return }
        transcriptionTask = nil
        activeTranscriptionTaskID = nil
        errorMessage = nil
        endTranscription()
        loadTranscriptions()
    }

    private func saveTranscription(
        _ transcription: Transcription,
        contentType: UTType,
        fileExtension: String,
        exporter: (ExportServiceProtocol, URL) throws -> Void
    ) {
        let stem = TranscriptSegmenter.sanitizedExportStem(from: transcription.fileName)
        let defaultFileName = "\(stem).\(fileExtension)"
        guard let selectedURL = savePanelClient.chooseSaveURL(defaultFileName: defaultFileName, contentType: contentType) else {
            return
        }

        let destinationURL = normalizedExportURL(selectedURL, requiredExtension: fileExtension)
        do {
            try exporter(exportService, destinationURL)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save transcript: \(error.localizedDescription)"
        }
    }

    private func normalizedExportURL(_ url: URL, requiredExtension: String) -> URL {
        let current = url.pathExtension.lowercased()
        let required = requiredExtension.lowercased()
        if current == required {
            return url
        }
        if current.isEmpty {
            return url.appendingPathExtension(required)
        }
        return url.deletingPathExtension().appendingPathExtension(required)
    }

    private func endTranscription() {
        isTranscribing = false
        onTranscribingChanged?(false)
        progress = ""
        transcriptionProgress = nil
        transcribingFileName = ""
        progressPhase = .preparing
        progressHeadline = Self.headline(for: .preparing)
        progressSubline = nil
    }

    private func updateProgress(with progress: TranscriptionProgress, taskID: UUID? = nil) {
        if let taskID, activeTranscriptionTaskID != taskID { return }
        let phase = Self.mapPhase(from: progress)
        self.progress = Self.displayText(for: progress)
        self.transcriptionProgress = progress.fraction
        self.progressPhase = phase
        self.progressHeadline = Self.headline(for: phase)
        self.progressSubline = Self.subline(for: phase)
    }

    private static func mapPhase(from progress: TranscriptionProgress) -> ProgressPhase {
        switch progress {
        case .converting: return .converting
        case .downloading: return .converting
        case .transcribing: return .transcribing
        case .identifyingSpeakers: return .identifyingSpeakers
        case .finalizing: return .finalizing
        }
    }

    private static func displayText(for progress: TranscriptionProgress) -> String {
        switch progress {
        case .converting: return "Converting audio..."
        case .downloading(let percent): return "Downloading... \(percent)%"
        case .transcribing(let percent): return "Transcribing... \(percent)%"
        case .identifyingSpeakers: return "Identifying speakers..."
        case .finalizing: return "Finalizing..."
        }
    }

    private static func headline(for phase: ProgressPhase) -> String {
        switch phase {
        case .preparing: return "Preparing transcription pipeline"
        case .converting: return "Normalizing audio stream"
        case .transcribing: return "Running speech recognition"
        case .identifyingSpeakers: return "Identifying speakers"
        case .finalizing: return "Finalizing transcript"
        }
    }

    private static func subline(for phase: ProgressPhase) -> String? {
        switch phase {
        case .transcribing: return "Runs entirely on-device using the Neural Engine"
        case .identifyingSpeakers: return "Adds ~30–60s per hour of audio"
        default: return nil
        }
    }

    // MARK: - Speaker Rename

    public func renameSpeaker(id speakerId: String, to newLabel: String) {
        guard var transcription = currentTranscription,
              var speakers = transcription.speakers else { return }
        guard let index = speakers.firstIndex(where: { $0.id == speakerId }) else { return }
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, speakers[index].label != trimmed else { return }
        speakers[index].label = trimmed
        transcription.speakers = speakers
        currentTranscription = transcription
        do {
            try transcriptionRepo?.updateSpeakers(id: transcription.id, speakers: speakers)
        } catch {
            logger.error("Failed to persist speaker rename error=\(error.localizedDescription, privacy: .public)")
        }
    }
}
