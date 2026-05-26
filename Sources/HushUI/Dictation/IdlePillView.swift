import SwiftUI
import HushCore
import HushViewModels

/// Persistent floating pill shown when idle — always visible when not dictating.
/// Expands on hover to show "Click or hold <trigger key> to start dictating" tooltip.
public struct IdlePillView: View {
    @Bindable var viewModel: IdlePillViewModel

    public init(viewModel: IdlePillViewModel) {
        self.viewModel = viewModel
    }

    /// Whether we're in notch grow-down mode.
    private var isNotchMode: Bool {
        viewModel.isTopPosition && viewModel.notchGapWidth > 0
    }

    public var body: some View {
        if isNotchMode {
            notchBody
        } else {
            bottomBody
        }
    }

    // MARK: - Bottom Position (original design)

    private var bottomBody: some View {
        VStack(spacing: 6) {
            tooltip
                .opacity(viewModel.isHovered ? 1 : 0)
                .scaleEffect(viewModel.isHovered ? 1 : 0.9)
                .animation(.easeOut(duration: 0.2), value: viewModel.isHovered)

            bottomPill
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isHovered)
        }
        .padding(.bottom, 8)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .bottom
        )
    }

    // MARK: - Notch Grow-Down Position

    private var notchBody: some View {
        VStack(spacing: 0) {
            // Invisible spacer matching notch height — pushes content below camera housing
            Color.clear.frame(height: viewModel.notchHeight + 2)

            // Collapsed: just a row of dots; Expanded: dots + tooltip
            VStack(spacing: viewModel.isHovered ? 8 : 0) {
                dotsRow
                    .padding(.top, 4)

                if viewModel.isHovered {
                    notchTooltipContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, viewModel.isHovered ? 6 : 4)
        }
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 0
            )
            .fill(.black)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isHovered)
        // Constrain width: slightly wider than notch for the grow-down bump
        .frame(width: viewModel.isHovered ? viewModel.notchGapWidth + 80 : viewModel.notchGapWidth + 20)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
    }

    /// Tooltip text content for notch mode (no separate background — part of the grow-down)
    private var notchTooltipContent: some View {
        HStack(spacing: 0) {
            Text("Click or hold ")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Text(HotkeyTrigger.current.shortSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: NSColor(red: 0.85, green: 0.55, blue: 0.75, alpha: 1.0)))
            Text(" to dictate")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Bottom Pill

    private var bottomPill: some View {
        ZStack {
            Capsule()
                .fill(viewModel.isHovered ? DesignSystem.Colors.pillBackground : Color(white: 0.25, opacity: 0.9))
                .overlay(
                    Capsule()
                        .strokeBorder(DesignSystem.Colors.pillBorder.opacity(viewModel.isHovered ? 0.67 : 0.4), lineWidth: 0.5)
                )
        }
        .frame(
            width: viewModel.isHovered ? 148 : 48,
            height: viewModel.isHovered ? 30 : 10
        )
        .shadow(color: .black.opacity(0.3), radius: viewModel.isHovered ? 8 : 4, y: 4)
        .overlay {
            if viewModel.isHovered {
                dotsRow
                    .transition(.opacity)
            }
        }
    }

    private var dotsRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<12, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 3, height: 3)
            }
        }
    }

    // MARK: - Tooltip (bottom position)

    private var tooltip: some View {
        HStack(spacing: 0) {
            Text("Click or hold ")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text(HotkeyTrigger.current.shortSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(nsColor: NSColor(red: 0.85, green: 0.55, blue: 0.75, alpha: 1.0)))
            Text(" to start dictating")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.pillBackground)
                .overlay(
                    Capsule()
                        .strokeBorder(DesignSystem.Colors.pillBorder.opacity(0.67), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        )
    }
}

struct IdlePillView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            IdlePillView(viewModel: {
                let vm = IdlePillViewModel()
                return vm
            }())

            IdlePillView(viewModel: {
                let vm = IdlePillViewModel()
                vm.isHovered = true
                return vm
            }())
        }
        .padding(30)
        .frame(width: 400, height: 200)
        .background(Color.gray.opacity(0.3))
    }
}
