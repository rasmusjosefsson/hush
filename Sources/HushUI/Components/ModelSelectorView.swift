import SwiftUI

public struct ModelSelectorView: View {
    let currentModel: String
    let displayName: String
    let availableModels: [String]
    var disabled: Bool = false
    let onSelect: (String) -> Void

    public init(currentModel: String, displayName: String, availableModels: [String], disabled: Bool = false, onSelect: @escaping (String) -> Void) {
        self.currentModel = currentModel
        self.displayName = displayName
        self.availableModels = availableModels
        self.disabled = disabled
        self.onSelect = onSelect
    }

    public var body: some View {
        Menu {
            ForEach(availableModels, id: \.self) { model in
                Button {
                    onSelect(model)
                } label: {
                    HStack {
                        Text(model)
                        if model == currentModel {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(displayName)
                    .font(DesignSystem.Typography.micro)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }
}

// MARK: - Previews

struct ModelSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ModelSelectorView(
                currentModel: "large-v3",
                displayName: "large-v3",
                availableModels: ["tiny", "base", "small", "medium", "large-v3"],
                onSelect: { _ in }
            )

            ModelSelectorView(
                currentModel: "tiny",
                displayName: "tiny",
                availableModels: ["tiny", "base", "small"],
                disabled: true,
                onSelect: { _ in }
            )
        }
        .padding()
    }
}
