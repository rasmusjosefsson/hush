import Foundation
@testable import HushCore
@testable import HushViewModels
import UniformTypeIdentifiers

// MARK: - MockDictationRepository

final class MockDictationRepository: DictationRepositoryProtocol, @unchecked Sendable {
    var dictations: [Dictation] = []
    var deleteCalledWith: [UUID] = []
    var deleteAllCalled = false
    var deleteHiddenCalled = false
    var savedDictations: [Dictation] = []
    var fetchAllCallCount = 0
    var statsCallCount = 0

    func save(_ dictation: Dictation) throws {
        savedDictations.append(dictation)
        // Also insert/update in the working list
        if let idx = dictations.firstIndex(where: { $0.id == dictation.id }) {
            dictations[idx] = dictation
        } else {
            dictations.append(dictation)
        }
    }

    func fetch(id: UUID) throws -> Dictation? {
        dictations.first(where: { $0.id == id })
    }

    func fetchAll(limit: Int?) throws -> [Dictation] {
        fetchAllCallCount += 1
        let sorted = dictations.filter { !$0.hidden }.sorted { $0.createdAt > $1.createdAt }
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }

    func search(query: String, limit: Int?) throws -> [Dictation] {
        let filtered = dictations.filter {
            !$0.hidden && (
                $0.rawTranscript.localizedCaseInsensitiveContains(query)
                || ($0.cleanTranscript?.localizedCaseInsensitiveContains(query) ?? false)
            )
        }
        let sorted = filtered.sorted { $0.createdAt > $1.createdAt }
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }

    func delete(id: UUID) throws -> Bool {
        deleteCalledWith.append(id)
        dictations.removeAll { $0.id == id }
        return true
    }

    func countByAudioPath(_ path: String) throws -> Int {
        dictations.filter { $0.audioPath == path }.count
    }

    func deleteAll() throws {
        deleteAllCalled = true
        dictations.removeAll { !$0.hidden }
    }

    func clearMissingAudioPaths() throws {
        // No-op in mock
    }

    func deleteEmpty() throws -> Int {
        let before = dictations.count
        dictations.removeAll {
            !$0.hidden && $0.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return before - dictations.count
    }

    func deleteHidden() throws {
        deleteHiddenCalled = true
        dictations.removeAll { $0.hidden }
    }

    func stats() throws -> DictationStats {
        statsCallCount += 1
        let completed = dictations.filter { $0.status == .completed }
        let totalDuration = completed.reduce(0) { $0 + $1.durationMs }
        let totalWords = completed.reduce(0) { $0 + $1.wordCount }
        let maxDuration = completed.map(\.durationMs).max() ?? 0
        let avgDuration = completed.isEmpty ? 0 : totalDuration / completed.count

        let dates = completed.map(\.createdAt)
        let (streak, thisWeek) = DictationRepository.computeWeeklyStreak(from: dates)

        let visible = completed.filter { !$0.hidden }
        return DictationStats(
            totalCount: completed.count,
            visibleCount: visible.count,
            totalDurationMs: totalDuration,
            totalWords: totalWords,
            longestDurationMs: maxDuration,
            averageDurationMs: avgDuration,
            weeklyStreak: streak,
            dictationsThisWeek: thisWeek
        )
    }
}

// MARK: - MockTranscriptionRepository

final class MockTranscriptionRepository: TranscriptionRepositoryProtocol, @unchecked Sendable {
    var transcriptions: [Transcription] = []
    var deleteCalledWith: [UUID] = []
    var deleteAllCalled = false
    var updateSummaryCalls: [(id: UUID, summary: String?)] = []
    var updateChatMessagesCalls: [(id: UUID, chatMessages: [ChatMessage]?)] = []
    var updateSpeakersCalls: [(id: UUID, speakers: [SpeakerInfo]?)] = []

    func save(_ transcription: Transcription) throws {
        if let idx = transcriptions.firstIndex(where: { $0.id == transcription.id }) {
            transcriptions[idx] = transcription
        } else {
            transcriptions.append(transcription)
        }
    }

    func fetch(id: UUID) throws -> Transcription? {
        transcriptions.first(where: { $0.id == id })
    }

    func fetchAll(limit: Int?) throws -> [Transcription] {
        let sorted = transcriptions.sorted { $0.createdAt > $1.createdAt }
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }

    func fetchCompletedByVideoID(_ videoID: String) throws -> Transcription? {
        transcriptions.first { t in
            t.status == .completed
                && t.sourceURL != nil
                && (t.sourceURL?.contains(videoID) ?? false)
        }
    }

    func delete(id: UUID) throws -> Bool {
        deleteCalledWith.append(id)
        transcriptions.removeAll { $0.id == id }
        return true
    }

    func deleteAll() throws {
        deleteAllCalled = true
        transcriptions.removeAll()
    }

    func updateStatus(id: UUID, status: Transcription.TranscriptionStatus, errorMessage: String?) throws {
        if let idx = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[idx].status = status
            transcriptions[idx].errorMessage = errorMessage
        }
    }

    func updateSummary(id: UUID, summary: String?) throws {
        updateSummaryCalls.append((id: id, summary: summary))
        if let idx = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[idx].summary = summary
            transcriptions[idx].updatedAt = Date()
        }
    }

    func updateChatMessages(id: UUID, chatMessages: [ChatMessage]?) throws {
        updateChatMessagesCalls.append((id: id, chatMessages: chatMessages))
        if let idx = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[idx].chatMessages = chatMessages
            transcriptions[idx].updatedAt = Date()
        }
    }

    func updateSpeakers(id: UUID, speakers: [SpeakerInfo]?) throws {
        updateSpeakersCalls.append((id: id, speakers: speakers))
        if let idx = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[idx].speakers = speakers
            transcriptions[idx].updatedAt = Date()
        }
    }

    func clearStoredAudioPathsForURLTranscriptions() throws {
        for i in transcriptions.indices {
            if transcriptions[i].sourceURL != nil {
                transcriptions[i].filePath = nil
            }
        }
    }

    func updateFavorite(id: UUID, isFavorite: Bool) throws {
        if let idx = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[idx].isFavorite = isFavorite
            transcriptions[idx].updatedAt = Date()
        }
    }

    func fetchFavorites() throws -> [Transcription] {
        transcriptions.filter(\.isFavorite).sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - MockLaunchAtLoginService

final class MockLaunchAtLoginService: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus
    var setEnabledCalls: [Bool] = []
    var errorToThrow: Error?

    init(status: LaunchAtLoginStatus = .disabled, errorToThrow: Error? = nil) {
        self.status = status
        self.errorToThrow = errorToThrow
    }

    func currentStatus() -> LaunchAtLoginStatus {
        status
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        setEnabledCalls.append(enabled)
        if let errorToThrow {
            throw errorToThrow
        }
        status = enabled ? .enabled : .disabled
        return status
    }
}

// MARK: - MockTranscriptionService

actor MockTranscriptionService: TranscriptionServiceProtocol {
    var transcribeResult: Transcription?
    var transcribeError: Error?
    var transcribeCallCount = 0
    var lastFileURL: URL?
    var lastSource: TranscriptionSource?
    var transcribeProgressPhases: [TranscriptionProgress] = []
    var transcribeDelayMs: UInt64 = 0

    func configure(result: Transcription) {
        self.transcribeResult = result
        self.transcribeError = nil
    }

    func configure(error: Error) {
        self.transcribeError = error
        self.transcribeResult = nil
    }

    func configureProgress(phases: [TranscriptionProgress]) {
        self.transcribeProgressPhases = phases
    }

    func configureDelay(milliseconds: UInt64) {
        self.transcribeDelayMs = milliseconds
    }

    func transcribe(
        fileURL: URL,
        source: TranscriptionSource,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)? = nil
    ) async throws -> Transcription {
        transcribeCallCount += 1
        lastFileURL = fileURL
        lastSource = source

        for phase in transcribeProgressPhases {
            onProgress?(phase)
        }

        if transcribeDelayMs > 0 {
            try await Task.sleep(nanoseconds: transcribeDelayMs * 1_000_000)
        }

        if let error = transcribeError {
            throw error
        }

        return transcribeResult ?? Transcription(
            fileName: fileURL.lastPathComponent,
            rawTranscript: "Mock transcription",
            status: .completed
        )
    }

    func transcribeMeeting(
        recording: MeetingRecordingOutput,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription {
        // Not exercised by current view-model tests; return a stub.
        if let error = transcribeError {
            throw error
        }
        return transcribeResult ?? Transcription(
            fileName: "meeting",
            rawTranscript: "Mock meeting transcription",
            status: .completed
        )
    }
}

// MARK: - MockCustomWordRepository

final class MockCustomWordRepository: CustomWordRepositoryProtocol, @unchecked Sendable {
    var words: [CustomWord] = []

    func save(_ word: CustomWord) throws {
        if let idx = words.firstIndex(where: { $0.id == word.id }) {
            words[idx] = word
        } else {
            words.append(word)
        }
    }

    func fetch(id: UUID) throws -> CustomWord? {
        words.first(where: { $0.id == id })
    }

    func fetchAll() throws -> [CustomWord] {
        words.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    func fetchEnabled() throws -> [CustomWord] {
        words.filter { $0.isEnabled }
            .sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    func delete(id: UUID) throws -> Bool {
        let before = words.count
        words.removeAll { $0.id == id }
        return words.count < before
    }

    func deleteAll() throws {
        words.removeAll()
    }
}

// MARK: - MockTextSnippetRepository

final class MockTextSnippetRepository: TextSnippetRepositoryProtocol, @unchecked Sendable {
    var snippets: [TextSnippet] = []
    var incrementedIDs: [Set<UUID>] = []

    func save(_ snippet: TextSnippet) throws {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx] = snippet
        } else {
            snippets.append(snippet)
        }
    }

    func fetch(id: UUID) throws -> TextSnippet? {
        snippets.first(where: { $0.id == id })
    }

    func fetchAll() throws -> [TextSnippet] {
        snippets.sorted { $0.trigger.localizedCaseInsensitiveCompare($1.trigger) == .orderedAscending }
    }

    func fetchEnabled() throws -> [TextSnippet] {
        snippets.filter { $0.isEnabled }
            .sorted { $0.trigger.localizedCaseInsensitiveCompare($1.trigger) == .orderedAscending }
    }

    func delete(id: UUID) throws -> Bool {
        let before = snippets.count
        snippets.removeAll { $0.id == id }
        return snippets.count < before
    }

    func deleteAll() throws {
        snippets.removeAll()
    }

    func incrementUseCount(ids: Set<UUID>) throws {
        incrementedIDs.append(ids)
        for id in ids {
            if let idx = snippets.firstIndex(where: { $0.id == id }) {
                snippets[idx].useCount += 1
            }
        }
    }
}

// MARK: - MockPermissionService

final class MockPermissionService: PermissionServiceProtocol, @unchecked Sendable {
    var microphonePermission: PermissionStatus = .granted
    var accessibilityPermission: Bool = true
    var screenRecordingPermission: Bool = true
    var requestMicResult: Bool = true
    var requestAccessibilityResult: Bool = true
    var requestScreenRecordingResult: Bool = true
    var openMicrophoneSettingsCount = 0
    var openScreenRecordingSettingsCount = 0

    func checkMicrophonePermission() async -> PermissionStatus {
        microphonePermission
    }

    func requestMicrophonePermission() async -> Bool {
        requestMicResult
    }

    func checkAccessibilityPermission() -> Bool {
        accessibilityPermission
    }

    func requestAccessibilityPermission(prompt: Bool) -> Bool {
        accessibilityPermission = requestAccessibilityResult
        return accessibilityPermission
    }

    func checkScreenRecordingPermission() -> Bool {
        screenRecordingPermission
    }

    func requestScreenRecordingPermission() -> Bool {
        screenRecordingPermission = requestScreenRecordingResult
        return screenRecordingPermission
    }

    func openMicrophoneSettings() {
        openMicrophoneSettingsCount += 1
    }

    func openScreenRecordingSettings() {
        openScreenRecordingSettingsCount += 1
    }
}

// MARK: - MockDictationService

actor MockDictationService: DictationServiceProtocol {
    var reprocessResult: Dictation?
    var reprocessError: Error?
    var reprocessDelayNs: UInt64 = 0
    var reprocessCallCount = 0
    var lastReprocessDictationID: UUID?
    var reprocessStartedCount = 0
    var reprocessFinishedCount = 0

    func configureReprocess(result: Dictation) {
        reprocessResult = result
        reprocessError = nil
    }

    func configureReprocess(error: Error) {
        reprocessError = error
        reprocessResult = nil
    }

    func configureReprocessDelay(milliseconds: UInt64) {
        reprocessDelayNs = milliseconds * 1_000_000
    }

    func startRecording() async throws {}

    func stopRecording() async throws -> Dictation {
        Dictation(durationMs: 1000, rawTranscript: "Mock")
    }

    func reprocessWithSpeakers(dictationID: UUID, onProgress: (@Sendable (ReprocessingProgress) -> Void)?) async throws -> Dictation {
        reprocessStartedCount += 1
        reprocessCallCount += 1
        lastReprocessDictationID = dictationID
        defer { reprocessFinishedCount += 1 }

        if reprocessDelayNs > 0 {
            try await Task.sleep(nanoseconds: reprocessDelayNs)
        }

        if let reprocessError {
            throw reprocessError
        }

        return reprocessResult ?? Dictation(durationMs: 1000, rawTranscript: "Reprocessed", derivedFromDictationId: dictationID, processingOrigin: .reprocessed)
    }

    func cancelRecording(reason: DictationCancelReason?) async {}

    func confirmCancel() async {}

    func undoCancel() async throws -> Dictation {
        Dictation(durationMs: 1000, rawTranscript: "Undo")
    }

    var state: DictationState {
        get async { .idle }
    }

    var audioLevel: Float {
        get async { 0 }
    }
}

// MARK: - MockExportService

@MainActor
final class MockExportService: ExportServiceProtocol, @unchecked Sendable {
    var clipboardText = ""
    var formatForClipboardCallCount = 0
    var exportToTxtCallCount = 0
    var exportToMarkdownCallCount = 0
    var lastTxtURL: URL?
    var lastMarkdownURL: URL?
    var lastTxtTranscription: Transcription?
    var lastMarkdownTranscription: Transcription?
    var txtError: Error?
    var markdownError: Error?

    func exportToTxt(transcription: Transcription, url: URL) throws {
        exportToTxtCallCount += 1
        lastTxtTranscription = transcription
        lastTxtURL = url
        if let txtError {
            throw txtError
        }
    }

    func exportToSRT(transcription: Transcription, url: URL) throws {}

    func exportToVTT(transcription: Transcription, url: URL) throws {}

    func exportToMarkdown(transcription: Transcription, url: URL) throws {
        exportToMarkdownCallCount += 1
        lastMarkdownTranscription = transcription
        lastMarkdownURL = url
        if let markdownError {
            throw markdownError
        }
    }

    func exportToJSON(transcription: Transcription, url: URL) throws {}

    func exportToPDF(transcription: Transcription, url: URL) throws {}

    func exportToDocx(transcription: Transcription, url: URL) throws {}

    func formatSRT(words: [WordTimestamp], speakers: [SpeakerInfo]?) -> String { "" }

    func formatVTT(words: [WordTimestamp], speakers: [SpeakerInfo]?) -> String { "" }

    func formatMarkdown(transcription: Transcription) -> String { "" }

    func formatForClipboard(transcription: Transcription) -> String {
        formatForClipboardCallCount += 1
        return clipboardText
    }
}

// MARK: - Clipboard and Save Panel Mocks

final class MockPasteboardClient: PasteboardClient, @unchecked Sendable {
    private(set) var lastWrittenText: String?

    func write(_ text: String) {
        lastWrittenText = text
    }
}

final class MockSavePanelClient: SavePanelClient, @unchecked Sendable {
    var nextURL: URL?
    private(set) var chooseSaveURLCallCount = 0
    private(set) var lastDefaultFileName: String?
    private(set) var lastContentType: UTType?

    func chooseSaveURL(defaultFileName: String, contentType: UTType) -> URL? {
        chooseSaveURLCallCount += 1
        lastDefaultFileName = defaultFileName
        lastContentType = contentType
        return nextURL
    }
}
