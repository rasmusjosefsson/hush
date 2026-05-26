import Cocoa
import Foundation
import HushCore
import OSLog

/// Manages system-wide hotkey detection via CGEvent tap.
/// Supports any single key as trigger: modifier keys (Fn, Control, Option, Shift, Command)
/// or regular key codes (F13, End, Home, etc.). See ADR-009.
/// Requires Accessibility permission.
public final class HotkeyManager {
    private static let logger = Logger(subsystem: "com.hush.app", category: "HotkeyManager")
    public var onStartRecording: ((FnKeyStateMachine.RecordingMode) -> Void)?
    public var onStopRecording: (() -> Void)?
    public var onCancelRecording: (() -> Void)?
    public var onReadyForSecondTap: (() -> Void)?
    public var onEscapeWhileIdle: (() -> Void)?

    /// When true, hotkey gestures cannot stop persistent recording.
    /// The user must click the UI stop button instead.
    public var persistentStopDisabled: Bool {
        get { stateMachine.persistentStopDisabled }
        set { stateMachine.persistentStopDisabled = newValue }
    }

    private let stateMachine = FnKeyStateMachine()
    private let trigger: HotkeyTrigger
    private let targetMask: CGEventFlags?
    private var eventTap: CFMachPort?
    private var holdTimer: DispatchWorkItem?
    private var runLoopSource: CFRunLoopSource?
    /// Retained reference to self passed to the CGEvent tap callback.
    /// Prevents use-after-free if the tap fires during deallocation.
    private var retainedSelf: Unmanaged<HotkeyManager>?
    /// The run loop the source was installed on, so stop() removes from the correct one.
    private var installedRunLoop: CFRunLoop?
    /// Edge detection: was the target modifier pressed in the previous event?
    private var targetModifierWasPressed = false
    /// Edge detection for keyCode triggers: true while the trigger key is physically held.
    private var triggerKeyIsPressed = false
    /// For chord triggers: true after a required modifier was released while the key was still held.
    /// Prevents double fnUp when the key is subsequently released.
    private var chordModifierReleased = false
    /// For multi-modifier triggers: true when all required modifiers are currently held.
    private var allModifiersHeld = false

    /// Bare-tap filtering: true until a non-Escape key is pressed while modifier is held.
    private var bareTap = true

    /// Mask of the 4 relevant modifier bits (⌃⌥⇧⌘) for chord matching.
    static let relevantModifierBits: UInt64 = HotkeyTrigger.relevantModifierBits

    /// Required modifier flags for `.chord` triggers, precomputed from `trigger.chordEventFlags`.
    private let requiredChordFlags: UInt64

    public init(trigger: HotkeyTrigger = .fn) {
        self.trigger = trigger
        self.targetMask = trigger.kind == .modifier ? Self.mask(for: trigger) : nil
        self.requiredChordFlags = trigger.chordEventFlags
    }

    deinit {
        // Inline cleanup — deinit is nonisolated, can't call @MainActor stop().
        // Safe because deinit guarantees exclusive access to self.
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource, let runLoop = installedRunLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        retainedSelf?.release()
        holdTimer?.cancel()
    }

    /// Start listening for key events. Requires Accessibility permission.
    public func start() -> Bool {
        // Guard against double-start: stop existing tap to prevent leaking it
        if eventTap != nil { stop() }

        var eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        if trigger.kind == .keyCode || trigger.kind == .chord {
            eventMask |= (1 << CGEventType.keyUp.rawValue)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(type: type, event: event)
            },
            userInfo: {
                let retained = Unmanaged.passRetained(self)
                self.retainedSelf = retained
                return retained.toOpaque()
            }()
        ) else {
            // tapCreate failed — release the retained reference to avoid a permanent leak.
            // Without this, deinit can never fire (the +1 prevents deallocation).
            retainedSelf?.release()
            retainedSelf = nil
            // Log the trust state so logs distinguish "permission not granted"
            // from a generic system error. AXIsProcessTrusted is read-only and
            // doesn't trigger a permission prompt (we pass `nil` options).
            let isTrusted = AXIsProcessTrusted()
            Self.logger.error(
                "hotkey_tap_create_failed accessibility_trusted=\(isTrusted, privacy: .public)"
            )
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let runLoop = CFRunLoopGetCurrent()
        installedRunLoop = runLoop
        CFRunLoopAddSource(runLoop, runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Sync gesture state at startup so a key already held when the app
        // launches isn't treated as a fresh trigger. Same path as disabled-tap
        // recovery — clears stale flags and pending timers. (upstream 21ba3d16)
        recoverFromDisabledTap()

        return true
    }

    /// Stop listening for key events
    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource, let runLoop = installedRunLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        // Balance the passRetained from start() to avoid leaking self
        retainedSelf?.release()
        retainedSelf = nil
        holdTimer?.cancel()
        eventTap = nil
        runLoopSource = nil
        installedRunLoop = nil
        targetModifierWasPressed = false
        triggerKeyIsPressed = false
        chordModifierReleased = false
        allModifiersHeld = false
        bareTap = true
        stateMachine.reset()
    }

    // MARK: - Private

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS can disable our tap if the callback is slow or for user-input conditions.
        // Re-enable it to prevent the hotkey from silently dying.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            recoverFromDisabledTap()
            return Unmanaged.passUnretained(event)
        }

        switch trigger.kind {
        case .modifier:
            return handleModifierEvent(type: type, event: event)
        case .keyCode:
            return handleKeyCodeEvent(type: type, event: event)
        case .chord:
            return handleChordEvent(type: type, event: event)
        case .multiModifier:
            return handleMultiModifierEvent(type: type, event: event)
        }
    }

    /// Resync gesture state after macOS disabled and we re-enabled the event tap.
    ///
    /// During the disabled window we may have missed keyUp/flagsChanged events,
    /// so stale `triggerKeyIsPressed`/`allModifiersHeld`/`chordModifierReleased`
    /// flags can cause the next legitimate keyDown to be swallowed as a repeat
    /// or treat a held key as a fresh trigger. We also need to cancel any pending
    /// hold timer that would fire stale work after recovery.
    ///
    /// If an active dictation is in flight (`.persistent` or `.holdToTalk`),
    /// we preserve all gesture flags AND the state machine so the user can still
    /// stop the recording via the usual mechanism:
    ///   - hold-to-talk: needs `triggerKeyIsPressed=true` so the eventual keyUp
    ///     fires stop; clearing it would orphan the recording.
    ///   - persistent: next deliberate keyDown stops the recording; resetting
    ///     the state machine would lose that affordance.
    /// We still cancel any pending hold timer (it's tied to the just-aborted
    /// gesture, not the active recording).
    private func recoverFromDisabledTap() {
        holdTimer?.cancel()
        holdTimer = nil

        let activeRecording = (stateMachine.state == .persistent || stateMachine.state == .holdToTalk)
        guard !activeRecording else { return }

        targetModifierWasPressed = false
        triggerKeyIsPressed = false
        chordModifierReleased = false
        allModifiersHeld = false
        bareTap = true
        stateMachine.reset()
    }

    // MARK: - Modifier Trigger Path (existing behavior)

    private func handleModifierEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let timestampMs = UInt64(event.timestamp / 1_000_000)

        if type == .flagsChanged, let mask = targetMask {
            let flags = event.flags
            let isPressed = flags.contains(mask)

            // Edge detection: only act on actual transitions of the target modifier
            guard isPressed != targetModifierWasPressed else {
                return Unmanaged.passUnretained(event)
            }
            targetModifierWasPressed = isPressed

            if isPressed {
                // Modifier down — start bare-tap tracking
                bareTap = true
                let action = stateMachine.fnDown(timestampMs: timestampMs)
                handleAction(action)

                // Fire ready callback when first tap enters waitingForSecondTap
                if action == .none && stateMachine.state == .waitingForSecondTap {
                    onReadyForSecondTap?()
                }

                // Schedule hold timer
                holdTimer?.cancel()
                let timer = DispatchWorkItem { [weak self] in
                    let action = self?.stateMachine.holdTimerFired() ?? .none
                    self?.handleAction(action)
                }
                holdTimer = timer
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .milliseconds(FnKeyStateMachine.tapThresholdMs),
                    execute: timer
                )
            } else {
                // Modifier up
                holdTimer?.cancel()

                if bareTap {
                    let action = stateMachine.fnUp(timestampMs: timestampMs)
                    handleAction(action)
                } else {
                    // Not a bare tap (e.g., Ctrl+C) — reset instead of treating as a gesture
                    if stateMachine.state == .holdToTalk {
                        handleAction(.cancelRecording)
                    }
                    if stateMachine.state == .waitingForSecondTapToStop {
                        stateMachine.abortStopGesture()
                    } else {
                        stateMachine.reset()
                    }
                }
                bareTap = true
            }

            // Swallow the flagsChanged event when the state machine is actively
            // processing a gesture. This prevents macOS from triggering its own
            // Fn/Globe behavior (dictation, emoji picker, input source switch)
            // which causes the system "dot" sound and yellow dictation icon.
            if stateMachine.state != .idle {
                return nil
            }
        } else if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 { // Escape
                let action = stateMachine.escapePressed()
                if action == .none {
                    // State machine is idle — ESC may still need to dismiss an error overlay
                    onEscapeWhileIdle?()
                } else {
                    handleAction(action)
                }
            } else if keyCode == 63 || keyCode == 179 {
                // Fn/Globe key (63/179) — macOS generates a synthetic keyDown
                // with keyCode 179 when Fn is released (for "Change Input Source" or
                // "Show Emoji & Symbols"). Swallow these when a gesture is active
                // to prevent the system alert sound.
                if stateMachine.state != .idle {
                    return nil
                }
            } else {
                if targetModifierWasPressed {
                    bareTap = false
                }

                // Gesture interruption: if waiting for second tap, a regular key press
                // means the user is typing, not double-tapping the hotkey
                if stateMachine.state == .waitingForSecondTap {
                    stateMachine.reset()
                    holdTimer?.cancel()
                } else if stateMachine.state == .waitingForSecondTapToStop {
                    stateMachine.abortStopGesture()
                    holdTimer?.cancel()
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - KeyCode Trigger Path

    private func handleKeyCodeEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let triggerCode = trigger.keyCode else {
            return Unmanaged.passUnretained(event)
        }

        let timestampMs = UInt64(event.timestamp / 1_000_000)
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyDown {
            if keyCode == triggerCode {
                // Edge detection: ignore key-repeat (macOS sends repeated keyDown for held keys)
                guard !triggerKeyIsPressed else {
                    return nil // Swallow repeated keyDown
                }
                triggerKeyIsPressed = true

                let action = stateMachine.fnDown(timestampMs: timestampMs)
                handleAction(action)

                // Fire ready callback when first tap enters waitingForSecondTap
                if action == .none && stateMachine.state == .waitingForSecondTap {
                    onReadyForSecondTap?()
                }

                // Schedule hold timer
                holdTimer?.cancel()
                let timer = DispatchWorkItem { [weak self] in
                    let action = self?.stateMachine.holdTimerFired() ?? .none
                    self?.handleAction(action)
                }
                holdTimer = timer
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .milliseconds(FnKeyStateMachine.tapThresholdMs),
                    execute: timer
                )

                return nil // Swallow the trigger key event
            } else if keyCode == 53 { // Escape
                let action = stateMachine.escapePressed()
                if action == .none {
                    onEscapeWhileIdle?()
                } else {
                    handleAction(action)
                }
            } else {
                // Gesture interruption: if waiting for second tap, a regular key press
                // means the user is typing, not double-tapping the hotkey
                if stateMachine.state == .waitingForSecondTap {
                    stateMachine.reset()
                    holdTimer?.cancel()
                } else if stateMachine.state == .waitingForSecondTapToStop {
                    stateMachine.abortStopGesture()
                    holdTimer?.cancel()
                }
            }
        } else if type == .keyUp {
            if keyCode == triggerCode {
                guard triggerKeyIsPressed else {
                    return nil // Swallow stale keyUp
                }
                triggerKeyIsPressed = false

                holdTimer?.cancel()
                let action = stateMachine.fnUp(timestampMs: timestampMs)
                handleAction(action)

                return nil // Swallow the trigger key event
            }
        }
        // flagsChanged events are ignored for keyCode triggers

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Chord Trigger Path

    private func handleChordEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let triggerCode = trigger.keyCode else {
            return Unmanaged.passUnretained(event)
        }

        let timestampMs = UInt64(event.timestamp / 1_000_000)
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyDown {
            if keyCode == triggerCode {
                // Check required modifiers are held
                let flags = event.flags.rawValue & Self.relevantModifierBits
                guard flags & requiredChordFlags == requiredChordFlags else {
                    return Unmanaged.passUnretained(event)
                }

                // Edge detection: ignore key-repeat
                guard !triggerKeyIsPressed else {
                    return nil // Swallow repeated keyDown
                }
                triggerKeyIsPressed = true
                chordModifierReleased = false

                let action = stateMachine.fnDown(timestampMs: timestampMs)
                handleAction(action)

                if action == .none && stateMachine.state == .waitingForSecondTap {
                    onReadyForSecondTap?()
                }

                // Schedule hold timer
                holdTimer?.cancel()
                let timer = DispatchWorkItem { [weak self] in
                    let action = self?.stateMachine.holdTimerFired() ?? .none
                    self?.handleAction(action)
                }
                holdTimer = timer
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .milliseconds(FnKeyStateMachine.tapThresholdMs),
                    execute: timer
                )

                return nil // Swallow the trigger key
            } else if keyCode == 53 { // Escape
                let action = stateMachine.escapePressed()
                if action == .none {
                    onEscapeWhileIdle?()
                } else {
                    handleAction(action)
                }
            } else {
                // Gesture interruption
                if stateMachine.state == .waitingForSecondTap {
                    stateMachine.reset()
                    holdTimer?.cancel()
                } else if stateMachine.state == .waitingForSecondTapToStop {
                    stateMachine.abortStopGesture()
                    holdTimer?.cancel()
                }
            }
        } else if type == .keyUp {
            if keyCode == triggerCode {
                // Only swallow keyUp if we previously swallowed the matching keyDown.
                // Otherwise the foreground app sees keyDown without keyUp and macOS
                // opens alternate-character input (issue: chord like Ctrl+Shift+R
                // breaks plain R typing).
                guard triggerKeyIsPressed else {
                    return Unmanaged.passUnretained(event)
                }
                triggerKeyIsPressed = false
                if !chordModifierReleased {
                    // Normal key release — end dictation
                    holdTimer?.cancel()
                    let action = stateMachine.fnUp(timestampMs: timestampMs)
                    handleAction(action)
                }
                chordModifierReleased = false
                // Swallow the trigger key's keyUp (we consumed the keyDown)
                return nil
            }
        } else if type == .flagsChanged {
            // Release-any-part: if a required modifier is released while trigger key is held,
            // end dictation and mark that we already sent fnUp.
            if triggerKeyIsPressed && !chordModifierReleased {
                let flags = event.flags.rawValue & Self.relevantModifierBits
                if flags & requiredChordFlags != requiredChordFlags {
                    chordModifierReleased = true
                    holdTimer?.cancel()
                    let action = stateMachine.fnUp(timestampMs: timestampMs)
                    handleAction(action)
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Multi-Modifier Trigger Path

    /// Handles triggers that require two or more modifier keys held simultaneously (e.g. Option+Command).
    /// Uses the same FnKeyStateMachine for gesture recognition (double-tap / hold-to-talk).
    private func handleMultiModifierEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let timestampMs = UInt64(event.timestamp / 1_000_000)

        if type == .flagsChanged {
            let flags = event.flags.rawValue & Self.relevantModifierBits
            let isHeld = (flags & requiredChordFlags) == requiredChordFlags && requiredChordFlags != 0

            // Edge detection: only act on transitions
            guard isHeld != allModifiersHeld else {
                return Unmanaged.passUnretained(event)
            }
            allModifiersHeld = isHeld

            if isHeld {
                // All required modifiers now held — treat as "key down"
                bareTap = true
                let action = stateMachine.fnDown(timestampMs: timestampMs)
                handleAction(action)

                if action == .none && stateMachine.state == .waitingForSecondTap {
                    onReadyForSecondTap?()
                }

                // Schedule hold timer
                holdTimer?.cancel()
                let timer = DispatchWorkItem { [weak self] in
                    let action = self?.stateMachine.holdTimerFired() ?? .none
                    self?.handleAction(action)
                }
                holdTimer = timer
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .milliseconds(FnKeyStateMachine.tapThresholdMs),
                    execute: timer
                )
            } else {
                // A required modifier was released — treat as "key up"
                holdTimer?.cancel()

                if bareTap {
                    let action = stateMachine.fnUp(timestampMs: timestampMs)
                    handleAction(action)
                } else {
                    // Not a bare tap — a regular key was pressed while modifiers were held
                    if stateMachine.state == .holdToTalk {
                        handleAction(.cancelRecording)
                    }
                    if stateMachine.state == .waitingForSecondTapToStop {
                        stateMachine.abortStopGesture()
                    } else {
                        stateMachine.reset()
                    }
                }
                bareTap = true
            }
        } else if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 { // Escape
                let action = stateMachine.escapePressed()
                if action == .none {
                    onEscapeWhileIdle?()
                } else {
                    handleAction(action)
                }
            } else {
                // Regular key pressed while modifiers held — not a bare tap
                if allModifiersHeld {
                    bareTap = false
                }

                // Gesture interruption
                if stateMachine.state == .waitingForSecondTap {
                    stateMachine.reset()
                    holdTimer?.cancel()
                } else if stateMachine.state == .waitingForSecondTapToStop {
                    stateMachine.abortStopGesture()
                    holdTimer?.cancel()
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    /// Notify state machine that cancel was triggered via UI (not Esc).
    /// Blocks hotkey during the cancel countdown window.
    public func notifyCancelledByUI() {
        stateMachine.cancelledByUI()
    }

    /// Resume recording mode after undo, so hotkey stops the recording correctly.
    public func resumeRecording(mode: FnKeyStateMachine.RecordingMode) {
        stateMachine.resumeRecording(mode: mode)
    }

    /// Reset state machine to idle (e.g., after cancel countdown expires).
    public func resetToIdle() {
        stateMachine.reset()
    }

    private func handleAction(_ action: FnKeyStateMachine.Action) {
        switch action {
        case .none:
            break
        case .startRecording(let mode):
            onStartRecording?(mode)
        case .stopRecording:
            onStopRecording?()
        case .cancelRecording:
            onCancelRecording?()
        }
    }

    // MARK: - Key Mapping

    private static func mask(for trigger: HotkeyTrigger) -> CGEventFlags? {
        guard trigger.kind == .modifier, let name = trigger.modifierName else { return nil }
        switch name {
        case "fn": return .maskSecondaryFn
        case "control": return .maskControl
        case "option": return .maskAlternate
        case "shift": return .maskShift
        case "command": return .maskCommand
        default: return nil
        }
    }
}
