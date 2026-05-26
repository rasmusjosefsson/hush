import SwiftUI
import HushCore
import HushViewModels

struct TranscriptionLibraryView: View {
    @Bindable var viewModel: TranscriptionLibraryViewModel
    var onSelect: (Transcription) -> Void

    @State private var pendingDelete: Transcription?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Filter bar
            HStack(spacing: 0) {
                ForEach(LibraryFilter.allCases, id: \.self) { filter in
                    Button {
                        viewModel.filter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(DesignSystem.Typography.bodySmall.weight(
                                viewModel.filter == filter ? .semibold : .regular
                            ))
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(viewModel.filter == filter
                                          ? DesignSystem.Colors.accent.opacity(0.12)
                                          : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewModel.filter == filter ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.sm)

            // Grid
            if viewModel.filteredTranscriptions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: DesignSystem.Layout.thumbnailCardMinWidth), spacing: DesignSystem.Spacing.md)],
                        spacing: DesignSystem.Spacing.md
                    ) {
                        ForEach(viewModel.filteredTranscriptions) { transcription in
                            TranscriptionThumbnailCard(transcription: transcription, searchText: viewModel.searchText, onTap: {
                                onSelect(transcription)
                            }, contextMenu: {
                                libraryMenuItems(for: transcription)
                            })
                            .contextMenu {
                                libraryMenuItems(for: transcription)
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.lg)
                }
            }
        }
        .onAppear {
            viewModel.loadTranscriptions()
        }
        .searchable(text: $viewModel.searchText, prompt: "Search transcriptions")
        .alert(
            "Delete Transcription?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let transcription = pendingDelete {
                    viewModel.deleteTranscription(transcription)
                    pendingDelete = nil
                }
            }
        } message: {
            if let pending = pendingDelete {
                Text("\"\(pending.fileName)\" will be permanently deleted.")
            }
        }
    }

    @ViewBuilder
    private func libraryMenuItems(for transcription: Transcription) -> some View {
        Button {
            onSelect(transcription)
        } label: {
            Label("Open", systemImage: "doc.text")
        }

        Button {
            viewModel.toggleFavorite(transcription)
        } label: {
            Label(
                transcription.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: transcription.isFavorite ? "star.slash" : "star"
            )
        }

        Divider()

        Button(role: .destructive) {
            pendingDelete = transcription
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            Image(systemName: viewModel.searchText.isEmpty ? "doc.text" : "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DesignSystem.Colors.accent)
                .opacity(0.5)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(viewModel.searchText.isEmpty
                     ? "No transcriptions yet"
                     : "No matching transcriptions")
                    .font(DesignSystem.Typography.pageTitle)
                    .foregroundStyle(.primary)
                Text(viewModel.searchText.isEmpty
                     ? "Transcribe a file to get started."
                     : "Try different words or clear your search.")
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

struct TranscriptionLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Empty state
            TranscriptionLibraryView(
                viewModel: TranscriptionLibraryViewModel(),
                onSelect: { _ in }
            )
            .previewDisplayName("Empty")

            // Populated state
            TranscriptionLibraryView(
                viewModel: {
                    let vm = TranscriptionLibraryViewModel()
                    vm.transcriptions = [
                        Transcription(
                            fileName: "Interview Recording.m4a",
                            durationMs: 185_000,
                            cleanTranscript: "Hello and welcome to today's episode...",
                            status: .completed,
                            isFavorite: true
                        ),
                        Transcription(
                            fileName: "Meeting Notes 2024.mp3",
                            durationMs: 3_600_000,
                            cleanTranscript: "Let's start with the quarterly review.",
                            status: .completed,
                            sourceURL: "https://example.com/video"
                        ),
                        Transcription(
                            fileName: "Lecture.wav",
                            durationMs: 2_700_000,
                            status: .completed
                        ),
                    ]
                    return vm
                }(),
                onSelect: { _ in }
            )
            .previewDisplayName("Populated")
        }
        .frame(width: 600, height: 500)
    }
}
