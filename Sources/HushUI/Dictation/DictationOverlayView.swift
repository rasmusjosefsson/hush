import HushCore
import HushViewModels
import SwiftUI

// MARK: - Animated Checkmark

/// Apple-style success checkmark: thin ring draws, then thin check strokes in.
/// Inspired by Apple Pay / Activity completion — confidence through restraint.
private struct AnimatedCheckmarkView: View {
    var size: CGFloat = 20
    @State private var ringTrim: CGFloat = 0
    @State private var checkTrim: CGFloat = 0

    private let lineWidth: CGFloat = 1.5
    private let color = DesignSystem.Colors.successGreen

    var body: some View {
        ZStack {
            // Background ring (faint guide)
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            // Animated ring
            Circle()
                .trim(from: 0, to: ringTrim)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Checkmark
            CheckmarkShape()
                .trim(from: 0, to: checkTrim)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .padding(size * 0.27)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                ringTrim = 1
            }
            withAnimation(.easeOut(duration: 0.25).delay(0.25)) {
                checkTrim = 1
            }
        }
    }
}

/// Checkmark path shape
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.22, y: h * 0.52))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.28))
        return path
    }
}

/// Thin rotating ring, same footprint as the checkmark so processing → success morphs in place.
private struct OverlaySpinner: View {
    var size: CGFloat = 20
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(DesignSystem.Colors.overlayFill, lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(DesignSystem.Colors.overlayPrimary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

/// The dictation overlay. In notch mode a single black surface continues the hardware
/// notch: compact content flanks the camera, messages expand downward. Elsewhere the
/// same content sits in a floating capsule (or a card when there is a message).
public struct DictationOverlayView: View {
    @Bindable var viewModel: DictationOverlayViewModel

    public init(viewModel: DictationOverlayViewModel) {
        self.viewModel = viewModel
    }

    private typealias Colors = DesignSystem.Colors
    private typealias Typography = DesignSystem.Typography

    public var body: some View {
        VStack(spacing: 6) {
            if viewModel.isTopPosition {
                surface
                tooltipRow
            } else {
                tooltipRow
                surface
            }
        }
        .padding(.bottom, viewModel.isTopPosition ? 0 : 8)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: viewModel.isTopPosition ? .top : .bottom
        )
    }

    // MARK: - Layout

    private var isNotchMode: Bool {
        viewModel.notchGapWidth > 0 && viewModel.isTopPosition
    }

    private var isError: Bool {
        if case .error = viewModel.state { return true }
        return false
    }

    /// Width of each "ear" next to the camera in notch mode, per state.
    private var earWidth: CGFloat {
        switch viewModel.state {
        case .ready: return 34
        case .recording: return viewModel.recordingMode == .holdToTalk ? 64 : 92
        case .cancelled: return 64
        case .processing, .success: return 40
        case .noSpeech: return 40
        case .error: return 60
        }
    }

    private static let earTopRadius: CGFloat = 6

    @ViewBuilder
    private var surface: some View {
        if isNotchMode {
            notchSurface
        } else {
            floatingSurface
        }
    }

    private var notchSurface: some View {
        let width = viewModel.notchGapWidth + earWidth * 2 + Self.earTopRadius * 2
        return VStack(spacing: 0) {
            // ear | camera gap | ear — content never sits under the hardware cutout
            HStack(spacing: 0) {
                leadingContent
                    .padding(.leading, 6)
                    .frame(width: earWidth, alignment: .leading)
                Color.clear.frame(width: viewModel.notchGapWidth)
                trailingContent
                    .padding(.trailing, 6)
                    .frame(width: earWidth, alignment: .trailing)
            }
            .padding(.horizontal, Self.earTopRadius)
            .frame(height: max(viewModel.notchHeight, 28))

            if let expanded = expandedContent {
                expanded
                    .padding(.horizontal, Self.earTopRadius + 14)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(width: max(width, hasExpandedContent ? viewModel.notchGapWidth + 140 : 0))
        .background(
            NotchShape(topRadius: Self.earTopRadius, bottomRadius: hasExpandedContent ? 20 : 12)
                .fill(.black)
        )
        .animation(DesignSystem.Animation.overlayMorph, value: viewModel.pillStateKey)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var floatingSurface: some View {
        if hasExpandedContent {
            VStack(alignment: .leading, spacing: 10) {
                if case .recording = viewModel.state { compactRow }
                if case .processing = viewModel.state { compactRow }
                expandedContent
            }
            .padding(14)
            .frame(width: isError || viewModel.sessionKind == .command ? 280 : 220)
            .background(floatingBackground(RoundedRectangle(cornerRadius: 18, style: .continuous)))
            .animation(DesignSystem.Animation.overlayMorph, value: viewModel.pillStateKey)
        } else {
            compactRow
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(floatingBackground(Capsule()))
                .animation(DesignSystem.Animation.overlayMorph, value: viewModel.pillStateKey)
        }
    }

    private var compactRow: some View {
        HStack(spacing: 12) {
            leadingContent
            trailingContent
        }
        .frame(minHeight: 22)
    }

    private func floatingBackground(_ shape: some InsettableShape) -> some View {
        shape
            .fill(Colors.pillBackground)
            .overlay(shape.strokeBorder(Colors.pillBorder, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }

    // MARK: - Content slots

    @ViewBuilder
    private var leadingContent: some View {
        ZStack {
            switch viewModel.state {
            case .ready:
                BrandWaveformView(size: 14, color: Colors.overlaySecondary)
            case .recording:
                if viewModel.recordingMode == .holdToTalk {
                    HStack(spacing: 6) {
                        RecordingDot()
                        timer
                    }
                } else {
                    HStack(spacing: 8) {
                        cancelButton
                        timer
                    }
                }
            case .cancelled:
                countdownRing
            case .processing, .success:
                BrandWaveformView(size: 14, color: Colors.overlaySecondary)
            case .noSpeech, .error:
                // Icon lives inline with the message in the expanded area
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(DesignSystem.Animation.overlayContent, value: viewModel.pillStateKey)
    }

    @ViewBuilder
    private var trailingContent: some View {
        ZStack {
            switch viewModel.state {
            case .ready:
                WaveformView(audioLevel: 0.15, barCount: 5)
            case .recording:
                HStack(spacing: 10) {
                    WaveformView(audioLevel: viewModel.audioLevel, barCount: viewModel.recordingMode == .holdToTalk ? 7 : 9)
                    if viewModel.recordingMode == .persistent {
                        stopButton
                    }
                }
            case .cancelled:
                undoButton
            case .processing:
                OverlaySpinner(size: 18)
            case .success:
                AnimatedCheckmarkView(size: 18)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .noSpeech, .error:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(DesignSystem.Animation.overlayContent, value: viewModel.pillStateKey)
    }

    private var hasExpandedContent: Bool {
        switch viewModel.state {
        case .noSpeech, .error: return true
        case .recording, .processing: return viewModel.sessionKind == .command
        default: return false
        }
    }

    private var expandedContent: AnyView? {
        guard hasExpandedContent else { return nil }
        switch viewModel.state {
        case .recording: return AnyView(commandPrompt)
        case .processing: return AnyView(statusLine("Applying command…"))
        case .noSpeech: return AnyView(noSpeechContent)
        case .error(let message): return AnyView(errorContent(message: message))
        default: return nil
        }
    }

    // MARK: - Pieces

    private var timer: some View {
        Text(viewModel.formattedElapsed)
            .font(Typography.overlayTimer)
            .foregroundStyle(Colors.overlaySecondary)
            .fixedSize()
    }

    private var isCancelHovered: Bool {
        viewModel.hoverTooltip?.contains("Cancel") == true
    }

    private var isStopHovered: Bool {
        viewModel.hoverTooltip?.contains("Stop") == true
    }

    private var cancelButton: some View {
        OverlayCircleButton(tint: .white.opacity(0.28), isHovered: isCancelHovered, action: { viewModel.onCancel?() }) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Cancel dictation")
    }

    private var stopButton: some View {
        OverlayCircleButton(tint: Colors.recordingRed, isHovered: isStopHovered, action: { viewModel.onStop?() }) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(.white)
                .frame(width: 8, height: 8)
        }
        .accessibilityLabel(viewModel.sessionKind == .command ? "Stop and apply" : "Stop and paste")
    }

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(Colors.overlayFill, lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: CGFloat(viewModel.cancelTimeRemaining / 5.0))
                .stroke(Colors.overlayAccent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: viewModel.cancelTimeRemaining)
            Text("\(Int(ceil(viewModel.cancelTimeRemaining)))")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Colors.overlayPrimary)
        }
        .frame(width: 20, height: 20)
        .contentShape(Circle())
        .onTapGesture {
            // Confirm cancel immediately (matches spec: tap ring to discard now).
            viewModel.onCancel?()
        }
        .help("Discard now")
    }

    private var undoButton: some View {
        Button(action: { viewModel.onUndo?() }) {
            Text("Undo")
                .font(Typography.overlayLabel)
                .foregroundStyle(Colors.overlayAccent)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Colors.overlayFill))
        }
        .buttonStyle(.plain)
    }

    private var commandPrompt: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.commandPromptText)
                .font(Typography.overlayTitle)
                .foregroundStyle(Colors.overlayPrimary)
            HStack(spacing: 4) {
                Text("“\(viewModel.commandSelectedPreview)”")
                    .foregroundStyle(Colors.overlaySecondary)
                    .lineLimit(1)
                Text("\(viewModel.commandSelectedCharacterCount) chars")
                    .foregroundStyle(Colors.overlayTertiary)
                    .fixedSize()
            }
            .font(Typography.overlayCaption)
        }
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(Typography.overlayLabel)
            .foregroundStyle(Colors.overlaySecondary)
    }

    private var noSpeechContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Colors.overlaySecondary)
                Text(viewModel.sessionKind == .command ? "No command detected" : "No speech detected")
                    .font(Typography.overlayTitle)
                    .foregroundStyle(Colors.overlayPrimary)
            }

            // Thin progress bar — track + fill, shrinks over 3s
            ZStack(alignment: .leading) {
                Capsule().fill(Colors.overlayFill)
                Capsule()
                    .fill(Colors.overlaySecondary)
                    .scaleEffect(x: viewModel.noSpeechProgress, anchor: .leading)
                    .animation(.linear(duration: 3.0), value: viewModel.noSpeechProgress)
            }
            .frame(height: 2)
            .onAppear {
                // Trigger after the view renders so SwiftUI has a "from" value to animate
                viewModel.noSpeechProgress = 0.0
            }
        }
    }

    private func errorContent(message: String) -> some View {
        let info = errorInfo(message)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Colors.warningAmber)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(Typography.overlayTitle)
                        .foregroundStyle(Colors.overlayPrimary)
                    Text(info.subtitle)
                        .font(Typography.overlayCaption)
                        .foregroundStyle(Colors.overlaySecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
            }

            HStack {
                Spacer()
                Button(action: { viewModel.onDismiss?() }) {
                    Text("Dismiss")
                        .font(Typography.overlayLabel)
                        .foregroundStyle(Colors.overlayPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(Capsule().fill(Colors.overlayFill))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    /// Map technical error messages to user-friendly title + actionable subtitle
    private func errorInfo(_ message: String) -> (title: String, subtitle: String) {
        let lower = message.lowercased()

        if lower.contains("stt") || lower.contains("speech engine") || lower.contains("engine")
            || lower.contains("model not loaded")
            || lower.contains("failed to start") {
            return ("Speech Engine Not Ready", "Run onboarding or go to Settings > Speech Model > Repair.")
        }
        if lower.contains("couldn't hear") || lower.contains("empty")
            || lower.contains("too short") || lower.contains("insufficient") {
            return ("No Speech Detected", "Try speaking louder or holding a bit longer.")
        }
        if lower.contains("microphone") || lower.contains("audio input") {
            return ("Microphone Unavailable", "Check your mic connection or select a different input.")
        }
        if lower.contains("copied to clipboard") || lower.contains("cmd+v") {
            return ("Copied to Clipboard", "Auto-paste wasn't available. Press ⌘V where you want the text.")
        }
        if lower.contains("permission") || lower.contains("access") {
            return ("Permission Required", "Grant access in System Settings > Privacy & Security.")
        }
        if lower.contains("not recording") {
            return ("Not Recording", "Press \(HotkeyTrigger.current.displayName) to start recording first.")
        }
        if lower.contains("timeout") || lower.contains("timed out") {
            return ("Transcription Timed Out", "Try a shorter recording or restart the app.")
        }
        if lower.contains("memory") || lower.contains("oom") {
            return ("Out of Memory", "Close other apps to free memory and try again.")
        }

        // Fallback: use the raw message as subtitle
        let title = "Something Went Wrong"
        let subtitle = message.count > 90 ? String(message.prefix(87)) + "…" : message
        return (title, subtitle)
    }

    // MARK: - Tooltip

    /// Align tooltip under/over the hovered button: leading for cancel, trailing for stop.
    private var tooltipAlignment: Alignment {
        if isCancelHovered { return .leading }
        if isStopHovered { return .trailing }
        return .center
    }

    private var tooltipRow: some View {
        tooltipLabel
            .frame(maxWidth: .infinity, alignment: tooltipAlignment)
            .padding(.horizontal, isNotchMode ? 24 : 30)
            .opacity(viewModel.isHovered && viewModel.hoverTooltip != nil ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: viewModel.isHovered)
            .animation(.easeInOut(duration: 0.1), value: viewModel.hoverTooltip)
            .frame(height: 30)
    }

    /// "Cancel (Esc)" → "Cancel" + keycap "Esc"
    @ViewBuilder
    private var tooltipLabel: some View {
        if let tooltip = viewModel.hoverTooltip {
            HStack(spacing: 6) {
                if let parenStart = tooltip.firstIndex(of: "("),
                   let parenEnd = tooltip.lastIndex(of: ")") {
                    Text(tooltip[..<parenStart].trimmingCharacters(in: .whitespaces))
                        .font(Typography.overlayLabel)
                        .foregroundStyle(Colors.overlayPrimary)
                    OverlayKeycap(String(tooltip[tooltip.index(after: parenStart)..<parenEnd]))
                } else {
                    Text(tooltip)
                        .font(Typography.overlayLabel)
                        .foregroundStyle(Colors.overlayPrimary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(floatingBackground(Capsule()))
        }
    }
}

/// Softly pulsing red dot used while holding the hotkey.
private struct RecordingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(DesignSystem.Colors.recordingRed)
            .frame(width: 7, height: 7)
            .opacity(pulse ? 0.55 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

struct DictationOverlayView_Previews: PreviewProvider {
    static func make(_ state: DictationOverlayViewModel.OverlayState, notch: Bool, mode: FnKeyStateMachine.RecordingMode = .persistent) -> some View {
        let vm = DictationOverlayViewModel()
        vm.state = state
        vm.recordingMode = mode
        vm.audioLevel = 0.4
        vm.recordingElapsedSeconds = 12
        vm.isTopPosition = notch
        vm.notchGapWidth = notch ? 185 : 0
        vm.notchHeight = notch ? 32 : 0
        return DictationOverlayView(viewModel: vm).frame(width: 445, height: notch ? 140 : 120)
    }

    static var previews: some View {
        let states: [DictationOverlayViewModel.OverlayState] = [
            .ready, .recording, .cancelled(timeRemaining: 3), .processing, .success, .noSpeech,
            .error("Failed to start speech engine: model not loaded"),
        ]
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 8) {
                ForEach(Array(states.enumerated()), id: \.offset) { make($0.element, notch: true) }
                make(.recording, notch: true, mode: .holdToTalk)
            }
            VStack(spacing: 8) {
                ForEach(Array(states.enumerated()), id: \.offset) { make($0.element, notch: false) }
            }
        }
        .padding(20)
        .background(Color.gray.opacity(0.3))
    }
}
