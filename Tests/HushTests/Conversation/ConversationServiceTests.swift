import Foundation
@testable import HushCore
import XCTest

final class ConversationServiceTests: XCTestCase {
    func testMissingSystemAudioPermissionFailsBeforeStartingModels() async {
        let synthesizer = FakeConversationSynthesizer()
        let service = ConversationService(
            transcriber: FakeConversationTranscriber(),
            replyGenerator: FakeConversationReplyGenerator(),
            synthesizer: synthesizer,
            player: FakeConversationPlayer(),
            hasSystemAudioPermission: { false }
        )

        do {
            try await service.start(referenceWAV: URL(fileURLWithPath: "/tmp/reference.wav"))
            XCTFail("Expected permission failure")
        } catch MeetingAudioError.screenRecordingPermissionDenied {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let startCount = await synthesizer.startCount
        XCTAssertEqual(startCount, 0)
    }

    func testLocalModeDraftsAndSpeaksWithoutStartingCapture() async throws {
        let transcriber = FakeConversationTranscriber()
        let synthesizer = FakeConversationSynthesizer()
        let player = FakeConversationPlayer()
        let service = ConversationService(
            transcriber: transcriber,
            replyGenerator: FakeConversationReplyGenerator(),
            synthesizer: synthesizer,
            player: player,
            hasSystemAudioPermission: { false }
        )
        let recorder = EventRecorder()
        let events = await service.events
        let eventTask = Task { for await event in events { await recorder.append(event) } }
        defer { eventTask.cancel() }

        try await service.start(
            referenceWAV: URL(fileURLWithPath: "/tmp/reference.wav"),
            mode: .localTest
        )
        await service.submitLocalTestTurn("Can we meet Friday?")
        try await waitUntil { await recorder.latestDraft() != nil }
        let recordedDraft = await recorder.latestDraft()
        let draft = try XCTUnwrap(recordedDraft)
        try await service.speak(draftID: draft.id)

        let transcriberStartCount = await transcriber.startCount
        let synthesizeCount = await synthesizer.synthesizeCount
        let playCount = await player.playCount
        XCTAssertEqual(transcriberStartCount, 0)
        XCTAssertEqual(synthesizeCount, 1)
        XCTAssertEqual(playCount, 1)
        await service.stop()
    }

    func testDraftDoesNotSpeakUntilApproved() async throws {
        let transcriber = FakeConversationTranscriber()
        let synthesizer = FakeConversationSynthesizer()
        let player = FakeConversationPlayer()
        let service = ConversationService(
            transcriber: transcriber,
            replyGenerator: FakeConversationReplyGenerator(),
            synthesizer: synthesizer,
            player: player,
            hasSystemAudioPermission: { true }
        )
        let recorder = EventRecorder()
        let events = await service.events
        let eventTask = Task { for await event in events { await recorder.append(event) } }
        defer { eventTask.cancel() }

        try await service.start(referenceWAV: URL(fileURLWithPath: "/tmp/reference.wav"))
        await transcriber.emit("Can we meet Friday?")
        try await waitUntil { await recorder.latestDraft() != nil }

        let countBeforeApproval = await synthesizer.synthesizeCount
        let recordedDraft = await recorder.latestDraft()
        XCTAssertEqual(countBeforeApproval, 0)
        let draft = try XCTUnwrap(recordedDraft)
        try await service.speak(draftID: draft.id)

        let countAfterApproval = await synthesizer.synthesizeCount
        let playCount = await player.playCount
        XCTAssertEqual(countAfterApproval, 1)
        XCTAssertEqual(playCount, 1)
        await service.stop()
    }

    func testNewTurnInvalidatesOldDraftAndApproval() async throws {
        let transcriber = FakeConversationTranscriber()
        let synthesizer = FakeConversationSynthesizer()
        let service = ConversationService(
            transcriber: transcriber,
            replyGenerator: FakeConversationReplyGenerator(),
            synthesizer: synthesizer,
            player: FakeConversationPlayer(),
            hasSystemAudioPermission: { true }
        )
        let recorder = EventRecorder()
        let events = await service.events
        let eventTask = Task { for await event in events { await recorder.append(event) } }
        defer { eventTask.cancel() }

        try await service.start(referenceWAV: URL(fileURLWithPath: "/tmp/reference.wav"))
        await transcriber.emit("First turn")
        try await waitUntil { await recorder.latestDraft()?.transcriptRevision == 1 }
        let recordedStaleDraft = await recorder.latestDraft()
        let staleDraft = try XCTUnwrap(recordedStaleDraft)

        await transcriber.emit("Second turn")
        try await waitUntil { await recorder.latestDraft()?.transcriptRevision == 2 }
        try await service.speak(draftID: staleDraft.id)

        let synthesizeCount = await synthesizer.synthesizeCount
        let currentDraft = await recorder.latestDraft()
        XCTAssertEqual(synthesizeCount, 0)
        XCTAssertEqual(currentDraft?.text, "Reply to Second turn")
        await service.stop()
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @escaping () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition timed out")
    }
}

private actor FakeConversationTranscriber: ConversationTranscribing {
    private var continuation: AsyncStream<String>.Continuation?
    private var stream: AsyncStream<String>?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    var finalizedTurns: AsyncStream<String> {
        if let stream { return stream }
        var continuation: AsyncStream<String>.Continuation?
        let stream = AsyncStream<String> { continuation = $0 }
        self.continuation = continuation
        self.stream = stream
        return stream
    }

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func emit(_ text: String) { continuation?.yield(text) }
}

private actor FakeConversationReplyGenerator: ConversationReplyGenerating {
    func draft(messages: [ChatMessage]) -> String {
        "Reply to \(messages.last?.content ?? "")"
    }
}

private actor FakeConversationSynthesizer: ConversationVoiceSynthesizing {
    private(set) var startCount = 0
    private(set) var synthesizeCount = 0

    func start(referenceWAV: URL) { startCount += 1 }
    func synthesize(text: String) -> URL {
        synthesizeCount += 1
        return URL(fileURLWithPath: "/tmp/reply.wav")
    }
    func stop() {}
}

private actor FakeConversationPlayer: ConversationSpeechPlaying {
    private(set) var playCount = 0

    func play(fileURL: URL) { playCount += 1 }
    func stop() {}
}

private actor EventRecorder {
    private var events: [ConversationEvent] = []

    func append(_ event: ConversationEvent) { events.append(event) }

    func latestDraft() -> ConversationDraft? {
        for event in events.reversed() {
            if case .draft(let draft) = event, let draft { return draft }
        }
        return nil
    }
}
