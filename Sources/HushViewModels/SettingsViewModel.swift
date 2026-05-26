import AppKit
import Foundation
import HushCore
import OSLog

@MainActor
@Observable
public final class SettingsViewModel {
    public enum LocalModelStatus: Equatable {
        case unknown
        case checking
        case ready
        case notLoaded
        case notDownloaded
        case repairing
        case failed
    }

    public struct InputDeviceItem: Identifiable, Equatable, Hashable {
        public let id: UInt32
        public let name: String
        public let isDefault: Bool
    }

    // General
    public var launchAtLogin: Bool {
        didSet {
            guard !isApplyingLaunchAtLoginState else { return }
            applyLaunchAtLoginChange(launchAtLogin)
        }
    }
    public var launchAtLoginDetail: String = ""
    public var launchAtLoginError: String?
    public var menuBarOnlyMode: Bool {
        didSet {
            defaults.set(menuBarOnlyMode, forKey: AppPreferences.menuBarOnlyModeKey)
            NotificationCenter.default.post(name: Notification.Name("hush.menuBarOnlyModeDidChange"), object: nil)
        }
    }
    public var showIdlePill: Bool {
        didSet {
            defaults.set(showIdlePill, forKey: "showIdlePill")
            NotificationCenter.default.post(name: Notification.Name("hush.showIdlePillDidChange"), object: nil)
        }
    }
    public var overlayPosition: OverlayPosition {
        didSet {
            defaults.set(overlayPosition.rawValue, forKey: "overlayPosition")
            NotificationCenter.default.post(name: Notification.Name("hush.overlayPositionDidChange"), object: nil)
        }
    }

    // Dictation
    public var hotkeyTrigger: HotkeyTrigger {
        didSet {
            hotkeyTrigger.save(to: defaults)
            NotificationCenter.default.post(name: Notification.Name("hush.hotkeyTriggerDidChange"), object: nil)
        }
    }
    public var silenceAutoStop: Bool {
        didSet { defaults.set(silenceAutoStop, forKey: "silenceAutoStop") }
    }
    public var silenceDelay: Double {
        didSet { defaults.set(silenceDelay, forKey: "silenceDelay") }
    }
    public var stopOnlyViaUI: Bool {
        didSet {
            defaults.set(stopOnlyViaUI, forKey: "stopOnlyViaUI")
            NotificationCenter.default.post(name: Notification.Name("hush.stopOnlyViaUIDidChange"), object: nil)
        }
    }

    public var dictationSoundEffects: Bool {
        didSet { defaults.set(dictationSoundEffects, forKey: "dictationSoundEffects") }
    }

    public var captureSystemAudio: Bool {
        didSet {
            defaults.set(captureSystemAudio, forKey: "captureSystemAudio")
            // If enabling, check permission and prompt if needed
            if captureSystemAudio, !screenRecordingGranted {
                if #available(macOS 15, *) {
                    CGRequestScreenCaptureAccess()
                } else {
                    openScreenRecordingSettings()
                }
                // Refresh permission status after a short delay
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    self.refreshPermissions()
                }
            }
        }
    }

    // Input device
    public var availableInputDevices: [InputDeviceItem] = []
    public var selectedInputDeviceID: UInt32 = 0 {
        didSet {
            if selectedInputDeviceID == 0 {
                defaults.removeObject(forKey: "preferredInputDeviceID")
            } else {
                defaults.set(Int(selectedInputDeviceID), forKey: "preferredInputDeviceID")
            }
        }
    }
    public var defaultInputDeviceName: String? {
        guard !availableInputDevices.isEmpty else { return nil }
        return availableInputDevices.first(where: \.isDefault)?.name
    }

    // Processing
    public var processingMode: String {
        didSet {
            guard Dictation.ProcessingMode(rawValue: processingMode) != nil else {
                let fallback = Dictation.ProcessingMode.raw.rawValue
                processingMode = fallback
                defaults.set(fallback, forKey: "processingMode")
                return
            }
            defaults.set(processingMode, forKey: "processingMode")
        }
    }
    public var customWordCount: Int = 0
    public var snippetCount: Int = 0

    // Storage
    public var saveDictationHistory: Bool {
        didSet { defaults.set(saveDictationHistory, forKey: "saveDictationHistory") }
    }
    public var saveAudioRecordings: Bool {
        didSet { defaults.set(saveAudioRecordings, forKey: "saveAudioRecordings") }
    }
    public var saveTranscriptionAudio: Bool {
        didSet { defaults.set(saveTranscriptionAudio, forKey: "saveTranscriptionAudio") }
    }

    // Permission status
    public var microphoneGranted = false
    public var accessibilityGranted = false
    public var screenRecordingGranted = false
    public var microphoneResetMessage: String?
    public var accessibilityResetMessage: String?

    // Stats
    public var dictationCount = 0

    // Local model status
    public var parakeetStatus: LocalModelStatus = .unknown
    public var parakeetStatusDetail: String = "Not checked yet."
    public var parakeetRepairing = false
    /// 0.0–1.0 download/warmup progress, nil when not downloading.
    public var modelDownloadProgress: Double?
    public var availableModels: [ModelInfo] = []
    public var selectedModelID: String = ""

    private var permissionService: PermissionServiceProtocol?
    private var dictationRepo: DictationRepositoryProtocol?
    private var transcriptionRepo: TranscriptionRepositoryProtocol?
    private var customWordRepo: CustomWordRepositoryProtocol?
    private var snippetRepo: TextSnippetRepositoryProtocol?
    private var launchAtLoginService: LaunchAtLoginControlling?
    private var sttClient: STTClientProtocol?
    private var modelRegistry: ModelRegistry?
    private let defaults: UserDefaults
    private let isSpeechModelCached: @Sendable () -> Bool
    private var isApplyingLaunchAtLoginState = false
    @ObservationIgnored
    private var appActivateObserver: Any?
    private let logger = Logger(subsystem: "com.hush.viewmodels", category: "SettingsViewModel")

    public init(
        defaults: UserDefaults = .standard,
        isSpeechModelCached: @escaping @Sendable () -> Bool = { FluidAudioClient.isModelCached() }
    ) {
        self.defaults = defaults
        self.isSpeechModelCached = isSpeechModelCached
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        menuBarOnlyMode = AppPreferences.isMenuBarOnlyModeEnabled(defaults: defaults)
        showIdlePill = defaults.object(forKey: "showIdlePill") as? Bool ?? true
        overlayPosition = OverlayPosition(rawValue: defaults.string(forKey: "overlayPosition") ?? "") ?? .bottom
        hotkeyTrigger = HotkeyTrigger.current(defaults: defaults)
        silenceAutoStop = defaults.bool(forKey: "silenceAutoStop")
        let delay = defaults.double(forKey: "silenceDelay")
        silenceDelay = delay == 0 ? 2.0 : delay
        stopOnlyViaUI = defaults.bool(forKey: "stopOnlyViaUI")
        dictationSoundEffects = defaults.object(forKey: "dictationSoundEffects") as? Bool ?? true
        captureSystemAudio = defaults.object(forKey: "captureSystemAudio") as? Bool ?? false
        processingMode = Self.normalizedProcessingMode(defaults.string(forKey: "processingMode"))
        saveDictationHistory = defaults.object(forKey: "saveDictationHistory") as? Bool ?? true
        saveAudioRecordings = defaults.object(forKey: "saveAudioRecordings") as? Bool ?? true
        saveTranscriptionAudio = defaults.object(forKey: "saveTranscriptionAudio") as? Bool ?? true
    }

    deinit {
        if let observer = appActivateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func configure(
        permissionService: PermissionServiceProtocol,
        dictationRepo: DictationRepositoryProtocol,
        transcriptionRepo: TranscriptionRepositoryProtocol? = nil,
        launchAtLoginService: LaunchAtLoginControlling? = nil,
        customWordRepo: CustomWordRepositoryProtocol? = nil,
        snippetRepo: TextSnippetRepositoryProtocol? = nil,
        sttClient: STTClientProtocol? = nil,
        modelRegistry: ModelRegistry? = nil
    ) {
        self.permissionService = permissionService
        self.dictationRepo = dictationRepo
        self.transcriptionRepo = transcriptionRepo
        self.launchAtLoginService = launchAtLoginService
        self.customWordRepo = customWordRepo
        self.snippetRepo = snippetRepo
        self.sttClient = sttClient
        self.modelRegistry = modelRegistry
        if let modelRegistry {
            availableModels = modelRegistry.allModels
            selectedModelID = modelRegistry.selectedModel.id
        }
        refreshLaunchAtLoginStatus()
        refreshPermissions()
        refreshStats()
        refreshModelStatus()
        refreshInputDevices()

        if let existing = appActivateObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        appActivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }
    }

    public func refreshLaunchAtLoginStatus() {
        guard let service = launchAtLoginService else {
            launchAtLoginDetail = ""
            launchAtLoginError = nil
            return
        }
        applyLaunchAtLoginStatus(service.currentStatus())
        launchAtLoginError = nil
    }

    public func refreshPermissions() {
        microphoneResetMessage = nil
        accessibilityResetMessage = nil
        Task {
            if let service = permissionService {
                let micStatus = await service.checkMicrophonePermission()
                let accStatus = service.checkAccessibilityPermission()
                let screenStatus = service.checkScreenRecordingPermission()
                microphoneGranted = micStatus == .granted
                accessibilityGranted = accStatus
                screenRecordingGranted = screenStatus
            }
        }
    }

    public func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    public func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    public func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    public func reRequestScreenRecording() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.hush.app"
        Task.detached { [weak self] in
            // Reset stale TCC entry so the system will prompt fresh
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "ScreenCapture", bundleID]
            try? process.run()
            process.waitUntilExit()

            await MainActor.run {
                _ = self?.permissionService?.requestScreenRecordingPermission()
                // Refresh after a delay to pick up the new status
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    self?.refreshPermissions()
                }
            }
        }
    }

    public func resetMicrophonePermission() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.hush.app"
        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Microphone", bundleID]
            let pipe = Pipe()
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let succeeded = process.terminationStatus == 0
                let errorString: String? = succeeded ? nil : {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    return String(data: data, encoding: .utf8) ?? "Unknown error"
                }()

                await MainActor.run {
                    if succeeded {
                        self?.microphoneResetMessage = "Permission reset. Restart the app to re-trigger the prompt."
                    } else {
                        self?.logger.error("tccutil reset failed: \(errorString ?? "", privacy: .public)")
                        self?.microphoneResetMessage = "Failed to reset microphone permission: \(errorString ?? "Unknown error")"
                    }
                }
            } catch {
                await MainActor.run {
                    self?.logger.error("Failed to run tccutil: \(error.localizedDescription, privacy: .public)")
                    self?.microphoneResetMessage = "Failed to reset microphone permission: \(error.localizedDescription)"
                }
            }
        }
    }

    public func reRequestMicrophone() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.hush.app"
        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Microphone", bundleID]
            try? process.run()
            process.waitUntilExit()

            await MainActor.run {
                Task {
                    _ = await self?.permissionService?.requestMicrophonePermission()
                    self?.refreshPermissions()
                }
            }
        }
    }

    public func reRequestAccessibility() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.hush.app"
        Task.detached { [weak self] in
            // First reset the stale TCC entry so the system will prompt fresh
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            try? process.run()
            process.waitUntilExit()

            await MainActor.run {
                // Now trigger the system accessibility prompt
                _ = self?.permissionService?.requestAccessibilityPermission(prompt: true)
                self?.refreshPermissions()
            }
        }
    }

    public func resetAccessibilityPermission() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.hush.app"
        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            let pipe = Pipe()
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let succeeded = process.terminationStatus == 0
                let errorString: String? = succeeded ? nil : {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    return String(data: data, encoding: .utf8) ?? "Unknown error"
                }()

                await MainActor.run {
                    if succeeded {
                        self?.accessibilityResetMessage = "Permission reset. Restart the app to re-trigger the prompt."
                    } else {
                        self?.logger.error("tccutil reset Accessibility failed: \(errorString ?? "", privacy: .public)")
                        self?.accessibilityResetMessage = "Failed to reset accessibility permission: \(errorString ?? "Unknown error")"
                    }
                }
            } catch {
                await MainActor.run {
                    self?.logger.error("Failed to run tccutil for Accessibility: \(error.localizedDescription, privacy: .public)")
                    self?.accessibilityResetMessage = "Failed to reset accessibility permission: \(error.localizedDescription)"
                }
            }
        }
    }

    public func resetOnboarding() {
        defaults.removeObject(forKey: OnboardingViewModel.onboardingCompletedKey)
        NotificationCenter.default.post(name: Notification.Name("hush.openOnboarding"), object: nil)
    }

    // MARK: - Diagnostics

    public var logFileExists: Bool {
        FileManager.default.fileExists(atPath: AppPaths.logsDir + "/hush.log")
    }

    public func openLogFile() {
        let path = AppPaths.logsDir + "/hush.log"
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: AppPaths.logsDir)
    }

    public func openLogFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: AppPaths.logsDir, isDirectory: true))
    }

    public func openAppSupportFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: AppPaths.appSupportDir, isDirectory: true))
    }

    public func refreshStats() {
        guard let repo = dictationRepo else { return }
        do { dictationCount = try repo.stats().visibleCount }
        catch { logger.error("Failed to load dictation stats: \(error.localizedDescription)") }
        do { customWordCount = try customWordRepo?.fetchAll().count ?? 0 }
        catch { logger.error("Failed to load custom word count: \(error.localizedDescription)") }
        do { snippetCount = try snippetRepo?.fetchAll().count ?? 0 }
        catch { logger.error("Failed to load snippet count: \(error.localizedDescription)") }
    }

    public func refreshInputDevices() {
        let devices = AudioDeviceManager.inputDevices()
        let defaultID = AudioDeviceManager.defaultInputDevice()
        availableInputDevices = devices.map { device in
            InputDeviceItem(
                id: device.id,
                name: device.name,
                isDefault: device.id == defaultID
            )
        }
        let stored = defaults.integer(forKey: "preferredInputDeviceID")
        let storedID = UInt32(max(stored, 0))
        // Reset to system default if stored device is no longer available
        if storedID > 0, !availableInputDevices.contains(where: { $0.id == storedID }) {
            selectedInputDeviceID = 0
        } else {
            selectedInputDeviceID = storedID
        }
    }

    public func refreshModelStatus() {
        guard let sttClient else {
            parakeetStatus = .unknown
            parakeetStatusDetail = "Unavailable in this runtime."
            return
        }

        parakeetStatus = .checking
        parakeetStatusDetail = "Checking model state..."

        let selectedEngine = modelRegistry?.selectedModel.engineType ?? .fluidAudio
        let selectedVariant = modelRegistry?.selectedModel.variant

        Task {
            let isReady = await sttClient.isReady()

            let isCachedOnDisk: Bool
            switch selectedEngine {
            case .fluidAudio:
                isCachedOnDisk = isSpeechModelCached()
            case .whisperKit:
                if let variant = selectedVariant {
                    isCachedOnDisk = WhisperKitClient.isModelCached(variant: variant)
                } else {
                    isCachedOnDisk = false
                }
            }

            await MainActor.run {
                if isReady {
                    self.parakeetStatus = .ready
                    self.parakeetStatusDetail = "Loaded in memory and ready."
                } else if isCachedOnDisk {
                    self.parakeetStatus = .notLoaded
                    self.parakeetStatusDetail = "Downloaded. Loads automatically when needed."
                } else {
                    self.parakeetStatus = .notDownloaded
                    self.parakeetStatusDetail = "Not downloaded yet."
                }
            }
        }
    }

    public func selectModel(id: String) {
        modelRegistry?.selectModel(id: id)
        selectedModelID = id
        Task {
            await sttClient?.shutdown()
            refreshModelStatus()
        }
    }

    public func repairParakeetModel() {
        guard let sttClient else { return }
        guard !parakeetRepairing else { return }
        parakeetRepairing = true
        parakeetStatus = .repairing
        parakeetStatusDetail = "Preparing speech model..."
        modelDownloadProgress = 0

        Task {
            do {
                try await sttClient.warmUp { [weak self] progressMessage in
                    Task { @MainActor [weak self] in
                        self?.parakeetStatusDetail = progressMessage
                        self?.modelDownloadProgress = Self.parseProgress(from: progressMessage)
                    }
                }

                await MainActor.run {
                    self.parakeetRepairing = false
                    self.modelDownloadProgress = nil
                    self.refreshModelStatus()
                }
            } catch {
                await MainActor.run {
                    self.parakeetRepairing = false
                    self.modelDownloadProgress = nil
                    self.parakeetStatus = .failed
                    self.parakeetStatusDetail = error.localizedDescription
                }
            }
        }
    }

    /// Extract a 0.0–1.0 fraction from progress strings like "Downloading... 42% (200/500 MB)"
    private static func parseProgress(from message: String) -> Double {
        // Match "NN%" in the message
        guard let range = message.range(of: #"(\d+)%"#, options: .regularExpression),
              let percent = Int(message[range].dropLast()) else {
            return 0
        }
        return Double(min(max(percent, 0), 100)) / 100.0
    }

    public var onDictationsCleared: (() -> Void)?

    public func clearAllDictations() {
        guard let repo = dictationRepo else { return }
        do { try repo.deleteAll() }
        catch { logger.error("Failed to delete all dictations error=\(error.localizedDescription, privacy: .public)") }
        let dir = AppPaths.dictationsDir
        if FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.removeItem(atPath: dir)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        refreshStats()
        onDictationsCleared?()
    }

    public func resetPrivateStatistics() {
        guard let repo = dictationRepo else { return }
        do { try repo.deleteHidden() }
        catch { logger.error("Failed to delete hidden dictations error=\(error.localizedDescription, privacy: .public)") }
        refreshStats()
        onDictationsCleared?()
    }

    private static func normalizedProcessingMode(_ rawValue: String?) -> String {
        guard let rawValue, Dictation.ProcessingMode(rawValue: rawValue) != nil else {
            return Dictation.ProcessingMode.raw.rawValue
        }
        return rawValue
    }

    private func applyLaunchAtLoginChange(_ enabled: Bool) {
        defaults.set(enabled, forKey: "launchAtLogin")
        launchAtLoginError = nil
        guard let service = launchAtLoginService else { return }
        do {
            let updatedStatus = try service.setEnabled(enabled)
            applyLaunchAtLoginStatus(updatedStatus)
        } catch {
            let fallbackStatus = service.currentStatus()
            applyLaunchAtLoginStatus(fallbackStatus)
            launchAtLoginError = error.localizedDescription
        }
    }

    private func applyLaunchAtLoginStatus(_ status: LaunchAtLoginStatus) {
        isApplyingLaunchAtLoginState = true
        launchAtLogin = status.isEnabled
        defaults.set(status.isEnabled, forKey: "launchAtLogin")
        isApplyingLaunchAtLoginState = false
        launchAtLoginDetail = status.detailText
    }
}
