import Foundation

public enum ConversationMode: Sendable, Equatable, Hashable {
    case localTest
    case liveSystemAudio
}

public struct ConversationDraft: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let transcriptRevision: Int
    public let text: String

    public init(id: UUID = UUID(), transcriptRevision: Int, text: String) {
        self.id = id
        self.transcriptRevision = transcriptRevision
        self.text = text
    }
}

public enum ConversationState: Sendable, Equatable {
    case idle
    case starting
    case listening
    case drafting
    case draftReady
    case speaking
    case failed(String)
}

public enum ConversationEvent: Sendable, Equatable {
    case state(ConversationState)
    case remoteTurn(String)
    case draft(ConversationDraft?)
}

public protocol ConversationTranscribing: Sendable {
    var finalizedTurns: AsyncStream<String> { get async }
    func start() async throws
    func stop() async
}

public protocol ConversationReplyGenerating: Sendable {
    func draft(messages: [ChatMessage]) async throws -> String
}

public protocol ConversationVoiceSynthesizing: Sendable {
    func start(referenceWAV: URL) async throws
    func synthesize(text: String) async throws -> URL
    func stop() async
}

public protocol ConversationSpeechPlaying: Sendable {
    func play(fileURL: URL) async throws
    func stop() async
}
