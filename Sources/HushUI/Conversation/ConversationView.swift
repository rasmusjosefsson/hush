import HushCore
import HushViewModels
import SwiftUI
import UniformTypeIdentifiers

public struct ConversationView: View {
    @Bindable var viewModel: ConversationViewModel
    @State private var choosingReference = false
    @State private var localTestText = ""

    public init(viewModel: ConversationViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            HStack {
                Text("Listen locally, draft with Ollama, and reply in your voice.")
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                Button(viewModel.isRunning ? "Stop" : "Start") {
                    viewModel.isRunning ? viewModel.stop() : viewModel.start()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !viewModel.isRunning
                        && (viewModel.referenceAudioURL == nil || viewModel.availabilityError != nil)
                )
            }

            Picker("Mode", selection: $viewModel.mode) {
                Text("Local test").tag(ConversationMode.localTest)
                Text("Live system audio").tag(ConversationMode.liveSystemAudio)
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isRunning)

            HStack {
                Label(
                    viewModel.referenceAudioURL?.lastPathComponent ?? "No voice reference selected",
                    systemImage: "waveform"
                )
                .font(DesignSystem.Typography.bodySmall)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                Button("Choose WAV...") { choosingReference = true }
                    .disabled(viewModel.isRunning)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius))

            if let availabilityError = viewModel.availabilityError {
                Text(availabilityError)
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(DesignSystem.Colors.errorRed)
            }

            stateBanner

            if viewModel.mode == .localTest, viewModel.isRunning {
                HStack(alignment: .bottom, spacing: DesignSystem.Spacing.sm) {
                    TextField("What should the other person say?", text: $localTestText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button("Generate reply") {
                        viewModel.submitLocalTestTurn(localTestText)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        localTestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || viewModel.state == .starting
                    )
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    if viewModel.remoteTurns.isEmpty {
                        Text(emptyStateText)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                    } else {
                        ForEach(Array(viewModel.remoteTurns.enumerated()), id: \.offset) { _, turn in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("THEM")
                                    .font(DesignSystem.Typography.caption.weight(.semibold))
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                Text(turn)
                                    .font(DesignSystem.Typography.body)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius))
                        }
                    }
                }
            }

            if let draft = viewModel.draft {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("Suggested reply")
                        .font(DesignSystem.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text(draft.text)
                        .font(DesignSystem.Typography.body)
                        .textSelection(.enabled)
                    HStack {
                        Button("Dismiss") { viewModel.dismissDraft() }
                        Button("Regenerate") { viewModel.regenerate() }
                        Spacer()
                        Button("Speak") { viewModel.speak() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(DesignSystem.Spacing.lg)
                .background(DesignSystem.Colors.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius))
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .navigationTitle("Conversation")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .fileImporter(
            isPresented: $choosingReference,
            allowedContentTypes: [.wav],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.selectReferenceAudio(url)
            }
        }
    }

    private var emptyStateText: String {
        if !viewModel.isRunning { return "Press Start when the conversation begins." }
        return viewModel.mode == .localTest
            ? "Enter a pretend incoming message above."
            : "Listening for system audio..."
    }

    @ViewBuilder
    private var stateBanner: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .starting:
            status("Preparing your local voice. First start can take about 45 seconds.", progress: true)
        case .listening:
            status(
                viewModel.mode == .localTest ? "Ready for a local test" : "Listening to system audio",
                progress: false
            )
        case .drafting:
            status("Writing a local reply...", progress: true)
        case .draftReady:
            EmptyView()
        case .speaking:
            status("Speaking through Mac output. Capture is paused.", progress: true)
        case .failed(let message):
            Text(message)
                .font(DesignSystem.Typography.bodySmall)
                .foregroundStyle(DesignSystem.Colors.errorRed)
        }
    }

    private func status(_ text: String, progress: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if progress { ProgressView().controlSize(.small) }
            Circle()
                .fill(DesignSystem.Colors.successGreen)
                .frame(width: 7, height: 7)
            Text(text).font(DesignSystem.Typography.bodySmall)
        }
    }
}
