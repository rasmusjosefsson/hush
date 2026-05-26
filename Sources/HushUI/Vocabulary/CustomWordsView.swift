import SwiftUI
import HushCore
import HushViewModels

struct CustomWordsView: View {
    @Bindable var viewModel: CustomWordsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var hoveredWordID: UUID?
    @FocusState private var wordFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Custom Words")
                    .font(DesignSystem.Typography.sectionTitle)
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.sm)

            // Fixed header (stats + add form)
            headerCard
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.md)

            // Scrollable rules list
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    wordsCard
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)
            }
        }
        .background(DesignSystem.Colors.background)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .alert(
            "Delete Word?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteWord != nil },
                set: { if !$0 { viewModel.pendingDeleteWord = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeleteWord = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            if let word = viewModel.pendingDeleteWord {
                Text("Delete \"\(word.word)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Add Form

    private var headerCard: some View {
        managementCard(
            title: "Add Word Rule",
            subtitle: "Adds to the word rules list.",
            icon: "plus.circle"
        ) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.errorRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    TextField("Word or phrase", text: $viewModel.newWord)
                        .textFieldStyle(.roundedBorder)
                        .focused($wordFieldFocused)
                    TextField("Replacement (optional)", text: $viewModel.newReplacement)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        viewModel.addWord()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                    .disabled(viewModel.newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Rules (with inline search)

    private var wordsCard: some View {
        managementCard(
            title: "Word Rules",
            subtitle: "Toggle to enable or disable each rule.",
            icon: "list.bullet"
        ) {
            if !viewModel.words.isEmpty {
                TextField("Search words...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
            }

            if viewModel.filteredWords.isEmpty {
                emptyWordsState
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(viewModel.filteredWords) { word in
                        wordRow(word)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func wordRow(_ word: CustomWord) -> some View {
        let isHovered = hoveredWordID == word.id
        return HStack(spacing: DesignSystem.Spacing.md) {
            Toggle("", isOn: Binding(
                get: { word.isEnabled },
                set: { _ in viewModel.toggleEnabled(word) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 3) {
                Text(word.word)
                    .font(DesignSystem.Typography.body)
                    .opacity(word.isEnabled ? 1.0 : 0.55)

                if let replacement = word.replacement {
                    Text("Replaces with: \(replacement)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enforces exact spelling")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                viewModel.pendingDeleteWord = word
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(isHovered ? DesignSystem.Colors.rowHoverBackground : DesignSystem.Colors.surfaceElevated)
        )
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.hoverTransition) {
                hoveredWordID = hovering ? word.id : nil
            }
        }
    }

    private var emptyWordsState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            Image(systemName: viewModel.words.isEmpty ? "character.textbox" : "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DesignSystem.Colors.accent)
                .opacity(0.5)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(viewModel.words.isEmpty ? "No custom words yet" : "No matches")
                    .font(DesignSystem.Typography.pageTitle)
                    .foregroundStyle(.primary)
                if viewModel.words.isEmpty {
                    Text("Add words to fix spelling or capitalization that the speech engine gets wrong.")
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Reusable

    private func managementCard<Content: View>(
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
        )
    }
}

// MARK: - Preview

struct CustomWordsView_Previews: PreviewProvider {
    static var previews: some View {
        let vm = CustomWordsViewModel()
        vm.words = [
            CustomWord(word: "hush", replacement: "Hush"),
            CustomWord(word: "openai", replacement: "OpenAI"),
            CustomWord(word: "kubernetes", replacement: nil, isEnabled: false),
        ]

        return CustomWordsView(viewModel: vm)
            .frame(width: 620, height: 500)
    }
}
