import SwiftUI
import HushCore

/// Simplified thumbnail card for transcription grid.
struct TranscriptionThumbnailCard<MenuContent: View>: View {
    let transcription: Transcription
    let searchText: String
    let onTap: () -> Void
    @ViewBuilder let contextMenu: () -> MenuContent

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // File icon placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 100)
                    .overlay {
                        if transcription.sourceURL != nil {
                            Image(systemName: "play.rectangle")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        } else {
                            BrandWaveformView(size: 32, color: .secondary)
                        }
                    }

                Text(transcription.fileName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)

                if let duration = transcription.durationMs {
                    Text(formatDuration(duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .contextMenu { contextMenu() }
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Previews

struct TranscriptionThumbnailCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Local file card
            TranscriptionThumbnailCard(
                transcription: Transcription(
                    fileName: "Interview Recording.m4a",
                    durationMs: 185_000,
                    status: .completed
                ),
                searchText: "",
                onTap: { },
                contextMenu: { EmptyView() }
            )

            // Remote source card (shows play icon)
            TranscriptionThumbnailCard(
                transcription: Transcription(
                    fileName: "Conference Talk.mp4",
                    durationMs: 3_600_000,
                    status: .completed,
                    sourceURL: "https://example.com/video.mp4"
                ),
                searchText: "",
                onTap: { },
                contextMenu: { EmptyView() }
            )
        }
        .padding()
        .frame(width: 250)
        .background(Color.gray.opacity(0.15))
    }
}
