import SwiftUI

/// Row of color swatches in the style of System Settings > Appearance > Accent color.
struct AccentSwatchPicker: View {
    @Binding var selection: AccentChoice
    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentChoice.allCases) { choice in
                swatch(choice)
            }
        }
    }

    private func swatch(_ choice: AccentChoice) -> some View {
        Button {
            selection = choice
        } label: {
            ZStack {
                if choice == .system {
                    Circle().fill(AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                        center: .center
                    ))
                } else {
                    Circle().fill(choice.color)
                }
                Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
                if selection == choice {
                    Circle().fill(.white).frame(width: 6, height: 6)
                }
            }
            .frame(width: 16, height: 16)
            .padding(2)
            .overlay(Circle().strokeBorder(selection == choice ? choice.color.opacity(0.45) : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(choice.label)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(selection == choice ? .isSelected : [])
    }
}
