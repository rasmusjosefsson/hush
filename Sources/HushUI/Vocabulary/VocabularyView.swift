import SwiftUI
import HushCore
import HushViewModels

struct VocabularyView: View {
    @Bindable var settingsViewModel: SettingsViewModel
    @Bindable var customWordsViewModel: CustomWordsViewModel
    @Bindable var textSnippetsViewModel: TextSnippetsViewModel

    @State private var showCustomWords = false
    @State private var showTextSnippets = false
    @State private var hoveredModeTitle: String?

    private var selectedMode: Dictation.ProcessingMode {
        Dictation.ProcessingMode(rawValue: settingsViewModel.processingMode) ?? .raw
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                modeSelectionCard
                if selectedMode == .raw {
                    rawModeMessage
                } else {
                    pipelineCard
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.background)
        .navigationTitle("AI Processing")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Color.clear.frame(width: 0, height: 0)
            }
        }
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

    // MARK: - Mode Selection

    private var modeSelectionCard: some View {
        vocabularyCard(
            title: "Processing Mode",
            subtitle: "Switch anytime. Takes effect on your next dictation.",
            icon: "slider.horizontal.3"
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md)],
                spacing: DesignSystem.Spacing.md
            ) {
                modeCard(
                    title: "Raw",
                    subtitle: "As spoken",
                    detail: "Exactly as you spoke it. No corrections applied.",
                    icon: "waveform",
                    isSelected: selectedMode == .raw
                ) {
                    settingsViewModel.processingMode = Dictation.ProcessingMode.raw.rawValue
                }

                modeCard(
                    title: "AI Processed",
                    subtitle: "Polished",
                    detail: "Polishes your text — removes fillers, fixes words, expands snippets.",
                    icon: "sparkles",
                    isSelected: selectedMode == .clean
                ) {
                    settingsViewModel.processingMode = Dictation.ProcessingMode.clean.rawValue
                }

            }
        }
    }

    // MARK: - Pipeline Cards

    private var pipelineCard: some View {
        vocabularyCard(
            title: "Processing Pipeline",
            subtitle: "Runs in order on every dictation. All local.",
            icon: "list.number"
        ) {
            VStack(spacing: 0) {
                pipelineStep(
                    title: "Remove fillers",
                    detail: "um, uh, umm, uhh",
                    actionTitle: nil,
                    action: nil
                )

                dividerLine

                pipelineStep(
                    title: "Fix words",
                    detail: "\(settingsViewModel.customWordCount) custom correction\(settingsViewModel.customWordCount == 1 ? "" : "s")",
                    actionTitle: "Manage words",
                    action: {
                        customWordsViewModel.loadWords()
                        showCustomWords = true
                    }
                )

                dividerLine

                pipelineStep(
                    title: "Expand snippets",
                    detail: "\(settingsViewModel.snippetCount) phrase snippet\(settingsViewModel.snippetCount == 1 ? "" : "s")",
                    actionTitle: "Manage snippets",
                    action: {
                        textSnippetsViewModel.loadSnippets()
                        showTextSnippets = true
                    }
                )

                dividerLine

                pipelineStep(
                    title: "Clean whitespace",
                    detail: "Fixes spacing and punctuation boundaries",
                    actionTitle: nil,
                    action: nil
                )
            }
            .padding(.top, 2)
        }
    }

    private var rawModeMessage: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Text("Text is pasted exactly as you speak it.")
                .font(DesignSystem.Typography.bodySmall)
                .foregroundStyle(.secondary)
            Text("Switch to AI Processed for post-processing options.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DesignSystem.Spacing.md)
    }

    // MARK: - Reusable

    private var dividerLine: some View {
        Divider()
            .padding(.leading, 48)
    }

    private func vocabularyCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignSystem.Colors.accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Typography.sectionTitle)
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .fill(DesignSystem.Colors.cardBackground)
                .cardShadow(DesignSystem.Shadows.cardRest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(
                    DesignSystem.Colors.border.opacity(0.6),
                    lineWidth: 0.5
                )
        )
    }

    private func modeCard(
        title: String,
        subtitle: String,
        detail: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredModeTitle == title
        return Button(action: action) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack {
                    if icon == "waveform" {
                        BrandWaveformView(size: 16, color: isSelected ? DesignSystem.Colors.accent : .secondary)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? DesignSystem.Colors.accent : .secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(DesignSystem.Colors.successGreen)
                    }
                }

                Text(title)
                    .font(DesignSystem.Typography.sectionTitle)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)

                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                    .fill(isSelected ? DesignSystem.Colors.accentLight : DesignSystem.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                    .strokeBorder(
                        isSelected ? DesignSystem.Colors.accent.opacity(0.5) : DesignSystem.Colors.border,
                        lineWidth: isSelected ? 1.2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.hoverTransition) {
                hoveredModeTitle = hovering ? title : nil
            }
        }
    }

    private func pipelineStep(
        title: String,
        detail: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Circle()
                .fill(DesignSystem.Colors.accent)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.body)
                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .font(DesignSystem.Typography.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(DesignSystem.Colors.accent)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
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
