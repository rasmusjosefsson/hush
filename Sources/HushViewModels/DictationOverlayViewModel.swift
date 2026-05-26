import Foundation
import HushCore

/// ViewModel for the dictation overlay
@MainActor
@Observable
public final class DictationOverlayViewModel {
    public enum SessionKind {
        case dictation
        case command
    }

    public enum OverlayState {
        case ready
        case recording
        case cancelled(timeRemaining: Double)
        case processing
        case success
        case noSpeech
        case error(String)
    }

    public var state: OverlayState = .recording
    public var sessionKind: SessionKind = .dictation
    public var recordingMode: FnKeyStateMachine.RecordingMode = .persistent
    public var audioLevel: Float = 0.0
    public var recordingElapsedSeconds: Int = 0
    public var isHovered: Bool = false
    public var hoverTooltip: String?
    public var isTopPosition: Bool = false
    /// Width of the notch camera cutout in points. When > 0, the recording UI splits
    /// into two pills flanking the camera gap. Set by the controller from NotchGeometry.
    public var notchGapWidth: CGFloat = 0
    /// Height of the notch (safeAreaInsets.top). Used to push single-pill content
    /// below the camera housing so the notch appears to "grow" downward.
    public var notchHeight: CGFloat = 0
    public var commandPromptText: String = "Speak your command..."
    public var commandSelectedText: String = ""

    public var onCancel: (() -> Void)?
    public var onStop: (() -> Void)?
    public var onUndo: (() -> Void)?
    public var onDismiss: (() -> Void)?

    /// Cancel countdown value (separate from state enum to avoid view reconstruction jank).
    public var cancelTimeRemaining: Double = 5.0

    /// No-speech progress bar: starts at 1.0, animates to 0.0 over 3 seconds.
    public var noSpeechProgress: CGFloat = 1.0

    private var timerTask: Task<Void, Never>?

    public init() {}

    public func startTimer() {
        recordingElapsedSeconds = 0
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                self.recordingElapsedSeconds += 1
            }
        }
    }

    public func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Resume timer without resetting elapsed time (used after undo cancel)
    public func resumeTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                self.recordingElapsedSeconds += 1
            }
        }
    }

    public var formattedElapsed: String {
        let minutes = recordingElapsedSeconds / 60
        let seconds = recordingElapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    public var commandSelectedCharacterCount: Int {
        commandSelectedText.count
    }

    public var commandSelectedPreview: String {
        let compact = commandSelectedText.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count <= 50 { return compact }
        return String(compact.prefix(47)) + "..."
    }

    /// Stable key for animating pill size transitions between states
    public var pillStateKey: String {
        switch state {
        case .ready: return "ready"
        case .recording:
            if sessionKind == .command { return "commandRecording" }
            return recordingMode == .holdToTalk ? "holdToTalk" : "recording"
        case .cancelled: return "cancelled"
        case .processing:
            return sessionKind == .command ? "commandProcessing" : "processing"
        case .success: return "success"
        case .noSpeech:
            return sessionKind == .command ? "commandNoSpeech" : "noSpeech"
        case .error: return "error"
        }
    }
}
