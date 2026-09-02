import CoreGraphics
import Foundation

public actor ConversationService {
    private let transcriber: any ConversationTranscribing
    private let replyGenerator: any ConversationReplyGenerating
    private let synthesizer: any ConversationVoiceSynthesizing
    private let player: any ConversationSpeechPlaying
    private let hasSystemAudioPermission: @Sendable () -> Bool

    private var continuation: AsyncStream<ConversationEvent>.Continuation?
    private var cachedEvents: AsyncStream<ConversationEvent>?
    private var turnTask: Task<Void, Never>?
    private var draftTask: Task<Void, Never>?
    private var context: [ChatMessage] = []
    private var revision = 0
    private var currentDraft: ConversationDraft?
    private var mode: ConversationMode = .liveSystemAudio
    private var running = false

    public init(
        transcriber: any ConversationTranscribing,
        replyGenerator: any ConversationReplyGenerating,
        synthesizer: any ConversationVoiceSynthesizing,
        player: any ConversationSpeechPlaying,
        hasSystemAudioPermission: @escaping @Sendable () -> Bool = {
            CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        }
    ) {
        self.transcriber = transcriber
        self.replyGenerator = replyGenerator
        self.synthesizer = synthesizer
        self.player = player
        self.hasSystemAudioPermission = hasSystemAudioPermission
    }

    public var events: AsyncStream<ConversationEvent> {
        if let cachedEvents { return cachedEvents }
        var continuation: AsyncStream<ConversationEvent>.Continuation?
        let stream = AsyncStream<ConversationEvent>(bufferingPolicy: .bufferingNewest(32)) {
            continuation = $0
        }
        self.continuation = continuation
        cachedEvents = stream
        return stream
    }

    public func start(
        referenceWAV: URL,
        mode: ConversationMode = .liveSystemAudio
    ) async throws {
        guard !running else { return }
        running = true
        self.mode = mode
        continuation?.yield(.state(.starting))
        if mode == .liveSystemAudio, !hasSystemAudioPermission() {
            running = false
            let error = MeetingAudioError.screenRecordingPermissionDenied
            continuation?.yield(.state(.failed(error.localizedDescription)))
            throw error
        }
        context = []
        revision = 0
        currentDraft = nil

        do {
            try await synthesizer.start(referenceWAV: referenceWAV)
            guard running else {
                await synthesizer.stop()
                return
            }
            if mode == .liveSystemAudio {
                let turns = await transcriber.finalizedTurns
                try await transcriber.start()
                guard running else { return }
                turnTask = Task { [weak self] in
                    for await text in turns {
                        await self?.receiveRemoteTurn(text)
                    }
                }
            }
            continuation?.yield(.state(.listening))
        } catch {
            let shouldReport = running
            running = false
            if mode == .liveSystemAudio { await transcriber.stop() }
            await synthesizer.stop()
            if shouldReport {
                continuation?.yield(.state(.failed(error.localizedDescription)))
                throw error
            }
        }
    }

    public func stop() async {
        guard running || turnTask != nil else { return }
        running = false
        turnTask?.cancel()
        turnTask = nil
        draftTask?.cancel()
        draftTask = nil
        if mode == .liveSystemAudio { await transcriber.stop() }
        await player.stop()
        context = []
        currentDraft = nil
        revision = 0
        continuation?.yield(.draft(nil))
        continuation?.yield(.state(.idle))
    }

    public func shutdown() async {
        await stop()
        await synthesizer.stop()
    }

    public func submitLocalTestTurn(_ text: String) {
        guard running, mode == .localTest else { return }
        receiveRemoteTurn(text)
    }

    public func regenerate() {
        guard running, !context.isEmpty else { return }
        createDraft(for: revision)
    }

    public func dismissDraft() {
        currentDraft = nil
        continuation?.yield(.draft(nil))
        continuation?.yield(.state(.listening))
    }

    public func speak(draftID: UUID) async throws {
        guard running,
              let draft = currentDraft,
              draft.id == draftID,
              draft.transcriptRevision == revision else { return }

        currentDraft = nil
        continuation?.yield(.draft(nil))
        continuation?.yield(.state(.speaking))

        // ponytail: capture pauses during local playback until BlackHole/process
        // exclusion is proven; switch to barge-in cancellation when that gate passes.
        if mode == .liveSystemAudio { await transcriber.stop() }
        do {
            let fileURL = try await synthesizer.synthesize(text: draft.text)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            guard running, draft.transcriptRevision == revision else {
                if running {
                    if mode == .liveSystemAudio { try? await transcriber.start() }
                    continuation?.yield(.state(.listening))
                }
                return
            }
            try await player.play(fileURL: fileURL)
            guard running else { return }
            context.append(ChatMessage(role: .assistant, content: draft.text))
            trimContext()
            if mode == .liveSystemAudio { try await transcriber.start() }
            continuation?.yield(.state(.listening))
        } catch {
            if running, mode == .liveSystemAudio { try? await transcriber.start() }
            continuation?.yield(.state(.failed(error.localizedDescription)))
            throw error
        }
    }

    private func receiveRemoteTurn(_ rawText: String) {
        guard running else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        revision += 1
        currentDraft = nil
        draftTask?.cancel()
        context.append(ChatMessage(role: .user, content: text))
        trimContext()
        continuation?.yield(.remoteTurn(text))
        continuation?.yield(.draft(nil))
        createDraft(for: revision)
    }

    private func createDraft(for sourceRevision: Int) {
        draftTask?.cancel()
        continuation?.yield(.state(.drafting))
        let messages = context
        draftTask = Task { [weak self, replyGenerator] in
            do {
                let text = try await replyGenerator.draft(messages: messages)
                try Task.checkCancellation()
                await self?.acceptDraft(text, revision: sourceRevision)
            } catch is CancellationError {
                // A newer remote turn invalidated this draft.
            } catch {
                await self?.draftFailed(error, revision: sourceRevision)
            }
        }
    }

    private func acceptDraft(_ rawText: String, revision sourceRevision: Int) {
        guard running, sourceRevision == revision else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            continuation?.yield(.state(.failed("The local model returned an empty reply.")))
            return
        }
        let draft = ConversationDraft(transcriptRevision: sourceRevision, text: text)
        currentDraft = draft
        continuation?.yield(.draft(draft))
        continuation?.yield(.state(.draftReady))
    }

    private func draftFailed(_ error: Error, revision sourceRevision: Int) {
        guard running, sourceRevision == revision else { return }
        continuation?.yield(.state(.failed(error.localizedDescription)))
    }

    private func trimContext() {
        if context.count > 12 {
            context.removeFirst(context.count - 12)
        }
    }
}
