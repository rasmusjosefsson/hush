import XCTest
@testable import HushCore

final class DictationServiceTests: XCTestCase {
    var service: DictationService!
    var mockAudio: MockAudioProcessor!
    var mockSTT: MockSTTClient!
    var mockDiarization: MockDiarizationService!
    var dictationRepo: DictationRepository!

    override func setUp() async throws {
        let dbManager = try DatabaseManager()
        mockAudio = MockAudioProcessor()
        mockSTT = MockSTTClient()
        mockDiarization = MockDiarizationService()
        dictationRepo = DictationRepository(dbQueue: dbManager.dbQueue)

        service = DictationService(
            audioProcessor: mockAudio,
            sttClient: mockSTT,
            dictationRepo: dictationRepo,
            diarizationService: mockDiarization
        )
    }

    func testInitialStateIsIdle() async {
        let state = await service.state
        if case .idle = state {} else {
            XCTFail("Expected idle state, got \(state)")
        }
    }

    func testStartRecordingChangesState() async throws {
        try await service.startRecording()
        let state = await service.state
        if case .recording = state {} else {
            XCTFail("Expected recording state, got \(state)")
        }
    }

    func testStopRecordingTranscribesAndSaves() async throws {
        let expectedResult = STTResult(
            text: "Hello world",
            words: [
                TimestampedWord(word: "Hello", startMs: 0, endMs: 500, confidence: 0.98),
                TimestampedWord(word: "world", startMs: 520, endMs: 1000, confidence: 0.95)
            ]
        )
        await mockSTT.configure(result: expectedResult)

        try await service.startRecording()
        let dictation = try await service.stopRecording()

        XCTAssertEqual(dictation.rawTranscript, "Hello world")
        XCTAssertEqual(dictation.status, .completed)
        XCTAssertEqual(dictation.processingMode, .raw)
        XCTAssertEqual(dictation.durationMs, 1000)

        // Verify saved to DB
        let fetched = try dictationRepo.fetch(id: dictation.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.rawTranscript, "Hello world")
    }

    // Note: Cancel flow tests, stop-when-not-recording, and STT error propagation
    // are covered in CancelFlowTests.swift to avoid duplication.

    func testReprocessWithSpeakersUpdatesOriginalInPlace() async throws {
        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let original = Dictation(
            durationMs: 1_000,
            rawTranscript: "original raw",
            cleanTranscript: "original clean",
            audioPath: audioURL.path,
            processingMode: .clean,
            wordCount: 2
        )
        try dictationRepo.save(original)

        await mockSTT.configure(result: STTResult(
            text: "hello there",
            words: [
                TimestampedWord(word: "hello", startMs: 0, endMs: 200, confidence: 0.91),
                TimestampedWord(word: "there", startMs: 220, endMs: 480, confidence: 0.89)
            ]
        ))
        await mockDiarization.configure(result: HushDiarizationResult(
            segments: [SpeakerSegment(speakerId: "S1", startMs: 0, endMs: 800)],
            speakerCount: 1,
            speakers: [SpeakerInfo(id: "S1", label: "Speaker 1")]
        ))

        let updated = try await service.reprocessWithSpeakers(dictationID: original.id)

        // Reprocess edits in place to avoid history clutter (commit 909641e).
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.rawTranscript, "hello there")
        XCTAssertEqual(updated.wordTimestamps?.count, 2)
        XCTAssertEqual(updated.wordTimestamps?.first?.speakerId, "S1")
        XCTAssertEqual(updated.speakerCount, 1)
        XCTAssertEqual(updated.speakers?.first?.id, "S1")
        XCTAssertEqual(updated.diarizationSegments?.count, 1)

        let fetched = try dictationRepo.fetch(id: original.id)
        XCTAssertEqual(fetched?.rawTranscript, "hello there")
        XCTAssertEqual(fetched?.speakerCount, 1)

        let all = try dictationRepo.fetchAll(limit: nil)
        XCTAssertEqual(all.count, 1, "Reprocess should not create a new row")
    }

    func testReprocessWithSpeakersFailsWhenAudioMissing() async throws {
        let original = Dictation(durationMs: 1_000, rawTranscript: "hello", audioPath: nil)
        try dictationRepo.save(original)

        do {
            _ = try await service.reprocessWithSpeakers(dictationID: original.id)
            XCTFail("Expected missing audio error")
        } catch {
            // expected
        }

        let all = try dictationRepo.fetchAll(limit: nil)
        XCTAssertEqual(all.count, 1)
    }

    func testReprocessWithSpeakersFailsWhenAudioFileMissingAndCreatesNothing() async throws {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-")
            .appendingPathExtension(UUID().uuidString)
            .appendingPathExtension("wav")
            .path
        let original = Dictation(durationMs: 1_000, rawTranscript: "hello", audioPath: missingPath)
        try dictationRepo.save(original)

        do {
            _ = try await service.reprocessWithSpeakers(dictationID: original.id)
            XCTFail("Expected missing file error")
        } catch {
            // expected
        }

        let all = try dictationRepo.fetchAll(limit: nil)
        XCTAssertEqual(all.count, 1)
    }

    func testReprocessWithSpeakersFailsWhenSTTFailsAndCreatesNothing() async throws {
        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let original = Dictation(durationMs: 1_000, rawTranscript: "hello", audioPath: audioURL.path)
        try dictationRepo.save(original)
        await mockSTT.configure(error: STTError.transcriptionFailed("boom"))

        do {
            _ = try await service.reprocessWithSpeakers(dictationID: original.id)
            XCTFail("Expected STT failure")
        } catch {
            // expected
        }

        let all = try dictationRepo.fetchAll(limit: nil)
        XCTAssertEqual(all.count, 1)
    }

    func testReprocessWithSpeakersFailsWhenDiarizationFailsAndCreatesNothing() async throws {
        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let original = Dictation(durationMs: 1_000, rawTranscript: "hello", audioPath: audioURL.path)
        try dictationRepo.save(original)
        await mockSTT.configure(result: STTResult(
            text: "hello",
            words: [TimestampedWord(word: "hello", startMs: 0, endMs: 300, confidence: 0.9)]
        ))
        struct MockError: Error {}
        await mockDiarization.configure(error: MockError())

        do {
            _ = try await service.reprocessWithSpeakers(dictationID: original.id)
            XCTFail("Expected diarization failure")
        } catch {
            // expected
        }

        let all = try dictationRepo.fetchAll(limit: nil)
        XCTAssertEqual(all.count, 1)
    }

    private func makeTempAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-service-tests-")
            .appendingPathExtension(UUID().uuidString)
            .appendingPathExtension("wav")
        let created = FileManager.default.createFile(atPath: url.path, contents: Data("audio".utf8))
        XCTAssertTrue(created)
        return url
    }
}
