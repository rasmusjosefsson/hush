import Foundation
import HushCore

@MainActor
@Observable
public final class ConversationViewModel {
    public private(set) var state: ConversationState = .idle
    public private(set) var remoteTurns: [String] = []
    public private(set) var draft: ConversationDraft?
    public private(set) var referenceAudioURL: URL?
    public private(set) var isRunning = false
    public private(set) var availabilityError: String?
    public var mode: ConversationMode = .localTest

    private var service: ConversationService?
    private var canStart: @MainActor () -> Bool = { true }
    private var eventTask: Task<Void, Never>?
    private static let referencePathKey = "conversationVoiceReferencePath"

    public init() {
        if let path = UserDefaults.standard.string(forKey: Self.referencePathKey) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isReadableFile(atPath: path) { referenceAudioURL = url }
        }
    }

    public func configure(
        service: ConversationService?,
        canStart: @escaping @MainActor () -> Bool = { true }
    ) {
        self.service = service
        self.canStart = canStart
        availabilityError = service == nil ? "Conversation support is unavailable in this build." : nil
    }

    public func selectReferenceAudio(_ url: URL) {
        referenceAudioURL = url
        UserDefaults.standard.set(url.path, forKey: Self.referencePathKey)
    }

    public func start() {
        guard let service, let referenceAudioURL, !isRunning else { return }
        guard canStart() else {
            state = .failed("Stop the current dictation before starting Conversation.")
            return
        }
        isRunning = true
        state = .starting
        remoteTurns = []
        draft = nil
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            let events = await service.events
            for await event in events {
                guard let self else { return }
                apply(event)
            }
        }
        Task {
            do {
                try await service.start(referenceWAV: referenceAudioURL, mode: mode)
            } catch {
                isRunning = false
                state = .failed(error.localizedDescription)
            }
        }
    }

    public func stop() {
        guard let service else { return }
        Task {
            await service.stop()
            eventTask?.cancel()
            eventTask = nil
            isRunning = false
            state = .idle
            draft = nil
        }
    }

    public func submitLocalTestTurn(_ text: String) {
        Task { await service?.submitLocalTestTurn(text) }
    }

    public func regenerate() {
        Task { await service?.regenerate() }
    }

    public func dismissDraft() {
        Task { await service?.dismissDraft() }
    }

    public func speak() {
        guard let draft else { return }
        Task {
            do {
                try await service?.speak(draftID: draft.id)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func apply(_ event: ConversationEvent) {
        switch event {
        case .state(let state):
            self.state = state
            if state == .idle { isRunning = false }
        case .remoteTurn(let text):
            remoteTurns.append(text)
            if remoteTurns.count > 20 { remoteTurns.removeFirst(remoteTurns.count - 20) }
        case .draft(let draft):
            self.draft = draft
        }
    }
}
