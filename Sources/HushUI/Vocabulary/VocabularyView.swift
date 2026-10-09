import SwiftUI
import HushCore
import HushViewModels

struct VocabularyView: View {
    @Bindable var settingsViewModel: SettingsViewModel
    @Bindable var customWordsViewModel: CustomWordsViewModel
    @Bindable var textSnippetsViewModel: TextSnippetsViewModel

    @State private var showCustomWords = false
    @State private var showTextSnippets = false

    private var selectedMode: Dictation.ProcessingMode {
        Dictation.ProcessingMode(rawValue: settingsViewModel.processingMode) ?? .raw
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    IconTile(item: .vocabulary, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI Processing")
                            .font(.headline)
                        Text("Clean up dictated text on your Mac before it's pasted. Nothing leaves your device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack(spacing: DesignSystem.Spacing.lg) {
                    Spacer(minLength: 0)
                    modeOption(.raw, title: "Raw", detail: "Exactly as spoken")
                    modeOption(.clean, title: "AI Processed", detail: "Polished text")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DesignSystem.Spacing.sm)
            } header: {
                Text("Mode")
            } footer: {
                Text(selectedMode == .raw
                     ? "Text is pasted exactly as you speak it. Takes effect on your next dictation."
                     : "Takes effect on your next dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedMode != .raw {
                Section {
                    pipelineStep("Remove fillers", detail: "um, uh, umm, uhh", icon: "eraser")
                    pipelineStep(
                        "Fix words",
                        detail: "\(settingsViewModel.customWordCount) custom correction\(settingsViewModel.customWordCount == 1 ? "" : "s")",
                        icon: "character.cursor.ibeam"
                    ) {
                        customWordsViewModel.loadWords()
                        showCustomWords = true
                    }
                    pipelineStep(
                        "Expand snippets",
                        detail: "\(settingsViewModel.snippetCount) phrase snippet\(settingsViewModel.snippetCount == 1 ? "" : "s")",
                        icon: "text.insert"
                    ) {
                        textSnippetsViewModel.loadSnippets()
                        showTextSnippets = true
                    }
                    pipelineStep("Clean whitespace", detail: "Fixes spacing and punctuation boundaries", icon: "text.alignleft")
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Runs in order on every dictation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Processing")
        .sheet(isPresented: $showCustomWords) {
            settingsViewModel.refreshStats()
        } content: {
            CustomWordsView(viewModel: customWordsViewModel)
                .frame(minWidth: 620, minHeight: 460)
        }
        .sheet(isPresented: $showTextSnippets) {
            settingsViewModel.refreshStats()
        } content: {
            TextSnippetsView(viewModel: textSnippetsViewModel)
                .frame(minWidth: 620, minHeight: 460)
        }
        .onAppear {
            settingsViewModel.refreshStats()
        }
    }

    // MARK: - Pieces

    /// Selectable tile in the style of System Settings > Appearance (Light / Dark / Auto).
    private func modeOption(_ mode: Dictation.ProcessingMode, title: String, detail: String) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            settingsViewModel.processingMode = mode.rawValue
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(mode == .raw ? Color.primary.opacity(0.06) : DesignSystem.Colors.accent.opacity(0.14))
                    if mode == .raw {
                        BrandWaveformView(size: 30, color: .secondary)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.accent)
                    }
                }
                .frame(width: 128, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? DesignSystem.Colors.accent : Color.primary.opacity(0.1),
                                      lineWidth: isSelected ? 3 : 0.5)
                        .padding(isSelected ? -3 : 0)
                )
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func pipelineStep(_ title: String, detail: String, icon: String, manage: (() -> Void)? = nil) -> some View {
        LabeledContent {
            if let manage {
                Button("Manage…", action: manage)
            }
        } label: {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(DesignSystem.Colors.accent)
            }
        }
    }
}

// MARK: - Preview

struct VocabularyView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = SettingsViewModel()
        settings.customWordCount = 5
        settings.snippetCount = 3
        settings.processingMode = Dictation.ProcessingMode.clean.rawValue

        return VocabularyView(
            settingsViewModel: settings,
            customWordsViewModel: CustomWordsViewModel(),
            textSnippetsViewModel: TextSnippetsViewModel()
        )
        .frame(width: 600, height: 700)
    }
}
