import AppKit
import OSLog
import HushCore
import HushViewModels
import HushUI

@MainActor
final class DictationFlowCoordinator {
    // MARK: - Public Interface

    var isDictationActive: Bool { overlayController != nil }
    var isIdlePillVisible: Bool { idlePillController != nil }
    var hotkeyManager: HotkeyManager?

    // MARK: - Dependencies

    private let dictationService: DictationService
    private let clipboardService: ClipboardServiceProtocol
    private let dictationRepo: DictationRepository
    private let settingsViewModel: SettingsViewModel
    private let onMenuBarIconUpdate: (BreathWaveIcon.MenuBarState) -> Void
    private let onHistoryReload: () -> Void

    // MARK: - State Machine

    private var stateMachine = DictationFlowStateMachine()
    private let dictationLog = Logger(subsystem: "com.hush.app", category: "DictationFlow")

    // MARK: - UI Resources

    private var overlayController: DictationOverlayController?
    private var overlayViewModel: DictationOverlayViewModel?
    private var idlePillController: IdlePillController?
    private var readyDismissTimer: DispatchWorkItem?
    private var recordingTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var cancelCountdownTask: Task<Void, Never>?
    private var stopCountdownTask: Task<Void, Never>?
    private var displayDismissTask: Task<Void, Never>?

    // MARK: - Flow Context

    private var currentDictation: Dictation?

    // MARK: - Init

    init(
        dictationService: DictationService,
        clipboardService: ClipboardServiceProtocol,
        dictationRepo: DictationRepository,
        settingsViewModel: SettingsViewModel,
        onMenuBarIconUpdate: @escaping (BreathWaveIcon.MenuBarState) -> Void,
        onHistoryReload: @escaping () -> Void
    ) {
        self.dictationService = dictationService
        self.clipboardService = clipboardService
        self.dictationRepo = dictationRepo
        self.settingsViewModel = settingsViewModel
        self.onMenuBarIconUpdate = onMenuBarIconUpdate
        self.onHistoryReload = onHistoryReload
    }

    // MARK: - Public Methods

    func showIdlePill() {
        guard settingsViewModel.showIdlePill else { return }
        guard idlePillController == nil else { return }
        guard overlayController == nil else { return }
        let vm = IdlePillViewModel()
        vm.onStartDictation = { [weak self] in
            self?.startDictation(mode: .persistent, trigger: .pillClick)
        }
        let controller = IdlePillController(viewModel: vm)
        controller.show(position: settingsViewModel.overlayPosition)
        idlePillController = controller
    }

    func hideIdlePill() {
        idlePillController?.hide()
        idlePillController = nil
    }

    func showReadyPill() {
        sendEvent(.readyPillRequested)
    }

    func startDictation(
        mode: FnKeyStateMachine.RecordingMode,
        trigger: DictationTrigger = .hotkey
    ) {
        sendEvent(.startRequested(mode: mode))
    }

    func stopDictation() {
        // Hold-to-talk always stops immediately — no undo window
        if case .recording(.holdToTalk) = stateMachine.state {
            sendEvent(.stopRequested)
            return
        }

        if settingsViewModel.stopOnlyViaUI {
            // Immediate stop — user explicitly clicked the UI stop button
            sendEvent(.stopRequested)
        } else {
            // Stop with 5-second undo window (persistent sessions only)
            sendEvent(.stopWithUndoRequested)
        }
    }

    func cancelDictation(reason: DictationCancelReason = .ui) {
        let flowReason: DictationFlowCancelReason = reason == .ui ? .ui : .escape
        sendEvent(.cancelRequested(reason: flowReason))
    }

    func dismissOverlayIfError() {
        switch stateMachine.state {
        case .finishing(let outcome):
            switch outcome {
            case .error, .noSpeech, .pasteFailedCopied:
                sendEvent(.dismissRequested)
            case .success:
                break
            }
        default:
            break
        }
    }

    // MARK: - State Machine Core

    private func sendEvent(_ event: DictationFlowEvent) {
        let oldState = stateMachine.state
        let effects = stateMachine.handle(event)

        if !effects.isEmpty {
            dictationLog.notice(
                "flow_transition gen=\(self.stateMachine.generation) \(self.describeState(oldState), privacy: .public) → \(self.describeState(self.stateMachine.state), privacy: .public) on \(String(describing: event), privacy: .public)"
            )
        }

        executeEffects(effects)
    }

    // MARK: - Effect Executor

    private func executeEffects(_ effects: [DictationFlowEffect]) {
        for effect in effects {
            executeEffect(effect)
        }
    }

    private func executeEffect(_ effect: DictationFlowEffect) {
        switch effect {

        case .showReadyPill:
            overlayController?.hide()
            overlayController = nil
            overlayViewModel = nil

            let vm = DictationOverlayViewModel()
            vm.onCancel = { [weak self] in self?.cancelDictation() }
            vm.onStop = { [weak self] in self?.stopDictation() }
            vm.onUndo = { [weak self] in self?.sendEvent(.undoRequested) }
            vm.onDismiss = { [weak self] in self?.sendEvent(.dismissRequested) }
            vm.state = .ready
            overlayViewModel = vm

            let controller = DictationOverlayController(viewModel: vm)
            controller.show(position: settingsViewModel.overlayPosition)
            overlayController = controller

        case .rescheduleReadyDismissTimer:
            readyDismissTimer?.cancel()
            let gen = stateMachine.generation
            let timer = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.sendEvent(.readyPillTimedOut(generation: gen))
                }
            }
            readyDismissTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(FnKeyStateMachine.tapThresholdMs * 2), execute: timer)

        case .showRecordingOverlay(let mode):
            let vm: DictationOverlayViewModel
            let resuming: Bool
            if let existingVM = overlayViewModel {
                vm = existingVM
                // Resuming from a countdown state — keep elapsed time
                if case .cancelled = existingVM.state {
                    resuming = true
                } else {
                    resuming = false
                }
            } else {
                vm = DictationOverlayViewModel()
                vm.onCancel = { [weak self] in self?.cancelDictation() }
                vm.onStop = { [weak self] in self?.stopDictation() }
                vm.onUndo = { [weak self] in self?.sendEvent(.undoRequested) }
                vm.onDismiss = { [weak self] in self?.sendEvent(.dismissRequested) }
                overlayViewModel = vm

                let controller = DictationOverlayController(viewModel: vm)
                controller.show(position: settingsViewModel.overlayPosition)
                overlayController = controller
                resuming = false
            }
            vm.recordingMode = mode
            vm.state = .recording
            if resuming {
                vm.resumeTimer()
            } else {
                vm.startTimer()
                if settingsViewModel.dictationSoundEffects {
                    SoundManager.shared.play(.recordStart)
                }
            }

        case .showProcessingState:
            overlayViewModel?.stopTimer()
            overlayViewModel?.state = .processing

        case .showCancelCountdown:
            overlayViewModel?.stopTimer()
            overlayViewModel?.cancelTimeRemaining = 5.0
            overlayViewModel?.state = .cancelled(timeRemaining: 5.0)

        case .showSuccess:
            overlayViewModel?.state = .success

        case .showNoSpeech:
            if let vm = overlayViewModel {
                vm.noSpeechProgress = 1.0
                vm.state = .noSpeech
            }

        case .showError(let message):
            overlayViewModel?.state = .error(message)

        case .hideOverlay:
            overlayController?.hide()
            overlayController = nil
            overlayViewModel = nil

        case .dismissReadyPill:
            overlayController?.hide()
            overlayController = nil
            overlayViewModel = nil

        case .showIdlePill:
            showIdlePill()

        case .hideIdlePill:
            hideIdlePill()

        case .checkEntitlements:
            // No licensing — always grant
            let gen = stateMachine.generation
            sendEvent(.entitlementsGranted(generation: gen))

        case .startRecording(let mode):
            let gen = stateMachine.generation
            recordingTask = Task { @MainActor in
                do {
                    try await self.dictationService.startRecording()
                    guard !Task.isCancelled else { return }
                    self.sendEvent(.recordingStarted(generation: gen))

                    let (autoStopEnabled, silenceDelay) = (self.settingsViewModel.silenceAutoStop, self.settingsViewModel.silenceDelay)
                    let silenceThreshold: Float = 0.03
                    var lastNonSilenceAt = Date()
                    var didAutoStop = false

                    while !Task.isCancelled,
                          case .recording = await self.dictationService.state {
                        let level = await self.dictationService.audioLevel
                        self.overlayViewModel?.audioLevel = level

                        if autoStopEnabled {
                            let now = Date()
                            if level >= silenceThreshold {
                                lastNonSilenceAt = now
                            } else if !didAutoStop, now.timeIntervalSince(lastNonSilenceAt) >= silenceDelay {
                                didAutoStop = true
                                self.stopDictation()
                                break
                            }
                        }

                        try? await Task.sleep(for: .milliseconds(50))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.sendEvent(.startFailed(generation: gen, message: error.localizedDescription))
                }
            }

        case .stopRecordingAndTranscribe:
            let gen = stateMachine.generation
            actionTask = Task { @MainActor in
                do {
                    let dictation = try await self.dictationService.stopRecording()
                    guard !Task.isCancelled else { return }
                    self.currentDictation = dictation
                    self.sendEvent(.transcriptionCompleted(generation: gen))
                } catch where self.isNoSpeechError(error) {
                    guard !Task.isCancelled else { return }
                    self.sendEvent(.transcriptionFailedNoSpeech(generation: gen))
                } catch {
                    guard !Task.isCancelled else { return }
                    self.sendEvent(.transcriptionFailed(generation: gen, message: error.localizedDescription))
                }
            }

        case .cancelRecording(let reason):
            let cancelReason: DictationCancelReason = reason == .escape ? .escape : .ui
            Task {
                await self.dictationService.cancelRecording(reason: cancelReason)
            }

        case .confirmCancel:
            Task {
                await self.dictationService.confirmCancel()
            }

        case .undoCancelAndTranscribe:
            let gen = stateMachine.generation
            actionTask = Task { @MainActor in
                do {
                    let dictation = try await self.dictationService.undoCancel()
                    guard !Task.isCancelled else { return }
                    self.currentDictation = dictation
                    self.sendEvent(.transcriptionCompleted(generation: gen))
                } catch where self.isNoSpeechError(error) {
                    guard !Task.isCancelled else { return }
                    self.sendEvent(.transcriptionFailedNoSpeech(generation: gen))
                } catch {
                    guard !Task.isCancelled else { return }
                    self.sendEvent(.transcriptionFailed(generation: gen, message: error.localizedDescription))
                }
            }

        case .transcribePausedAudio:
            let gen = stateMachine.generation
            actionTask = Task { @MainActor in
                do {
                    let dictation = try await self.dictationService.transcribePausedAudio()
                    guard !Task.isCancelled else { return }
                    self.currentDictation = dictation
                    self.sendEvent(.transcriptionCompleted(generation: gen))
                } catch where self.isNoSpeechError(error) {
                    guard !Task.isCancelled else { return }
                    self.sendEvent(.transcriptionFailedNoSpeech(generation: gen))
                } catch {
                    guard !Task.isCancelled else { return }
                    self.sendEvent(.transcriptionFailed(generation: gen, message: error.localizedDescription))
                }
            }

        case .resignKeyWindow:
            overlayController?.resignKeyWindow()

        case .pasteTranscript:
            let gen = stateMachine.generation
            guard let dictation = currentDictation else {
                sendEvent(.pasteFailed(generation: gen, message: "No transcription available."))
                return
            }
            let transcript = dictation.cleanTranscript ?? dictation.rawTranscript
            actionTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }

                do {
                    try await self.clipboardService.pasteText(transcript + " ")
                    guard !Task.isCancelled else { return }

                    if let pastedToApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                        self.currentDictation?.pastedToApp = pastedToApp
                        self.currentDictation?.updatedAt = Date()
                        if let d = self.currentDictation {
                            try? self.dictationRepo.save(d)
                        }
                    }

                    self.sendEvent(.pasteSucceeded(generation: gen))
                } catch {
                    guard !Task.isCancelled else { return }
                    await self.clipboardService.copyToClipboard(transcript)
                    self.sendEvent(.pasteFailed(generation: gen, message: "Copied to clipboard. Press Cmd+V."))
                }
            }

        case .reloadHistory:
            onHistoryReload()
            currentDictation = nil

        case .updateMenuBar(let menuBarState):
            let iconState: BreathWaveIcon.MenuBarState = switch menuBarState {
            case .idle: .idle
            case .recording: .recording
            case .processing: .processing
            }
            onMenuBarIconUpdate(iconState)

        case .resetHotkeyStateMachine:
            hotkeyManager?.resetToIdle()

        case .notifyHotkeyCancelledByUI:
            hotkeyManager?.notifyCancelledByUI()

        case .presentEntitlementsAlert:
            break // No licensing

        case .startReadyDismissTimer:
            readyDismissTimer?.cancel()
            let gen = stateMachine.generation
            let timer = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.sendEvent(.readyPillTimedOut(generation: gen))
                }
            }
            readyDismissTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(FnKeyStateMachine.tapThresholdMs * 2), execute: timer)

        case .cancelReadyDismissTimer:
            readyDismissTimer?.cancel()
            readyDismissTimer = nil

        case .startCancelCountdown:
            let gen = stateMachine.generation
            cancelCountdownTask = Task { @MainActor in
                for i in stride(from: 4.0, through: 0, by: -1) {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                    self.overlayViewModel?.cancelTimeRemaining = i
                }
                guard !Task.isCancelled else { return }
                self.sendEvent(.cancelCountdownExpired(generation: gen))
            }

        case .cancelCancelCountdown:
            cancelCountdownTask?.cancel()
            cancelCountdownTask = nil

        case .showStopCountdown:
            overlayViewModel?.stopTimer()
            overlayViewModel?.cancelTimeRemaining = 5.0
            overlayViewModel?.state = .cancelled(timeRemaining: 5.0)

        case .startStopCountdown:
            let gen = stateMachine.generation
            stopCountdownTask = Task { @MainActor in
                for i in stride(from: 4.0, through: 0, by: -1) {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                    self.overlayViewModel?.cancelTimeRemaining = i
                }
                guard !Task.isCancelled else { return }
                self.sendEvent(.stopCountdownExpired(generation: gen))
            }

        case .cancelStopCountdown:
            stopCountdownTask?.cancel()
            stopCountdownTask = nil

        case .pauseRecording:
            Task {
                await self.dictationService.pauseRecording()
            }

        case .resumeRecording(let mode):
            let gen = stateMachine.generation
            recordingTask = Task { @MainActor in
                do {
                    try await self.dictationService.resumeRecording()
                    guard !Task.isCancelled else { return }

                    // Resume audio level monitoring loop
                    let (autoStopEnabled, silenceDelay) = (self.settingsViewModel.silenceAutoStop, self.settingsViewModel.silenceDelay)
                    let silenceThreshold: Float = 0.03
                    var lastNonSilenceAt = Date()
                    var didAutoStop = false

                    while !Task.isCancelled,
                          case .recording = await self.dictationService.state {
                        let level = await self.dictationService.audioLevel
                        self.overlayViewModel?.audioLevel = level

                        if autoStopEnabled {
                            let now = Date()
                            if level >= silenceThreshold {
                                lastNonSilenceAt = now
                            } else if !didAutoStop, now.timeIntervalSince(lastNonSilenceAt) >= silenceDelay {
                                didAutoStop = true
                                self.stopDictation()
                                break
                            }
                        }

                        try? await Task.sleep(for: .milliseconds(50))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.sendEvent(.startFailed(generation: gen, message: error.localizedDescription))
                }
            }
            // Re-arm hotkey state machine so Fn key gestures work
            hotkeyManager?.resumeRecording(mode: mode)
            // Resume the elapsed timer without resetting
            overlayViewModel?.resumeTimer()

        case .startDisplayDismissTimer(let seconds):
            displayDismissTask?.cancel()
            let gen = stateMachine.generation
            displayDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
                guard !Task.isCancelled else { return }
                self.sendEvent(.displayDismissExpired(generation: gen))
            }

        case .cancelAllTimers:
            readyDismissTimer?.cancel()
            readyDismissTimer = nil
            cancelCountdownTask?.cancel()
            cancelCountdownTask = nil
            stopCountdownTask?.cancel()
            stopCountdownTask = nil
            displayDismissTask?.cancel()
            displayDismissTask = nil

        case .cancelRecordingTask:
            recordingTask?.cancel()
            recordingTask = nil

        case .cancelActionTask:
            actionTask?.cancel()
            actionTask = nil
        }
    }

    // MARK: - Helpers

    private func isNoSpeechError(_ error: Error) -> Bool {
        if let e = error as? DictationServiceError, e == .emptyTranscript { return true }
        if let e = error as? AudioProcessorError, case .insufficientSamples = e { return true }
        return false
    }

    private func describeState(_ state: DictationFlowState) -> String {
        switch state {
        case .idle: return "idle"
        case .ready: return "ready"
        case .checkingEntitlements: return "checkingEntitlements"
        case .startingService: return "startingService"
        case .recording: return "recording"
        case .pendingStop: return "pendingStop"
        case .processing: return "processing"
        case .cancelCountdown: return "cancelCountdown"
        case .stopCountdown: return "stopCountdown"
        case .finishing(let outcome):
            switch outcome {
            case .success: return "finishing.success"
            case .pasteFailedCopied: return "finishing.pasteFailed"
            case .noSpeech: return "finishing.noSpeech"
            case .error: return "finishing.error"
            }
        }
    }
}
