import HushCore
import HushViewModels
import SwiftUI

struct TranscriptResultView: View {
    let transcription: Transcription
    @Bindable var viewModel: TranscriptionViewModel
    var onNavigateBack: (() -> Void)?

    @State private var copiedToClipboard = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if onNavigateBack != nil {
                    Button {
                        viewModel.currentTranscription = nil
                        onNavigateBack?()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(transcription.fileName)
                        .font(DesignSystem.Typography.body.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        if let duration = transcription.durationMs {
                            Text(formatDuration(duration))
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let count = transcription.speakerCount, count > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(count) speaker\(count == 1 ? "" : "s")")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Menu("Download") {
                    Button("Plain Text (.txt)") {
                        viewModel.downloadTranscriptionAsTxt(transcription)
                    }

                    Button("Markdown (.md)") {
                        viewModel.downloadTranscriptionAsMarkdown(transcription)
                    }
                }
                .menuStyle(.borderlessButton)

                // Copy button
                Button {
                    viewModel.copyToClipboard(transcription)
                    copiedToClipboard = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedToClipboard = false
                    }
                } label: {
                    Label(copiedToClipboard ? "Copied!" : "Copy", systemImage: copiedToClipboard ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding(DesignSystem.Spacing.lg)

            Divider()

            // Transcript content
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    if let speakers = transcription.speakers, !speakers.isEmpty,
                       let words = transcription.wordTimestamps, !words.isEmpty {
                        // Speaker-annotated transcript
                        speakerTranscript(speakers: speakers, words: words)
                    } else {
                        // Plain transcript
                        Text(transcription.cleanTranscript ?? transcription.rawTranscript ?? "No transcript available.")
                            .font(DesignSystem.Typography.body)
                            .textSelection(.enabled)
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
    }

    // MARK: - Speaker Transcript

    @ViewBuilder
    private func speakerTranscript(speakers: [SpeakerInfo], words: [WordTimestamp]) -> some View {
        let speakerMap = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.label) })
        let segments = groupWordsBySpeaker(words)

        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(speakerMap[segment.speakerId] ?? segment.speakerId)
                        .font(DesignSystem.Typography.caption.weight(.bold))
                        .foregroundStyle(DesignSystem.Colors.accent)

                    if let startMs = segment.words.first?.startMs {
                        Text(formatTimestamp(startMs))
                            .font(DesignSystem.Typography.micro)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(segment.words.map(\.word).joined(separator: " "))
                    .font(DesignSystem.Typography.body)
                    .textSelection(.enabled)
            }
            .padding(.bottom, DesignSystem.Spacing.sm)
        }
    }

    private struct SpeakerSegment {
        let speakerId: String
        var words: [WordTimestamp]
    }

    private func groupWordsBySpeaker(_ words: [WordTimestamp]) -> [SpeakerSegment] {
        var segments: [SpeakerSegment] = []
        var current: SpeakerSegment?

        for word in words {
            let sid = word.speakerId ?? "unknown"
            if current?.speakerId == sid {
                current?.words.append(word)
            } else {
                if let c = current { segments.append(c) }
                current = SpeakerSegment(speakerId: sid, words: [word])
            }
        }
        if let c = current { segments.append(c) }
        return segments
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatTimestamp(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Previews

struct TranscriptResultView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Plain transcript (no speakers)
            TranscriptResultView(
                transcription: Transcription(
                    fileName: "Interview Recording.m4a",
                    durationMs: 185_000,
                    cleanTranscript: "Hello and welcome to today's episode. We're going to be discussing the future of artificial intelligence and its impact on creative work. I think there's a lot to unpack here, so let's dive right in.",
                    status: .completed
                ),
                viewModel: TranscriptionViewModel()
            )
            .previewDisplayName("Plain Transcript")

            // Speaker-annotated transcript
            TranscriptResultView(
                transcription: Transcription(
                    fileName: "Team Standup.mp3",
                    durationMs: 420_000,
                    cleanTranscript: "Let's go around. What did everyone work on yesterday?",
                    wordTimestamps: [
                        WordTimestamp(word: "Let's", startMs: 0, endMs: 200, confidence: 0.95, speakerId: "S1"),
                        WordTimestamp(word: "go", startMs: 200, endMs: 350, confidence: 0.97, speakerId: "S1"),
                        WordTimestamp(word: "around.", startMs: 350, endMs: 600, confidence: 0.93, speakerId: "S1"),
                        WordTimestamp(word: "I", startMs: 2000, endMs: 2100, confidence: 0.98, speakerId: "S2"),
                        WordTimestamp(word: "worked", startMs: 2100, endMs: 2400, confidence: 0.96, speakerId: "S2"),
                        WordTimestamp(word: "on", startMs: 2400, endMs: 2500, confidence: 0.99, speakerId: "S2"),
                        WordTimestamp(word: "the", startMs: 2500, endMs: 2600, confidence: 0.98, speakerId: "S2"),
                        WordTimestamp(word: "API.", startMs: 2600, endMs: 2900, confidence: 0.94, speakerId: "S2"),
                    ],
                    speakerCount: 2,
                    speakers: [
                        SpeakerInfo(id: "S1", label: "Alice"),
                        SpeakerInfo(id: "S2", label: "Bob"),
                    ],
                    status: .completed
                ),
                viewModel: TranscriptionViewModel()
            )
            .previewDisplayName("Speaker Transcript")
        }
        .frame(width: 550, height: 400)
    }
}
