import SwiftUI
import UniformTypeIdentifiers
import HushCore
import HushViewModels

struct TranscribeView: View {
    @Bindable var viewModel: TranscriptionViewModel
    @Binding var showingProgressDetail: Bool
    var onNavigateBack: (() -> Void)?

    var body: some View {
        Group {
            if let transcription = viewModel.currentTranscription {
                TranscriptResultView(
                    transcription: transcription,
                    viewModel: viewModel,
                    onNavigateBack: onNavigateBack
                )
            } else if viewModel.isTranscribing {
                progressView
            } else {
                dropZoneView
            }
        }
        .navigationTitle("Transcribe")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()

            PortalDropZone(
                isDragging: $viewModel.isDragging,
                onDrop: { providers in
                    viewModel.handleFileDrop(providers: providers, onAccepted: {
                        SoundManager.shared.play(.fileDropped)
                    })
                },
                onBrowse: { }
            )

            if let error = viewModel.errorMessage {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text(viewModel.progressHeadline)
                .font(DesignSystem.Typography.body.weight(.semibold))

            if let subline = viewModel.progressSubline {
                Text(subline)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            if let fraction = viewModel.transcriptionProgress {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)

                Text("\(Int((fraction * 100).rounded()))%")
                    .font(DesignSystem.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button("Cancel") {
                viewModel.cancelTranscription()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

struct TranscribeView_Previews: PreviewProvider {
    static var previews: some View {
        // Default state shows the drop zone (no transcription in progress, no result)
        TranscribeView(
            viewModel: TranscriptionViewModel(),
            showingProgressDetail: .constant(false)
        )
        .frame(width: 500, height: 450)
        .previewDisplayName("Drop Zone (Idle)")
    }
}
