import ArgumentParser
import Foundation
import HushCore

struct HealthCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "health",
        abstract: "Check system health: database and local models."
    )

    @Flag(name: .long, help: "Attempt to warm the Parakeet speech model.")
    var repairModels: Bool = false

    func run() async throws {
        print("Hush Health Check")
        print("=====================")
        print()

        // 1. Paths
        print("Paths:")
        print("  App Support: \(AppPaths.appSupportDir)")
        print("  Database:    \(AppPaths.databasePath)")
        print("  Temp:        \(AppPaths.tempDir)")
        print()

        // 2. Directories
        print("Directories:")
        do {
            try AppPaths.ensureDirectories()
            print("  All directories exist or created.")
        } catch {
            print("  ERROR: \(error.localizedDescription)")
        }
        print()

        // 3. Database
        print("Database:")
        let dbExists = FileManager.default.fileExists(atPath: AppPaths.databasePath)
        if dbExists {
            do {
                let dbManager = try DatabaseManager(path: AppPaths.databasePath)
                let dictationRepo = DictationRepository(dbQueue: dbManager.dbQueue)
                let transcriptionRepo = TranscriptionRepository(dbQueue: dbManager.dbQueue)

                let dictStats = try dictationRepo.stats()
                let transcriptions = try transcriptionRepo.fetchAll(limit: nil)

                print("  Status: OK")
                print("  Dictations: \(dictStats.totalCount)")
                print("  Transcriptions: \(transcriptions.count)")
            } catch {
                print("  Status: ERROR — \(error.localizedDescription)")
            }
        } else {
            print("  Status: Not created yet (will be created on first use)")
        }
        print()

        // 4. Local models
        print("Local Models:")
        let sttClient = FluidAudioClient()
        let isReady = await sttClient.isReady()
        let isCached = FluidAudioClient.isModelCached()

        if isReady {
            print("  Parakeet: Loaded and ready")
        } else if isCached {
            print("  Parakeet: Downloaded (loads on first use)")
        } else {
            print("  Parakeet: Not downloaded")
        }

        if repairModels {
            print()
            print("Warming up model...")
            do {
                try await sttClient.warmUp { message in
                    print("  \(message)")
                }
                print("  Model ready.")
            } catch {
                print("  Failed: \(error.localizedDescription)")
            }
        }
        await sttClient.shutdown()
        print()

        // 5. FFmpeg
        print("FFmpeg:")
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            print("  Status: Found at \(path)")
        } else {
            print("  Status: Not found (install via `brew install ffmpeg`)")
        }
        print()

        print("Done.")
    }
}
