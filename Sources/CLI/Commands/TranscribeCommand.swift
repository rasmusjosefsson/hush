import ArgumentParser
import Foundation
import HushCore

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio/video file."
    )

    @Argument(help: "Path to audio/video file to transcribe.")
    var input: String

    @Flag(help: "Enable speaker diarization.")
    var diarize: Bool = false

    func run() async throws {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)

        let db = try DatabaseManager()
        let transcriptionRepo = TranscriptionRepository(dbQueue: db.dbQueue)
        let customWordRepo = CustomWordRepository(dbQueue: db.dbQueue)
        let snippetRepo = TextSnippetRepository(dbQueue: db.dbQueue)
        let sttClient = FluidAudioClient()
        let audioProcessor = AudioProcessor()

        let diarizationService: DiarizationService? = diarize ? DiarizationService() : nil

        let service = TranscriptionService(
            audioProcessor: audioProcessor,
            sttClient: sttClient,
            transcriptionRepo: transcriptionRepo,
            customWordRepo: customWordRepo,
            snippetRepo: snippetRepo,
            diarizationService: diarizationService
        )

        let fileURL = URL(fileURLWithPath: trimmedInput)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("Error: File not found: \(trimmedInput)")
            throw ExitCode.failure
        }

        print("Transcribing \(fileURL.lastPathComponent)...")
        let result = try await service.transcribe(fileURL: fileURL) { progress in
            switch progress {
            case .converting:
                print("  Converting audio...")
            case .transcribing(let percent):
                print("  Transcribing... \(percent)%")
            case .identifyingSpeakers:
                print("  Identifying speakers...")
            default:
                break
            }
        }

        print("\n--- Transcript ---")
        print(result.cleanTranscript ?? result.rawTranscript ?? "(empty)")

        if let speakers = result.speakers, !speakers.isEmpty {
            print("\nSpeakers: \(speakers.map(\.label).joined(separator: ", "))")
        }

        print("\nDuration: \(result.durationMs.map { "\($0 / 1000)s" } ?? "unknown")")
        print("Status: \(result.status.rawValue)")
    }
}
