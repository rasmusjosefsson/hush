import XCTest
@testable import HushCore
@testable import HushViewModels

@MainActor
final class DictationHistoryViewModelTests: XCTestCase {
    var viewModel: DictationHistoryViewModel!
    var mockRepo: MockDictationRepository!
    var mockDictationService: MockDictationService!
    var mockExportService: MockExportService!
    var mockSavePanel: MockSavePanelClient!

    override func setUp() {
        mockRepo = MockDictationRepository()
        mockDictationService = MockDictationService()
        mockExportService = MockExportService()
        mockSavePanel = MockSavePanelClient()
        viewModel = DictationHistoryViewModel()
    }

    // MARK: - Fetching

    func testConfigureLoadsDictations() {
        let dictation = Dictation(
            durationMs: 1000,
            rawTranscript: "Hello world"
        )
        mockRepo.dictations = [dictation]

        viewModel.configure(dictationRepo: mockRepo)

        XCTAssertEqual(viewModel.groupedDictations.count, 1, "Should have one date group")
        XCTAssertEqual(viewModel.groupedDictations[0].1.count, 1, "Group should have one dictation")
        XCTAssertEqual(viewModel.groupedDictations[0].1[0].rawTranscript, "Hello world")
    }

    func testEmptyRepoResultsInEmptyList() {
        viewModel.configure(dictationRepo: mockRepo)

        XCTAssertTrue(viewModel.groupedDictations.isEmpty)
    }

    func testMultipleDictationsGroupedByDate() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!

        mockRepo.dictations = [
            Dictation(createdAt: today, durationMs: 1000, rawTranscript: "Today's dictation"),
            Dictation(createdAt: yesterday, durationMs: 2000, rawTranscript: "Yesterday's dictation"),
            Dictation(createdAt: twoDaysAgo, durationMs: 3000, rawTranscript: "Older dictation"),
        ]

        viewModel.configure(dictationRepo: mockRepo)

        XCTAssertEqual(viewModel.groupedDictations.count, 3, "Should have three date groups")
        // Groups are sorted newest first
        XCTAssertEqual(viewModel.groupedDictations[0].0, "Today")
        XCTAssertEqual(viewModel.groupedDictations[1].0, "Yesterday")
    }

    func testTodayGroupHeader() {
        mockRepo.dictations = [
            Dictation(createdAt: Date(), durationMs: 500, rawTranscript: "Now")
        ]

        viewModel.configure(dictationRepo: mockRepo)

        XCTAssertEqual(viewModel.groupedDictations[0].0, "Today")
    }

    func testYesterdayGroupHeader() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        mockRepo.dictations = [
            Dictation(createdAt: yesterday, durationMs: 500, rawTranscript: "Yesterday entry")
        ]

        viewModel.configure(dictationRepo: mockRepo)

        XCTAssertEqual(viewModel.groupedDictations[0].0, "Yesterday")
    }

    func testMultipleDictationsSameDayGroupedTogether() {
        // Use noon today to avoid midnight boundary issues
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let now = noon
        let earlier = noon.addingTimeInterval(-3600) // 11 AM same day

        mockRepo.dictations = [
            Dictation(createdAt: now, durationMs: 1000, rawTranscript: "First"),
            Dictation(createdAt: earlier, durationMs: 2000, rawTranscript: "Second"),
        ]

        viewModel.configure(dictationRepo: mockRepo)

        XCTAssertEqual(viewModel.groupedDictations.count, 1, "Same day should be one group")
        XCTAssertEqual(viewModel.groupedDictations[0].1.count, 2, "Group should have two dictations")
        // Within a group, sorted by createdAt descending
        XCTAssertEqual(viewModel.groupedDictations[0].1[0].rawTranscript, "First")
        XCTAssertEqual(viewModel.groupedDictations[0].1[1].rawTranscript, "Second")
    }

    // MARK: - Search

    func testSearchFiltersDictations() {
        mockRepo.dictations = [
            Dictation(durationMs: 1000, rawTranscript: "The quick brown fox"),
            Dictation(durationMs: 1000, rawTranscript: "Hello world"),
            Dictation(durationMs: 1000, rawTranscript: "Goodbye world"),
        ]

        viewModel.configure(dictationRepo: mockRepo)
        XCTAssertEqual(totalDictationCount(), 3, "Before search, all three should be loaded")

        viewModel.searchText = "world"
        viewModel.loadDictations()

        XCTAssertEqual(totalDictationCount(), 2, "Should match two dictations containing 'world'")
    }

    func testClearSearchShowsAll() {
        mockRepo.dictations = [
            Dictation(durationMs: 1000, rawTranscript: "The quick brown fox"),
            Dictation(durationMs: 1000, rawTranscript: "Hello world"),
        ]

        viewModel.configure(dictationRepo: mockRepo)
        viewModel.searchText = "fox"
        viewModel.loadDictations()
        XCTAssertEqual(totalDictationCount(), 1)

        viewModel.searchText = ""
        XCTAssertEqual(totalDictationCount(), 2, "Clearing search should show all dictations")
    }

    func testSearchNoResults() {
        mockRepo.dictations = [
            Dictation(durationMs: 1000, rawTranscript: "Hello world"),
        ]

        viewModel.configure(dictationRepo: mockRepo)
        viewModel.searchText = "nonexistent"
        viewModel.loadDictations()

        XCTAssertTrue(viewModel.groupedDictations.isEmpty, "No results for unmatched search")
    }

    // MARK: - Delete

    func testDeleteRemovesFromList() {
        let dictation = Dictation(durationMs: 1000, rawTranscript: "To be deleted")
        mockRepo.dictations = [dictation]

        viewModel.configure(dictationRepo: mockRepo)
        XCTAssertEqual(totalDictationCount(), 1)

        viewModel.deleteDictation(dictation)

        XCTAssertTrue(viewModel.groupedDictations.isEmpty, "List should be empty after deletion")
        XCTAssertTrue(mockRepo.deleteCalledWith.contains(dictation.id))
    }

    // MARK: - Unconfigured

    func testLoadDictationsBeforeConfigureIsNoOp() {
        viewModel.loadDictations()
        XCTAssertTrue(viewModel.groupedDictations.isEmpty, "Should be empty when no repo configured")
    }

    func testDeleteBeforeConfigureIsNoOp() {
        let dictation = Dictation(durationMs: 1000, rawTranscript: "Test")
        // Should not crash
        viewModel.deleteDictation(dictation)
        XCTAssertTrue(viewModel.groupedDictations.isEmpty)
    }

    // MARK: - Playback State

    func testStopPlaybackResetsState() {
        viewModel.configure(dictationRepo: mockRepo)

        // Manually set playback state as if playing
        viewModel.isPlaying = true
        viewModel.playingDictationId = UUID()
        viewModel.playbackCurrentTime = 5.0
        viewModel.playbackDuration = 10.0

        viewModel.stopPlayback()

        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertNil(viewModel.playingDictationId)
        XCTAssertEqual(viewModel.playbackCurrentTime, 0)
        XCTAssertEqual(viewModel.playbackDuration, 0)
    }

    func testTogglePlaybackWithNoAudioPathIsNoOp() {
        let dictation = Dictation(durationMs: 1000, rawTranscript: "No audio")
        mockRepo.dictations = [dictation]
        viewModel.configure(dictationRepo: mockRepo)

        viewModel.togglePlayback(for: dictation)

        XCTAssertFalse(viewModel.isPlaying, "Should not play when no audio path")
        XCTAssertNil(viewModel.playingDictationId)
    }

    func testTogglePlaybackWithNonexistentFileIsNoOp() {
        let dictation = Dictation(
            durationMs: 1000,
            rawTranscript: "Has path",
            audioPath: "/nonexistent/path/audio.m4a"
        )
        mockRepo.dictations = [dictation]
        viewModel.configure(dictationRepo: mockRepo)

        viewModel.togglePlayback(for: dictation)

        XCTAssertFalse(viewModel.isPlaying, "Should not play when file doesn't exist")
    }

    func testDeleteClearsPlaybackForThatDictation() {
        let dictation = Dictation(durationMs: 1000, rawTranscript: "Playing")
        mockRepo.dictations = [dictation]
        viewModel.configure(dictationRepo: mockRepo)

        // Simulate playing state
        viewModel.isPlaying = true
        viewModel.playingDictationId = dictation.id

        viewModel.deleteDictation(dictation)

        XCTAssertFalse(viewModel.isPlaying, "Deleting playing dictation should stop playback")
        XCTAssertNil(viewModel.playingDictationId)
    }

    func testDeleteSharedAudioKeepsFileWhenAnotherReferenceRemains() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("shared-audio-\(UUID().uuidString).wav")
        let created = FileManager.default.createFile(atPath: tempURL.path, contents: Data("audio".utf8))
        XCTAssertTrue(created)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let original = Dictation(durationMs: 1000, rawTranscript: "Original", audioPath: tempURL.path)
        let derived = Dictation(durationMs: 1200, rawTranscript: "Derived", audioPath: tempURL.path, derivedFromDictationId: original.id, processingOrigin: .reprocessed)
        mockRepo.dictations = [original, derived]
        viewModel.configure(dictationRepo: mockRepo)

        viewModel.deleteDictation(original)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        XCTAssertTrue(mockRepo.dictations.contains { $0.id == derived.id })
    }

    func testDeleteSharedAudioRemovesFileWhenLastReferenceDeleted() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("single-audio-\(UUID().uuidString).wav")
        let created = FileManager.default.createFile(atPath: tempURL.path, contents: Data("audio".utf8))
        XCTAssertTrue(created)

        let dictation = Dictation(durationMs: 1000, rawTranscript: "Only", audioPath: tempURL.path)
        mockRepo.dictations = [dictation]
        viewModel.configure(dictationRepo: mockRepo)

        viewModel.deleteDictation(dictation)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testPlaybackProgressZeroWhenDurationZero() {
        viewModel.configure(dictationRepo: mockRepo)
        XCTAssertEqual(viewModel.playbackProgress, 0, "Progress should be 0 when duration is 0")
    }

    func testPausePlaybackSetsNotPlaying() {
        viewModel.configure(dictationRepo: mockRepo)
        viewModel.isPlaying = true

        viewModel.pausePlayback()

        XCTAssertFalse(viewModel.isPlaying)
    }

    // MARK: - Playing Dictation

    func testPlayingDictationReturnsCurrentlyPlaying() {
        let dictation = Dictation(durationMs: 1000, rawTranscript: "Playing now")
        mockRepo.dictations = [dictation]
        viewModel.configure(dictationRepo: mockRepo)

        XCTAssertNil(viewModel.playingDictation, "Should be nil when nothing is playing")

        viewModel.playingDictationId = dictation.id

        XCTAssertEqual(viewModel.playingDictation?.id, dictation.id, "Should return the currently playing dictation")
    }

    // MARK: - Confirm Delete

    func testConfirmDeleteRemovesDictation() {
        let dictation = Dictation(durationMs: 1000, rawTranscript: "To be confirmed deleted")
        mockRepo.dictations = [dictation]
        viewModel.configure(dictationRepo: mockRepo)

        viewModel.pendingDeleteDictation = dictation
        XCTAssertNotNil(viewModel.pendingDeleteDictation)

        viewModel.confirmDelete()

        XCTAssertNil(viewModel.pendingDeleteDictation, "Pending should be cleared after confirm")
        XCTAssertTrue(mockRepo.deleteCalledWith.contains(dictation.id), "Should have called delete")
        XCTAssertTrue(viewModel.groupedDictations.isEmpty, "Dictation should be removed from list")
    }

    // MARK: - Stats

    func testStatsLoadedOnConfigure() {
        mockRepo.dictations = [
            Dictation(durationMs: 5000, rawTranscript: "Hello world test", wordCount: 3)
        ]

        viewModel.configure(dictationRepo: mockRepo)

        XCTAssertFalse(viewModel.stats.isEmpty)
        XCTAssertEqual(viewModel.stats.totalCount, 1)
        XCTAssertEqual(viewModel.stats.totalWords, 3) // "Hello world test"
    }

    func testConfigureRefreshesStatsOnce() {
        mockRepo.dictations = [
            Dictation(durationMs: 1000, rawTranscript: "One")
        ]

        viewModel.configure(dictationRepo: mockRepo)

        XCTAssertEqual(mockRepo.statsCallCount, 1)
    }

    func testStatsRefreshOnDelete() {
        let d1 = Dictation(durationMs: 1000, rawTranscript: "First dictation")
        let d2 = Dictation(durationMs: 2000, rawTranscript: "Second")
        mockRepo.dictations = [d1, d2]

        viewModel.configure(dictationRepo: mockRepo)
        XCTAssertEqual(viewModel.stats.totalCount, 2)

        viewModel.deleteDictation(d1)
        XCTAssertEqual(viewModel.stats.totalCount, 1)
    }

    func testDeleteRefreshesStatsOncePerDelete() {
        let d1 = Dictation(durationMs: 1000, rawTranscript: "First")
        let d2 = Dictation(durationMs: 2000, rawTranscript: "Second")
        mockRepo.dictations = [d1, d2]

        viewModel.configure(dictationRepo: mockRepo)
        XCTAssertEqual(mockRepo.statsCallCount, 1)

        viewModel.deleteDictation(d1)
        XCTAssertEqual(mockRepo.statsCallCount, 2)
    }

    func testSearchReloadSkipsStatsRefresh() {
        mockRepo.dictations = [
            Dictation(durationMs: 1000, rawTranscript: "Hello world"),
            Dictation(durationMs: 1000, rawTranscript: "Goodbye world"),
        ]
        viewModel.configure(dictationRepo: mockRepo)
        let initialStatsCalls = mockRepo.statsCallCount

        viewModel.searchText = "world"
        viewModel.loadDictations(shouldRefreshStats: false)

        XCTAssertEqual(mockRepo.statsCallCount, initialStatsCalls)
    }

    func testStatsEmptyWhenNoDictations() {
        viewModel.configure(dictationRepo: mockRepo)
        XCTAssertTrue(viewModel.stats.isEmpty)
    }

    // MARK: - Helpers

    func testFormattedClipboardTextSplitsSentenceBoundaries() {
        let dictation = Dictation(
            durationMs: 1000,
            rawTranscript: "Hello world. How are you? I am fine!"
        )

        let formatted = viewModel.formattedClipboardText(for: dictation)

        XCTAssertEqual(formatted, "Hello world.\nHow are you?\nI am fine!")
    }

    func testFormattedClipboardTextPreservesExistingNewlines() {
        let dictation = Dictation(
            durationMs: 1000,
            rawTranscript: "Line one\nLine two"
        )

        let formatted = viewModel.formattedClipboardText(for: dictation)

        XCTAssertEqual(formatted, "Line one\nLine two")
    }

    func testExportTranscriptAsTxtNormalizesExtensionAndCallsExportService() {
        let dictation = Dictation(
            createdAt: Date(timeIntervalSince1970: 123),
            durationMs: 2000,
            rawTranscript: "Hello world"
        )
        mockSavePanel.nextURL = URL(fileURLWithPath: "/tmp/dictation-export")

        viewModel.configure(
            dictationRepo: mockRepo,
            exportService: mockExportService,
            savePanelClient: mockSavePanel
        )

        viewModel.exportTranscriptAsTxt(for: dictation)

        XCTAssertEqual(mockExportService.exportToTxtCallCount, 1)
        XCTAssertEqual(mockExportService.lastTxtURL?.pathExtension, "txt")
        XCTAssertEqual(mockSavePanel.lastDefaultFileName?.suffix(4), ".txt")
    }

    func testExportTranscriptAsMarkdownNormalizesExtensionAndCallsExportService() {
        let dictation = Dictation(
            createdAt: Date(timeIntervalSince1970: 123),
            durationMs: 2000,
            rawTranscript: "Hello world"
        )
        mockSavePanel.nextURL = URL(fileURLWithPath: "/tmp/dictation-export.txt")

        viewModel.configure(
            dictationRepo: mockRepo,
            exportService: mockExportService,
            savePanelClient: mockSavePanel
        )

        viewModel.exportTranscriptAsMarkdown(for: dictation)

        XCTAssertEqual(mockExportService.exportToMarkdownCallCount, 1)
        XCTAssertEqual(mockExportService.lastMarkdownURL?.pathExtension, "md")
        XCTAssertEqual(mockSavePanel.lastDefaultFileName?.suffix(3), ".md")
    }

    func testReprocessWithSpeakersTogglesProcessingState() async {
        let dictation = Dictation(durationMs: 1000, rawTranscript: "Original", audioPath: "/tmp/audio.wav")
        mockRepo.dictations = [dictation]
        await mockDictationService.configureReprocessDelay(milliseconds: 50)
        await mockDictationService.configureReprocess(
            result: Dictation(durationMs: 1200, rawTranscript: "Derived", derivedFromDictationId: dictation.id, processingOrigin: .reprocessed)
        )

        viewModel.configure(dictationRepo: mockRepo, dictationService: mockDictationService, exportService: mockExportService)

        viewModel.reprocessWithSpeakers(dictation)
        await waitUntil("processing starts") { [self] in
            self.viewModel.processingDictationIDs.contains(dictation.id)
        }

        await waitUntil("processing finishes") { [self] in
            !self.viewModel.processingDictationIDs.contains(dictation.id)
        }

        let started = await mockDictationService.reprocessStartedCount
        let finished = await mockDictationService.reprocessFinishedCount
        XCTAssertEqual(started, 1)
        XCTAssertEqual(finished, 1)
    }

    func testReprocessWithSpeakersIgnoresDuplicateRequestWhileInFlight() async {
        let dictation = Dictation(durationMs: 1000, rawTranscript: "Original", audioPath: "/tmp/audio.wav")
        mockRepo.dictations = [dictation]
        await mockDictationService.configureReprocessDelay(milliseconds: 120)
        await mockDictationService.configureReprocess(
            result: Dictation(durationMs: 1200, rawTranscript: "Derived", derivedFromDictationId: dictation.id, processingOrigin: .reprocessed)
        )

        viewModel.configure(dictationRepo: mockRepo, dictationService: mockDictationService, exportService: mockExportService)

        viewModel.reprocessWithSpeakers(dictation)
        await waitUntil("first request starts") { [self] in
            self.viewModel.processingDictationIDs.contains(dictation.id)
        }

        viewModel.reprocessWithSpeakers(dictation)

        await waitUntil("single in-flight request completes") { [self] in
            !self.viewModel.processingDictationIDs.contains(dictation.id)
        }

        let reprocessCalls = await mockDictationService.reprocessCallCount
        let started = await mockDictationService.reprocessStartedCount
        let finished = await mockDictationService.reprocessFinishedCount
        XCTAssertEqual(reprocessCalls, 1)
        XCTAssertEqual(started, 1)
        XCTAssertEqual(finished, 1)
    }

    func testReprocessWithSpeakersSuccessReloadsHistory() async {
        let dictation = Dictation(durationMs: 1000, rawTranscript: "Original", audioPath: "/tmp/audio.wav")
        mockRepo.dictations = [dictation]

        let derived = Dictation(durationMs: 1200, rawTranscript: "Derived", derivedFromDictationId: dictation.id, processingOrigin: .reprocessed)
        await mockDictationService.configureReprocess(result: derived)

        viewModel.configure(dictationRepo: mockRepo, dictationService: mockDictationService, exportService: mockExportService)
        let beforeFetchCount = mockRepo.fetchAllCallCount

        viewModel.reprocessWithSpeakers(dictation)
        await waitUntil("success reload") { [self] in
            self.mockRepo.fetchAllCallCount > beforeFetchCount
        }

        XCTAssertGreaterThan(mockRepo.fetchAllCallCount, beforeFetchCount)
        XCTAssertNil(viewModel.processingError)
    }

    func testReprocessWithSpeakersFailureSetsProcessingError() async {
        let dictation = Dictation(durationMs: 1000, rawTranscript: "Original", audioPath: "/tmp/audio.wav")
        mockRepo.dictations = [dictation]
        await mockDictationService.configureReprocess(error: DictationServiceError.audioFileMissing)

        viewModel.configure(dictationRepo: mockRepo, dictationService: mockDictationService, exportService: mockExportService)

        viewModel.reprocessWithSpeakers(dictation)
        await waitUntil("failure processing cleanup") { [self] in
            !self.viewModel.processingDictationIDs.contains(dictation.id)
        }

        XCTAssertFalse(viewModel.processingDictationIDs.contains(dictation.id))
        XCTAssertEqual(viewModel.processingError, DictationServiceError.audioFileMissing.localizedDescription)
    }

    func testExportMappingIncludesSpeakerPayload() {
        let dictation = Dictation(
            durationMs: 2000,
            rawTranscript: "Hello there",
            cleanTranscript: "Hello there.",
            wordTimestamps: [WordTimestamp(word: "Hello", startMs: 0, endMs: 350, confidence: 0.9, speakerId: "S1")],
            speakerCount: 1,
            speakers: [SpeakerInfo(id: "S1", label: "Speaker 1")],
            diarizationSegments: [DiarizationSegmentRecord(speakerId: "S1", startMs: 0, endMs: 900)]
        )
        mockSavePanel.nextURL = URL(fileURLWithPath: "/tmp/dictation-export.md")

        viewModel.configure(
            dictationRepo: mockRepo,
            dictationService: mockDictationService,
            exportService: mockExportService,
            savePanelClient: mockSavePanel
        )

        viewModel.exportTranscriptAsMarkdown(for: dictation)

        XCTAssertEqual(mockExportService.lastMarkdownTranscription?.speakerCount, 1)
        XCTAssertEqual(mockExportService.lastMarkdownTranscription?.speakers?.first?.id, "S1")
        XCTAssertEqual(mockExportService.lastMarkdownTranscription?.wordTimestamps?.first?.speakerId, "S1")
        XCTAssertEqual(mockExportService.lastMarkdownTranscription?.diarizationSegments?.first?.speakerId, "S1")
    }

    private func totalDictationCount() -> Int {
        viewModel.groupedDictations.reduce(0) { $0 + $1.1.count }
    }

    private func waitUntil(
        _ description: String,
        timeoutSeconds: TimeInterval = 1.0,
        pollNs: UInt64 = 10_000_000,
        condition: @MainActor @escaping () -> Bool
    ) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeoutSeconds {
            if condition() { return }
            try? await Task.sleep(nanoseconds: pollNs)
        }
        XCTFail("Timed out waiting for condition: \(description)")
    }
}
