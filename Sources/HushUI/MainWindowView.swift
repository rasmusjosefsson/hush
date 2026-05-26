import SwiftUI
import HushCore
import HushViewModels

public enum SidebarItem: String, CaseIterable, Identifiable {
    case transcribe = "Transcribe"
    case library = "Library"
    case dictations = "Dictations"
    case vocabulary = "AI Processing"
    case settings = "Settings"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .transcribe: return "waveform"
        case .library: return "square.grid.2x2"
        case .dictations: return "clock.arrow.circlepath"
        case .vocabulary: return "wand.and.stars"
        case .settings: return "gearshape"
        }
    }

    public static let primaryItems: [SidebarItem] = [.transcribe, .library, .dictations]
    public static let configItems: [SidebarItem] = [.vocabulary, .settings]
}

public struct MainWindowView: View {
    @Bindable var state: MainWindowState

    let transcriptionViewModel: TranscriptionViewModel
    let historyViewModel: DictationHistoryViewModel
    let settingsViewModel: SettingsViewModel
    let customWordsViewModel: CustomWordsViewModel
    let textSnippetsViewModel: TextSnippetsViewModel
    let libraryViewModel: TranscriptionLibraryViewModel

    public init(state: MainWindowState, transcriptionViewModel: TranscriptionViewModel, historyViewModel: DictationHistoryViewModel, settingsViewModel: SettingsViewModel, customWordsViewModel: CustomWordsViewModel, textSnippetsViewModel: TextSnippetsViewModel, libraryViewModel: TranscriptionLibraryViewModel) {
        self.state = state
        self.transcriptionViewModel = transcriptionViewModel
        self.historyViewModel = historyViewModel
        self.settingsViewModel = settingsViewModel
        self.customWordsViewModel = customWordsViewModel
        self.textSnippetsViewModel = textSnippetsViewModel
        self.libraryViewModel = libraryViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                List(selection: $state.selectedItem) {
                    Section {
                        ForEach(SidebarItem.primaryItems) { item in
                            sidebarLabel(for: item)
                                .tag(item)
                        }
                    }

                    Section {
                        ForEach(SidebarItem.configItems) { item in
                            sidebarLabel(for: item)
                                .tag(item)
                        }
                    }
                }
                .listStyle(.sidebar)
                .tint(DesignSystem.Colors.accent)
                .frame(minWidth: 150)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                Group {
                    switch state.selectedItem {
                    case .transcribe:
                        TranscribeView(viewModel: transcriptionViewModel, showingProgressDetail: $state.showingProgressDetail, onNavigateBack: { state.navigateBack() })
                    case .library:
                        TranscriptionLibraryView(viewModel: libraryViewModel) { transcription in
                            transcriptionViewModel.currentTranscription = transcription
                            state.navigateToTranscription(from: .library)
                        }
                    case .dictations:
                        DictationHistoryView(viewModel: historyViewModel)
                    case .vocabulary:
                        VocabularyView(
                            settingsViewModel: settingsViewModel,
                            customWordsViewModel: customWordsViewModel,
                            textSnippetsViewModel: textSnippetsViewModel
                        )
                    case .settings:
                        SettingsView(viewModel: settingsViewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.background)
            }
            .navigationSplitViewStyle(.balanced)

            if showGlobalProgressBar {
                globalTranscriptionBottomBar
            }
        }
        .frame(
            minWidth: 860,
            minHeight: DesignSystem.Layout.windowMinHeight
        )
        .onChange(of: state.selectedItem) { _, newItem in
            // Update the window title to show the current page name
            NSApplication.shared.mainWindow?.title = newItem.rawValue
        }
        .onChange(of: transcriptionViewModel.isTranscribing) { _, isTranscribing in
            if !isTranscribing {
                state.showingProgressDetail = false
            }
        }
    }

    @ViewBuilder
    private func sidebarLabel(for item: SidebarItem) -> some View {
        if item == .transcribe {
            Label {
                Text(item.rawValue)
            } icon: {
                BrandWaveformView(size: 16, color: .primary)
            }
        } else {
            Label(item.rawValue, systemImage: item.icon)
        }
    }

    private var showGlobalProgressBar: Bool {
        transcriptionViewModel.isTranscribing
            && state.selectedItem != .transcribe
    }

    private var globalTranscriptionBottomBar: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(transcriptionViewModel.transcribingFileName)
                        .font(DesignSystem.Typography.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("On-device")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignSystem.Colors.successGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignSystem.Colors.successGreen.opacity(0.12)))
                }

                Text(transcriptionViewModel.progressHeadline)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let fraction = transcriptionViewModel.transcriptionProgress {
                Spacer(minLength: DesignSystem.Spacing.sm)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(DesignSystem.Typography.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)

                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(DesignSystem.Colors.accent)
                        .frame(width: 96)
                }
            }

            Spacer()

            Button {
                transcriptionViewModel.currentTranscription = nil
                state.selectedItem = .transcribe
            } label: {
                Text("View")
                    .font(DesignSystem.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Layout.buttonCornerRadius)
                            .fill(DesignSystem.Colors.accent.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.cardBackground)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - Previews

struct MainWindowView_Previews: PreviewProvider {
    static var previews: some View {
        MainWindowView(
            state: MainWindowState(),
            transcriptionViewModel: TranscriptionViewModel(),
            historyViewModel: DictationHistoryViewModel(),
            settingsViewModel: SettingsViewModel(),
            customWordsViewModel: CustomWordsViewModel(),
            textSnippetsViewModel: TextSnippetsViewModel(),
            libraryViewModel: TranscriptionLibraryViewModel()
        )
    }
}
