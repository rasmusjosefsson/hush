import SwiftUI
import HushCore
import HushViewModels

/// Persistent floating pill shown when idle — always visible when not dictating.
/// Expands on hover to show a "Click or hold <trigger key> to dictate" hint.
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

    // MARK: - Bottom Position

    /// Collapsed: a quiet sliver (like the home indicator). Hover: morphs into a capsule with the hint.
    private var bottomBody: some View {
        ZStack {
            if viewModel.isHovered {
                hint
                    .transition(.opacity.animation(.easeOut(duration: 0.15).delay(0.06)))
            }
        }
        .padding(.horizontal, viewModel.isHovered ? 14 : 0)
        .frame(width: viewModel.isHovered ? nil : 44, height: viewModel.isHovered ? 30 : 6)
        .background(
            Capsule()
                .fill(viewModel.isHovered ? DesignSystem.Colors.pillBackground : Color(white: 0.22, opacity: 0.85))
                .overlay(Capsule().strokeBorder(DesignSystem.Colors.pillBorder, lineWidth: 0.5))
                .shadow(color: .black.opacity(viewModel.isHovered ? 0.28 : 0.15), radius: viewModel.isHovered ? 10 : 3, y: viewModel.isHovered ? 4 : 1)
        )
        .animation(DesignSystem.Animation.overlayMorph, value: viewModel.isHovered)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Notch Position

    /// Invisible while idle: an opaque black shape inset inside the hardware notch, so it
    /// is never seen but still makes the window server route hover/clicks to this panel
    /// (fully transparent pixels pass mouse events through). On hover the notch grows
    /// outward and down to reveal the hint below the camera.
    private var notchBody: some View {
        let expanded = viewModel.isHovered
        return VStack(spacing: 0) {
            Color.clear.frame(height: expanded ? viewModel.notchHeight : max(viewModel.notchHeight - 4, 0))
            if expanded {
                hint
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                    .transition(.opacity.animation(.easeOut(duration: 0.15).delay(0.08)))
            }
        }
        .frame(width: max(viewModel.notchGapWidth + (expanded ? 112 : -10), 0))
        .background(
            NotchShape(topRadius: expanded ? 6 : 0, bottomRadius: expanded ? 18 : 8)
                .fill(.black)
        )
        .animation(DesignSystem.Animation.overlayMorph, value: expanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Hint

    private var hint: some View {
        HStack(spacing: 5) {
            Text("Click or hold")
            OverlayKeycap(HotkeyTrigger.current.shortSymbol)
            Text("to dictate")
        }
        .font(DesignSystem.Typography.overlayLabel)
        .foregroundStyle(DesignSystem.Colors.overlaySecondary)
        .fixedSize()
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

            IdlePillView(viewModel: {
                let vm = IdlePillViewModel()
                vm.isTopPosition = true
                vm.notchGapWidth = 185
                vm.notchHeight = 32
                vm.isHovered = true
                return vm
            }())
        }
        .padding(30)
        .frame(width: 400, height: 320)
        .background(Color.gray.opacity(0.3))
    }
}
