import AppKit
import AVFoundation
import Foundation
import HushCore
import os
import UniformTypeIdentifiers

@MainActor
@Observable
public final class DictationHistoryViewModel {
    private let logger = Logger(subsystem: "com.hush.viewmodels", category: "DictationHistory")
    public var groupedDictations: [(String, [Dictation])] = []
    public var searchText: String = "" {
        didSet { debounceSearch() }
    }
    private var searchDebounceTask: Task<Void, Never>?

    // MARK: - Playback State

    public var isPlaying: Bool = false
    public var playingDictationId: UUID?
    public var playbackCurrentTime: TimeInterval = 0
    public var playbackDuration: TimeInterval = 0

    public var playbackProgress: Double {
        guard playbackDuration > 0 else { return 0 }
        return playbackCurrentTime / playbackDuration
    }

    public var playbackTimeString: String {
        let currentMs = Int(playbackCurrentTime * 1000)
        let durationMs = Int(playbackDuration * 1000)
        return "\(currentMs.formattedDuration) / \(durationMs.formattedDuration)"
    }

    public var playingDictation: Dictation? {
        guard let id = playingDictationId else { return nil }
        return groupedDictations.flatMap(\.1).first { $0.id == id }
    }

    // MARK: - Stats

    public var stats: DictationStats = .empty

    // MARK: - Copy Confirmation

    public var copiedDictationId: UUID?
    private var copiedResetTask: Task<Void, Never>?

    // MARK: - Playback Error

    public var playbackError: String?
    private var playbackErrorResetTask: Task<Void, Never>?

    // MARK: - Delete Confirmation

    public var pendingDeleteDictation: Dictation?
    public var processingDictationIDs: Set<UUID> = []
    public var processingProgress: [UUID: ReprocessingProgress] = [:]
    public var processingError: String?

    public func confirmDelete() {
        guard let dictation = pendingDeleteDictation else { return }
        pendingDeleteDictation = nil
        deleteDictation(dictation)
    }

    private var dictationRepo: DictationRepositoryProtocol?
    private var dictationService: DictationServiceProtocol?
    private var exportService: ExportServiceProtocol = ExportService()
    private var savePanelClient: SavePanelClient = SystemSavePanelClient()
    private var audioPlayer: AVAudioPlayer?
    private var playbackDelegate: PlaybackDelegate?
    private var playbackTimerTask: Task<Void, Never>?

    public init() {}

    public func configure(
        dictationRepo: DictationRepositoryProtocol,
        dictationService: DictationServiceProtocol,
        exportService: ExportServiceProtocol,
        savePanelClient: SavePanelClient = SystemSavePanelClient()
    ) {
        self.dictationRepo = dictationRepo
        self.dictationService = dictationService
        self.exportService = exportService
        self.savePanelClient = savePanelClient
        loadDictations()
    }

    public func configure(
        dictationRepo: DictationRepositoryProtocol,
        exportService: ExportServiceProtocol,
        savePanelClient: SavePanelClient = SystemSavePanelClient()
    ) {
        self.dictationRepo = dictationRepo
        self.exportService = exportService
        self.savePanelClient = savePanelClient
        loadDictations()
    }

    public func configure(dictationRepo: DictationRepositoryProtocol) {
        configure(dictationRepo: dictationRepo, exportService: ExportService())
    }

    public func reprocessWithSpeakers(_ dictation: Dictation) {
        guard let dictationService else { return }
        guard !processingDictationIDs.contains(dictation.id) else { return }

        processingError = nil
        processingDictationIDs.insert(dictation.id)
        processingProgress[dictation.id] = ReprocessingProgress(phase: .transcribing, fractionCompleted: 0.0)

        Task {
            defer {
                processingDictationIDs.remove(dictation.id)
                processingProgress.removeValue(forKey: dictation.id)
            }

            do {
                let id = dictation.id
                _ = try await dictationService.reprocessWithSpeakers(dictationID: dictation.id) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.processingProgress[id] = progress
                    }
                }
                loadDictations()
            } catch {
                processingError = error.localizedDescription
            }
        }
    }

    public func loadDictations(shouldRefreshStats: Bool = true) {
        guard let repo = dictationRepo else { return }

        let dictations: [Dictation]
        do {
            if searchText.isEmpty {
                dictations = try repo.fetchAll(limit: 200)
            } else {
                dictations = try repo.search(query: searchText, limit: 200)
            }
        } catch {
            logger.error("Failed to load dictations: \(error.localizedDescription)")
            dictations = []
        }

        // Group by date
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: dictations) { dictation in
            calendar.startOfDay(for: dictation.createdAt)
        }

        groupedDictations = grouped.sorted { $0.key > $1.key }.map { (key, value) in
            (formatDateHeader(key), value.sorted { $0.createdAt > $1.createdAt })
        }

        if shouldRefreshStats {
            refreshStats()
        }
    }

    public func deleteDictation(_ dictation: Dictation) {
        guard let repo = dictationRepo else { return }
        if playingDictationId == dictation.id {
            stopPlayback()
        }

        do {
            let deleted = try repo.delete(id: dictation.id)
            if deleted, let path = dictation.audioPath {
                let remainingRefs = try repo.countByAudioPath(path)
                if remainingRefs == 0 {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
        } catch {
            logger.error("Failed to delete dictation \(dictation.id): \(error.localizedDescription)")
        }
        loadDictations()
    }

    private func refreshStats() {
        guard let repo = dictationRepo else { return }
        do {
            stats = try repo.stats()
        } catch {
            logger.error("Failed to load dictation stats: \(error.localizedDescription)")
            stats = .empty
        }
    }

    public func downloadAudio(for dictation: Dictation) {
        guard let audioPath = dictation.audioPath,
              FileManager.default.fileExists(atPath: audioPath) else { return }
        let sourceURL = URL(fileURLWithPath: audioPath)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.copyItem(at: sourceURL, to: destination)
    }

    public func revealInFinder() {
        let dirPath = AppPaths.dictationsDir
        let url = URL(fileURLWithPath: dirPath, isDirectory: true)
        try? AppPaths.ensureDirectories()
        NSWorkspace.shared.open(url)
    }

    public func exportTranscriptAsMarkdown(for dictation: Dictation) {
        let transcription = transcriptionForExport(from: dictation)
        let markdownType = UTType(filenameExtension: "md") ?? .plainText
        saveTranscription(transcription, contentType: markdownType, fileExtension: "md") { exportService, url in
            try exportService.exportToMarkdown(transcription: transcription, url: url)
        }
    }

    public func exportTranscriptAsTxt(for dictation: Dictation) {
        let transcription = transcriptionForExport(from: dictation)
        saveTranscription(transcription, contentType: .plainText, fileExtension: "txt") { exportService, url in
            try exportService.exportToTxt(transcription: transcription, url: url)
        }
    }

    public func copyToClipboard(_ dictation: Dictation) {
        let text = formattedClipboardText(for: dictation)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        copiedResetTask?.cancel()
        copiedDictationId = dictation.id
        copiedResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self.copiedDictationId = nil
        }
    }

    func formattedClipboardText(for dictation: Dictation) -> String {
        let base = (dictation.cleanTranscript ?? dictation.rawTranscript)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !base.isEmpty else { return "" }
        guard !base.contains("\n") else { return base }

        return base.replacingOccurrences(
            of: #"(?<=[.!?])\s+"#,
            with: "\n",
            options: .regularExpression
        )
    }

    // MARK: - Playback

    public func togglePlayback(for dictation: Dictation) {
        guard let audioPath = dictation.audioPath else { return }

        // If already playing this dictation, pause
        if playingDictationId == dictation.id, isPlaying {
            pausePlayback()
            return
        }

        // If paused on the same dictation, resume
        if playingDictationId == dictation.id, !isPlaying, audioPlayer != nil {
            audioPlayer?.play()
            isPlaying = true
            startPlaybackTimer()
            return
        }

        // Stop any current playback and start new
        stopPlayback()

        let url = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            showPlaybackError("Audio file no longer exists")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = PlaybackDelegate { [weak self] in
                Task { @MainActor in
                    self?.stopPlayback()
                }
            }
            player.delegate = delegate
            player.play()

            audioPlayer = player
            playbackDelegate = delegate
            playingDictationId = dictation.id
            isPlaying = true
            playbackDuration = player.duration
            playbackCurrentTime = 0
            startPlaybackTimer()
        } catch {
            showPlaybackError("Unable to play audio")
        }
    }

    public func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        playbackTimerTask?.cancel()
        playbackTimerTask = nil
    }

    public func stopPlayback() {
        playbackTimerTask?.cancel()
        playbackTimerTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        playbackDelegate = nil
        isPlaying = false
        playingDictationId = nil
        playbackCurrentTime = 0
        playbackDuration = 0
    }

    // MARK: - Private

    private func debounceSearch() {
        searchDebounceTask?.cancel()
        if searchText.isEmpty {
            // Clear immediately so the full list restores without lag
            loadDictations(shouldRefreshStats: false)
            return
        }
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            loadDictations(shouldRefreshStats: false)
        }
    }

    private func showPlaybackError(_ message: String) {
        playbackErrorResetTask?.cancel()
        playbackError = message
        playbackErrorResetTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.playbackError = nil
        }
    }

    private func startPlaybackTimer() {
        playbackTimerTask?.cancel()
        playbackTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { break }
                guard let self, let player = self.audioPlayer else { break }
                self.playbackCurrentTime = player.currentTime
            }
        }
    }

    private func transcriptionForExport(from dictation: Dictation) -> Transcription {
        let fallbackStamp = ISO8601DateFormatter().string(from: dictation.createdAt)
        let fileName = dictation.audioPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "dictation-\(fallbackStamp).txt"

        return Transcription(
            fileName: fileName,
            durationMs: dictation.durationMs,
            rawTranscript: dictation.rawTranscript,
            cleanTranscript: dictation.cleanTranscript,
            wordTimestamps: dictation.wordTimestamps,
            speakerCount: dictation.speakerCount,
            speakers: dictation.speakers,
            diarizationSegments: dictation.diarizationSegments,
            status: .completed
        )
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
        } catch {
            logger.error("Failed to save dictation transcript: \(error.localizedDescription)")
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

    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

// MARK: - PlaybackDelegate

@MainActor
private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: @MainActor () -> Void

    init(onFinish: @escaping @MainActor () -> Void) {
        self.onFinish = onFinish
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.onFinish()
        }
    }
}
