import Foundation
import GRDB

public struct Dictation: Codable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var durationMs: Int
    public var rawTranscript: String
    public var cleanTranscript: String?
    public var audioPath: String?
    public var pastedToApp: String?
    public var processingMode: ProcessingMode
    public var status: DictationStatus
    public var errorMessage: String?
    public var updatedAt: Date
    public var hidden: Bool
    public var wordCount: Int
    public var derivedFromDictationId: UUID?
    public var processingOrigin: ProcessingOrigin
    public var wordTimestamps: [WordTimestamp]?
    public var speakerCount: Int?
    public var speakers: [SpeakerInfo]?
    public var diarizationSegments: [DiarizationSegmentRecord]?
    /// Display name of the STT model used for this transcription (e.g. "Whisper Large v3 Turbo").
    public var sttModelName: String?

    public enum ProcessingMode: String, Codable, Sendable {
        case raw
        case clean

        /// Override default RawRepresentable init to handle deprecated mode values.
        /// Without this, `ProcessingMode(rawValue: "formal")` returns nil and callers
        /// fall back to `.raw`, silently disabling processing for upgraded users.
        public init?(rawValue: String) {
            switch rawValue {
            case "raw": self = .raw
            case "clean", "formal", "email", "code": self = .clean
            default: return nil
            }
        }

        public init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: rawValue) ?? .raw
        }
    }

    public enum DictationStatus: String, Codable, Sendable {
        case recording
        case processing
        case completed
        case error
    }

    public enum ProcessingOrigin: String, Codable, Sendable {
        case original
        case reprocessed
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        durationMs: Int,
        rawTranscript: String,
        cleanTranscript: String? = nil,
        audioPath: String? = nil,
        pastedToApp: String? = nil,
        processingMode: ProcessingMode = .raw,
        status: DictationStatus = .completed,
        errorMessage: String? = nil,
        updatedAt: Date = Date(),
        hidden: Bool = false,
        wordCount: Int = 0,
        derivedFromDictationId: UUID? = nil,
        processingOrigin: ProcessingOrigin = .original,
        wordTimestamps: [WordTimestamp]? = nil,
        speakerCount: Int? = nil,
        speakers: [SpeakerInfo]? = nil,
        diarizationSegments: [DiarizationSegmentRecord]? = nil,
        sttModelName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationMs = durationMs
        self.rawTranscript = rawTranscript
        self.cleanTranscript = cleanTranscript
        self.audioPath = audioPath
        self.pastedToApp = pastedToApp
        self.processingMode = processingMode
        self.status = status
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
        self.hidden = hidden
        self.wordCount = wordCount
        self.derivedFromDictationId = derivedFromDictationId
        self.processingOrigin = processingOrigin
        self.wordTimestamps = wordTimestamps
        self.speakerCount = speakerCount
        self.speakers = speakers
        self.diarizationSegments = diarizationSegments
        self.sttModelName = sttModelName
    }
}

public extension Dictation.ProcessingMode {
    var usesDeterministicPipeline: Bool {
        self != .raw
    }

    var displayName: String {
        switch self {
        case .raw:
            return "Raw"
        case .clean:
            return "AI Processed"
        }
    }

}

public extension Dictation {
    /// Whether this dictation has been enriched with speaker diarization data.
    var hasSpeakerData: Bool {
        guard let count = speakerCount, count > 0 else { return false }
        return speakers != nil && !(speakers?.isEmpty ?? true)
    }
}

extension Dictation: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "dictations"

    public enum Columns: String, ColumnExpression {
        case id, createdAt, durationMs, rawTranscript, cleanTranscript
        case audioPath, pastedToApp, processingMode, status, errorMessage, updatedAt
        case hidden, wordCount
        case derivedFromDictationId, processingOrigin, wordTimestamps
        case speakerCount, speakers, diarizationSegments
        case sttModelName
    }
}
