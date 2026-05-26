import AppKit
import Carbon
import Foundation

public protocol ClipboardServiceProtocol: Sendable {
    func pasteText(_ text: String) async throws
    func copyToClipboard(_ text: String) async
}

public enum ClipboardServiceError: LocalizedError {
    case accessibilityPermissionRequired
    case eventSourceUnavailable
    case eventCreationFailed
    case pasteboardWriteFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required for auto-paste."
        case .eventSourceUnavailable:
            return "Paste automation unavailable (event source creation failed)."
        case .eventCreationFailed:
            return "Paste automation unavailable (could not create keyboard events)."
        case .pasteboardWriteFailed:
            return "Failed to write transcript to clipboard."
        }
    }
}

/// Handles clipboard save/restore and paste simulation via Cmd+V.
@MainActor
public final class ClipboardService: ClipboardServiceProtocol {
    private let pasteShortcutKeyResolver: PasteShortcutKeyResolver

    public init() {
        self.pasteShortcutKeyResolver = PasteShortcutKeyResolver()
    }

    init(pasteShortcutKeyResolver: PasteShortcutKeyResolver) {
        self.pasteShortcutKeyResolver = pasteShortcutKeyResolver
    }

    /// Paste text into the active app by:
    /// 1. Saving current clipboard
    /// 2. Setting transcript on clipboard
    /// 3. Simulating Cmd+V
    /// 4. Restoring original clipboard after a 1s delay
    ///
    /// The 1s window (raised from 150ms) gives slow target apps time to
    /// process the synthetic Cmd+V before we restore. The `changeCount`
    /// guard still prevents clobbering user edits.
    public func pasteText(_ text: String) async throws {
        let pasteboard = NSPasteboard.general

        // 1. Save current clipboard contents
        let savedItems: [NSPasteboardItem]? = pasteboard.pasteboardItems?.map { item in
            let restored = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    restored.setData(data, forType: type)
                }
            }
            return restored
        }

        // 2. Set transcript — fail explicitly rather than posting Cmd+V against
        //    stale clipboard contents if the write didn't take.
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            // Try to restore the original clipboard immediately since we already cleared it.
            if let savedItems, !savedItems.isEmpty {
                pasteboard.clearContents()
                pasteboard.writeObjects(savedItems)
            }
            throw ClipboardServiceError.pasteboardWriteFailed
        }
        let ourChangeCount = pasteboard.changeCount

        // Always attempt to restore the previous clipboard contents after a delay.
        // If caller intentionally rewrites clipboard on error, changeCount guard prevents clobbering.
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // If the user changed the clipboard after we wrote, do not clobber it.
                guard pasteboard.changeCount == ourChangeCount else {
                    return
                }

                pasteboard.clearContents()
                if let savedItems, !savedItems.isEmpty {
                    pasteboard.writeObjects(savedItems)
                }
            }
        }

        // 3. Simulate Cmd+V
        try simulatePaste()
    }

    /// Copy text to clipboard without paste simulation
    public func copyToClipboard(_ text: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Private

    private func simulatePaste() throws {
        guard AXIsProcessTrusted() else {
            throw ClipboardServiceError.accessibilityPermissionRequired
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ClipboardServiceError.eventSourceUnavailable
        }

        // Resolve the shortcut under the same Command-modified layout state that
        // the generated CGEvents will carry. This preserves layouts such as
        // "Dvorak - QWERTY ⌘" that intentionally remap only while Command is held.
        let vKeyCode = pasteShortcutKeyResolver.virtualKeyCode(
            for: "v",
            modifierKeyState: UInt32(cmdKey >> 8)
        )

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            throw ClipboardServiceError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)

        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }
}
