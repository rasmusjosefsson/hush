import SwiftUI
import HushCore
import HushViewModels

struct TextSnippetsView: View {
    @Bindable var viewModel: TextSnippetsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var hoveredSnippetID: UUID?
    @State private var guidanceExpanded = false
    @FocusState private var triggerFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Text Snippets")
                    .font(DesignSystem.Typography.sectionTitle)
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.sm)

            // Fixed header (stats + add form + guidance)
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                statsAndAddCard
                guidanceSection
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.md)

            // Scrollable rules list
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    snippetsCard
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
            "Delete Snippet?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteSnippet != nil },
                set: { if !$0 { viewModel.pendingDeleteSnippet = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeleteSnippet = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            if let snippet = viewModel.pendingDeleteSnippet {
                Text("Delete \"\(snippet.trigger)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Add Form

    private var statsAndAddCard: some View {
        managementCard(
            title: "Add Snippet Rule",
            subtitle: "Adds to the snippet rules list.",
            icon: "text.insert"
        ) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.errorRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    TextField("Trigger phrase", text: $viewModel.newTrigger)
                        .textFieldStyle(.roundedBorder)
                        .focused($triggerFieldFocused)
                    TextField("Expansion", text: $viewModel.newExpansion)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        viewModel.addSnippet()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                    .disabled(
                        viewModel.newTrigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || viewModel.newExpansion.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }
        }
    }

    // MARK: - Guidance (collapsible)

    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DesignSystem.Animation.contentSwap) {
                    guidanceExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.accent)
                    Text("Tips for reliable phrase detection")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: guidanceExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if guidanceExpanded {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.accent)
                        Text("Use natural trigger phrases (for example, \"my signature\") rather than abbreviations, since Hush recognizes natural speech.")
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "return")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.accent)
                        Text("Expansions support line breaks. Use this to insert multi-line text from a single trigger phrase.")
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, DesignSystem.Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
    }

    // MARK: - Snippets (with inline search)

    private var snippetsCard: some View {
        managementCard(
            title: "Snippet Rules",
            subtitle: "Toggle each snippet and track usage volume.",
            icon: "list.bullet"
        ) {
            if !viewModel.snippets.isEmpty {
                TextField("Search snippets...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
            }

            if viewModel.filteredSnippets.isEmpty {
                emptyState
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(viewModel.filteredSnippets) { snippet in
                        snippetRow(snippet)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func snippetRow(_ snippet: TextSnippet) -> some View {
        let isHovered = hoveredSnippetID == snippet.id
        return HStack(spacing: DesignSystem.Spacing.md) {
            Toggle("", isOn: Binding(
                get: { snippet.isEnabled },
                set: { _ in viewModel.toggleEnabled(snippet) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Trigger:")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text("\"\(snippet.trigger)\"")
                        .font(DesignSystem.Typography.body)
                        .opacity(snippet.isEnabled ? 1.0 : 0.55)
                }

                Text("Expands to: \(snippet.expansion.replacingOccurrences(of: "\n", with: " ↵ "))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if snippet.useCount > 0 {
                Text("\(snippet.useCount)")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DesignSystem.Colors.surfaceElevated))
            }

            Button(role: .destructive) {
                viewModel.pendingDeleteSnippet = snippet
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
                hoveredSnippetID = hovering ? snippet.id : nil
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            Image(systemName: viewModel.snippets.isEmpty ? "text.insert" : "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DesignSystem.Colors.accent)
                .opacity(0.5)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(viewModel.snippets.isEmpty ? "No text snippets yet" : "No matches")
                    .font(DesignSystem.Typography.pageTitle)
                    .foregroundStyle(.primary)
                if viewModel.snippets.isEmpty {
                    Text("Say a trigger phrase during dictation and it expands to full text.")
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
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            if let title, let icon {
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
                        if let subtitle {
                            Text(subtitle)
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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

struct TextSnippetsView_Previews: PreviewProvider {
    static var previews: some View {
        let vm = TextSnippetsViewModel()
        vm.snippets = [
            TextSnippet(trigger: "my signature", expansion: "Best regards,\nRasmus Josefsson"),
            TextSnippet(trigger: "my email", expansion: "rasmus@example.com", useCount: 12),
            TextSnippet(trigger: "new paragraph", expansion: "\n\n", isEnabled: false, useCount: 3),
        ]

        return TextSnippetsView(viewModel: vm)
            .frame(width: 620, height: 500)
    }
}
