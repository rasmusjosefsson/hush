import CoreAudio
import Foundation
import HushCore

/// Service container: creates and wires up all dependencies.
@MainActor
final class AppEnvironment {
    let databaseManager: DatabaseManager
    let dictationRepo: DictationRepository
    let transcriptionRepo: TranscriptionRepository
    let customWordRepo: CustomWordRepository
    let snippetRepo: TextSnippetRepository
    let modelRegistry: ModelRegistry
    let sttDispatcher: STTDispatcher
    let audioProcessor: AudioProcessor
    let dictationService: DictationService
    let transcriptionService: TranscriptionService
    let diarizationService: DiarizationService
    let clipboardService: ClipboardService
    let exportService: ExportService
    let permissionService: PermissionService
    let accessibilityService: AccessibilityService
    let launchAtLoginService: LaunchAtLoginService

    init() throws {
        try AppPaths.ensureDirectories()

        // Check for crash report from previous session
        if let crashReport = CrashReporter.loadPendingReport() {
            FileLogger.shared.log(
                "Previous session crashed: \(crashReport.crashType) \(crashReport.name) at \(crashReport.timestamp)",
                level: .error,
                category: .crash
            )
            CrashReporter.deletePendingReport()
        }

        // Check for orphaned recording session
        if let orphaned = OrphanedSessionRecovery.check() {
            let audioCount = orphaned.availableAudioURLs.count
            FileLogger.shared.log(
                "Found orphaned recording session \(orphaned.sessionID.uuidString) from \(orphaned.startedAt) with \(audioCount) recoverable audio file(s) at \(orphaned.folderURL.path)",
                level: .warning,
                category: .recording
            )
        }

        // Database
        let dbPath = AppPaths.databasePath
        databaseManager = try DatabaseManager(path: dbPath)

        // Repositories
        dictationRepo = DictationRepository(dbQueue: databaseManager.dbQueue)
        transcriptionRepo = TranscriptionRepository(dbQueue: databaseManager.dbQueue)
        customWordRepo = CustomWordRepository(dbQueue: databaseManager.dbQueue)
        snippetRepo = TextSnippetRepository(dbQueue: databaseManager.dbQueue)

        // One-time cleanup on launch
        _ = try? dictationRepo.deleteEmpty()
        try? dictationRepo.clearMissingAudioPaths()

        // Services
        modelRegistry = ModelRegistry()
        sttDispatcher = STTDispatcher(
            registry: modelRegistry,
            backendFactory: STTDispatcher.defaultFactory()
        )
        audioProcessor = AudioProcessor(
            preferredDeviceID: {
                let stored = UserDefaults.standard.integer(forKey: "preferredInputDeviceID")
                return stored > 0 ? AudioDeviceID(stored) : nil
            },
            captureSystemAudio: {
                UserDefaults.standard.bool(forKey: "captureSystemAudio")
            }
        )
        clipboardService = ClipboardService()
        exportService = ExportService()
        permissionService = PermissionService()
        accessibilityService = AccessibilityService()
        launchAtLoginService = LaunchAtLoginService()

        let processingModeClosure: @Sendable () -> Dictation.ProcessingMode = {
            let raw = UserDefaults.standard.string(forKey: "processingMode")
            return Dictation.ProcessingMode(rawValue: raw ?? Dictation.ProcessingMode.raw.rawValue) ?? .raw
        }

        diarizationService = DiarizationService()

        dictationService = DictationService(
            audioProcessor: audioProcessor,
            sttClient: sttDispatcher,
            dictationRepo: dictationRepo,
            shouldSaveAudio: {
                UserDefaults.standard.object(forKey: "saveAudioRecordings") as? Bool ?? true
            },
            shouldSaveDictationHistory: {
                UserDefaults.standard.object(forKey: "saveDictationHistory") as? Bool ?? true
            },
            customWordRepo: customWordRepo,
            snippetRepo: snippetRepo,
            processingMode: processingModeClosure,
            diarizationService: diarizationService,
            selectedModelName: { [modelRegistry] in
                modelRegistry.selectedModel.name
            }
        )

        transcriptionService = TranscriptionService(
            audioProcessor: audioProcessor,
            sttClient: sttDispatcher,
            transcriptionRepo: transcriptionRepo,
            customWordRepo: customWordRepo,
            snippetRepo: snippetRepo,
            processingMode: processingModeClosure,
            diarizationService: diarizationService
        )
    }
}
