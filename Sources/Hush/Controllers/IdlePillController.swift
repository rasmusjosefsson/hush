import AppKit
import HushCore
import HushUI
import HushViewModels
import SwiftUI

// MARK: - Mouse Tracking (click-aware)

/// NSView overlay that detects mouse hover and clicks for the idle pill.
/// Uses mouseMoved to precisely track whether the cursor is over the pill region,
/// not the entire panel. The hover rect changes based on expanded state.
private final class IdlePillTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClicked: (() -> Void)?

    /// Small rect for the collapsed pill (hover trigger zone).
    var collapsedPillRect: NSRect = .zero
    /// Larger rect for the expanded pill + tooltip (stays hovered while interacting).
    var expandedPillRect: NSRect = .zero

    private var isInsidePill = false
    private var isExpanded = false

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
        // Panel entered — start tracking position
    }

    override func mouseExited(with event: NSEvent) {
        // Left the panel entirely — always exit hover
        if isInsidePill {
            isInsidePill = false
            isExpanded = false
            onExit?()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let activeRect = isExpanded ? expandedPillRect : collapsedPillRect

        if activeRect.contains(point) {
            if !isInsidePill {
                isInsidePill = true
                isExpanded = true
                onEnter?()
            }
        } else {
            if isInsidePill {
                isInsidePill = false
                isExpanded = false
                onExit?()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if expandedPillRect.contains(point) {
            onClicked?()
        }
    }

    // Only intercept clicks in the expanded pill region; pass through everywhere else
    override func hitTest(_ point: NSPoint) -> NSView? {
        expandedPillRect.contains(point) ? self : nil
    }
}

/// NSPanel subclass for the idle pill in notch mode.
/// Mirrors boring.notch's window config to render inside the notch zone.
/// canBecomeKey is false for idle pill — clicks are handled by the tracking view.
private final class NotchIdlePanel: NSPanel {
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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Idle Pill Controller

/// Manages the persistent idle pill panel — always visible when not dictating.
/// Non-activating NSPanel that never steals focus.
@MainActor
final class IdlePillController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<IdlePillView>?
    private var trackingView: IdlePillTrackingView?
    private var position: OverlayPosition = .bottom

    private let viewModel: IdlePillViewModel

    init(viewModel: IdlePillViewModel) {
        self.viewModel = viewModel
    }

    func show(position: OverlayPosition = .bottom) {
        if panel != nil { return }

        self.position = position
        viewModel.isTopPosition = position == .top

        // Detect notch for sizing/positioning
        let notch = NotchGeometry.detect(for: NSScreen.main)

        if position == .top && notch.hasNotch {
            viewModel.notchHeight = notch.notchHeight
            viewModel.notchGapWidth = notch.notchWidth
        } else {
            viewModel.notchHeight = 0
            viewModel.notchGapWidth = 0
        }

        let view = IdlePillView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: view)

        // For notch mode: panel centered on notch, wide enough for grow-down content.
        // For bottom mode: standard 350pt.
        let panelWidth: CGFloat = (position == .top && notch.hasNotch)
            ? notch.notchWidth + 120
            : 350
        let panelHeight: CGFloat = (position == .top && notch.hasNotch)
            ? 120  // Taller for grow-down content
            : 90
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let panel: NSPanel
        if position == .top {
            // Use notch-style panel config (mirrors boring.notch)
            panel = NotchIdlePanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                backing: .buffered,
                defer: false
            )
        } else {
            panel = NSPanel(
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

        // Mouse tracking overlay for hover + click
        let tracker = IdlePillTrackingView(frame: hosting.bounds)
        tracker.autoresizingMask = [.width, .height]
        tracker.onEnter = { [weak self] in
            Task { @MainActor in self?.viewModel.isHovered = true }
        }
        tracker.onExit = { [weak self] in
            Task { @MainActor in self?.viewModel.isHovered = false }
        }
        tracker.onClicked = { [weak self] in
            Task { @MainActor in self?.viewModel.onStartDictation?() }
        }

        if position == .top {
            // Top/notch position: grow-down pill is centered in the panel
            // Collapsed: small centered area at top for the dots row
            let collapsedW: CGFloat = notch.notchWidth + 30
            let collapsedH: CGFloat = notch.notchHeight + 20
            let collapsedX = (panelWidth - collapsedW) / 2
            let collapsedY = panelHeight - collapsedH
            tracker.collapsedPillRect = NSRect(x: collapsedX, y: collapsedY, width: collapsedW, height: collapsedH)

            // Expanded: wider area covering the full grow-down content + tooltip
            let expandedW: CGFloat = notch.notchWidth + 100
            let expandedH: CGFloat = panelHeight
            let expandedX = (panelWidth - expandedW) / 2
            let expandedY: CGFloat = 0
            tracker.expandedPillRect = NSRect(x: expandedX, y: expandedY, width: expandedW, height: expandedH)
        } else {
            // Bottom position: pill is at the bottom of the panel
            let collapsedW: CGFloat = 60
            let collapsedH: CGFloat = 24
            let collapsedX = (panelWidth - collapsedW) / 2
            tracker.collapsedPillRect = NSRect(x: collapsedX, y: 0, width: collapsedW, height: collapsedH)

            let expandedW: CGFloat = 320
            let expandedH: CGFloat = 80
            let expandedX = (panelWidth - expandedW) / 2
            tracker.expandedPillRect = NSRect(x: expandedX, y: 0, width: expandedW, height: expandedH)
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
            // Idle pill panel centered on the notch for grow-down design
            let x = notch.centeredOriginX(panelWidth: width, screenFrame: screenFrame)
            let y = notch.topOriginY(panelHeight: height, screenFrame: screenFrame)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}
