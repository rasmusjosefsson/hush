import AppKit
import HushCore
import HushUI
import HushViewModels
import SwiftUI

// MARK: - Mouse Tracking

/// NSView overlay that detects mouse hover and position via NSTrackingArea with `.activeAlways`.
/// Required because `.help()`, `.onHover`, and standard tracking options
/// all fail on non-activating NSPanel. See CLAUDE.md Known Pitfalls.
private final class MouseTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onMoved: ((NSPoint) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
        onMoved?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) { onExit?() }

    override func mouseMoved(with event: NSEvent) {
        onMoved?(convert(event.locationInWindow, from: nil))
    }

    // Pass all clicks through to SwiftUI content below
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Clickable Non-Activating Panel

/// NSPanel subclass that allows SwiftUI buttons to receive clicks while
/// remaining non-activating (won't steal focus on `orderFront`).
/// Without `canBecomeKey = true`, buttons inside a `.nonactivatingPanel`
/// are unresponsive because the panel never becomes key window.
private final class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    // Swallow key events to prevent macOS system beep (NSBeep)
    override func keyDown(with event: NSEvent) {}
}

/// NSPanel subclass for the notch overlay that mirrors boring.notch's window config.
/// Uses .utilityWindow + .hudWindow + isFloatingPanel to render above the menu bar
/// in the notch zone. canBecomeKey is true so SwiftUI buttons remain clickable.
private final class NotchPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        configureForNotch()
    }

    private func configureForNotch() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        hasShadow = false
        level = .mainMenu + 3
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
    }

    // Must be key to receive SwiftUI button clicks
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Swallow key events to prevent macOS system beep (NSBeep)
    override func keyDown(with event: NSEvent) {}
}

// MARK: - Overlay Controller

/// Manages the floating dictation overlay panel.
/// Non-activating NSPanel that never steals focus from the active app.
@MainActor
final class DictationOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<DictationOverlayView>?
    private var trackingView: MouseTrackingView?
    private var position: OverlayPosition = .bottom

    private let overlayViewModel: DictationOverlayViewModel

    init(viewModel: DictationOverlayViewModel) {
        self.overlayViewModel = viewModel
    }

    func show(position: OverlayPosition = .bottom) {
        if panel != nil { return }

        self.position = position
        overlayViewModel.isTopPosition = position == .top

        // Detect notch for sizing/positioning
        let notch = NotchGeometry.detect(for: NSScreen.main)

        if position == .top && notch.hasNotch {
            // Pass notch gap width so the view can split recording content around the camera
            overlayViewModel.notchGapWidth = notch.notchWidth
            overlayViewModel.notchHeight = notch.notchHeight
        } else {
            overlayViewModel.notchGapWidth = 0
            overlayViewModel.notchHeight = 0
        }

        let view = DictationOverlayView(viewModel: overlayViewModel)
        let hosting = NSHostingView(rootView: view)

        // For notch mode: panel must be wide enough to span both sides of the camera cutout
        // with room for content on each side (~120pt per side + notchWidth gap).
        // All notch states (recording split AND non-recording grow-down) use this width
        // so the panel is centered on the notch for seamless state transitions.
        // For bottom mode: standard 300pt.
        let panelWidth: CGFloat = (position == .top && notch.hasNotch)
            ? notch.notchWidth + 260
            : 300
        let panelHeight: CGFloat = (position == .top && notch.hasNotch)
            ? 200  // Taller for grow-down content below notch
            : 160
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let panel: NSPanel
        if position == .top {
            // Use notch-style panel config (mirrors boring.notch)
            panel = NotchPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                backing: .buffered,
                defer: false
            )
        } else {
            panel = ClickablePanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        panel.contentView = hosting

        // Mouse tracking overlay for hover tooltips
        let tracker = MouseTrackingView(frame: hosting.bounds)
        tracker.autoresizingMask = [.width, .height]
        tracker.onEnter = { [weak self] in
            MainActor.assumeIsolated { self?.overlayViewModel.isHovered = true }
        }
        tracker.onExit = { [weak self] in
            MainActor.assumeIsolated {
                self?.overlayViewModel.isHovered = false
                self?.overlayViewModel.hoverTooltip = nil
            }
        }
        tracker.onMoved = { [weak self] point in
            MainActor.assumeIsolated {
                self?.updateHoverTooltip(at: point, in: hosting.bounds)
            }
        }
        hosting.addSubview(tracker)
        trackingView = tracker

        applyPosition(to: panel, width: panelWidth, height: panelHeight)

        panel.orderFront(nil)

        // Add to CGSSpace so the window renders above menu bar / notch region
        if position == .top {
            NotchSpaceManager.shared.notchSpace.windows.insert(panel)
        }

        self.panel = panel
        self.hostingView = hosting
    }

    func hide() {
        if let panel {
            NotchSpaceManager.shared.notchSpace.windows.remove(panel)
            panel.orderOut(nil)
        }
        panel = nil
        hostingView = nil
        trackingView = nil
    }

    /// Resign key window so CGEvent paste targets the user's app, not the overlay panel.
    /// Call this before any simulated Cmd+V when the overlay was clicked (e.g. Undo, Stop button).
    func resignKeyWindow() {
        panel?.resignKey()
    }

    /// Determine which element the cursor is over and update the tooltip.
    /// The pill is centered in the panel. Left zone = cancel, right zone = stop.
    private func updateHoverTooltip(at point: NSPoint, in bounds: NSRect) {
        guard case .recording = overlayViewModel.state,
              overlayViewModel.recordingMode == .persistent else {
            // No hover tooltips in hold-to-talk, ready, cancelled, processing, success, noSpeech, or error states
            overlayViewModel.hoverTooltip = nil
            return
        }

        let panelWidth = bounds.width
        let pillWidth: CGFloat = 210 // approximate pill content width
        let pillLeft = (panelWidth - pillWidth) / 2
        let pillRight = pillLeft + pillWidth

        let x = point.x
        if x >= pillLeft && x < pillLeft + 45 {
            overlayViewModel.hoverTooltip = "Cancel (Esc)"
        } else if x > pillRight - 45 && x <= pillRight {
            if overlayViewModel.sessionKind == .command {
                overlayViewModel.hoverTooltip = "Stop & apply (Fn+Control)"
            } else {
                overlayViewModel.hoverTooltip = "Stop & paste (\(HotkeyTrigger.current.displayName))"
            }
        } else {
            overlayViewModel.hoverTooltip = nil
        }
    }

    func updateSize(width: CGFloat) {
        guard let panel else { return }
        var frame = panel.frame
        let oldWidth = frame.width
        frame.size.width = width
        frame.origin.x += (oldWidth - width) / 2
        panel.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Positioning

    private func applyPosition(to panel: NSPanel, width: CGFloat, height: CGFloat) {
        guard let screen = NSScreen.main else { return }

        switch position {
        case .bottom:
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - width / 2
            let y = screenFrame.origin.y + 12
            panel.setFrameOrigin(NSPoint(x: x, y: y))

        case .top:
            let screenFrame = screen.frame
            let notch = NotchGeometry.detect(for: screen)
            // Wide panel centered on the notch for all states:
            // recording splits content around camera, non-recording grows down from notch.
            let x = notch.centeredOriginX(panelWidth: width, screenFrame: screenFrame)
            let y = notch.topOriginY(panelHeight: height, screenFrame: screenFrame)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}
