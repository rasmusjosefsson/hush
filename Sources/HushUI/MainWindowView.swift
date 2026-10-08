import SwiftUI
import HushCore
import HushViewModels

public enum SidebarItem: String, CaseIterable, Identifiable {
    case transcribe = "Transcribe"
    case conversation = "Conversation"
    case library = "Library"
    case dictations = "Dictations"
    case vocabulary = "AI Processing"
    case general = "General"
    case appearance = "Appearance"
    case dictation = "Dictation"
    case speechModel = "Speech Model"
    case privacy = "Privacy & Security"
    case storage = "Storage"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .transcribe: return "waveform"
        case .conversation: return "bubble.left.and.bubble.right.fill"
        case .library: return "square.grid.2x2.fill"
        case .dictations: return "text.bubble.fill"
        case .vocabulary: return "wand.and.stars"
        case .general: return "gearshape.fill"
        case .appearance: return "circle.lefthalf.filled"
        case .dictation: return "mic.fill"
        case .speechModel: return "cpu.fill"
        case .privacy: return "hand.raised.fill"
        case .storage: return "internaldrive.fill"
        }
    }

    /// Tile color, in the style of System Settings' sidebar.
    public var tint: Color {
        switch self {
        case .transcribe: return DesignSystem.Colors.accent
        case .conversation: return Color(nsColor: .systemGreen)
        case .library: return Color(nsColor: .systemOrange)
        case .dictations: return Color(nsColor: .systemBlue)
        case .vocabulary: return Color(nsColor: .systemPurple)
        case .general, .storage: return Color(nsColor: .systemGray)
        case .appearance: return Color(white: 0.12)
        case .dictation: return Color(nsColor: .systemRed)
        case .speechModel: return Color(nsColor: .systemIndigo)
        case .privacy: return Color(nsColor: .systemBlue)
        }
    }

    /// Extra terms the sidebar search matches, like System Settings.
    var keywords: [String] {
        switch self {
        case .transcribe: return ["file", "audio", "video", "youtube"]
        case .conversation: return ["chat", "assistant"]
        case .library: return ["transcriptions", "files"]
        case .dictations: return ["history", "stats"]
        case .vocabulary: return ["words", "snippets", "vocabulary", "ai"]
        case .general: return ["login", "menu bar", "logs", "diagnostics", "about", "onboarding"]
        case .appearance: return ["accent", "color", "notch", "overlay", "theme"]
        case .dictation: return ["shortcut", "hotkey", "microphone", "silence", "sound", "system audio"]
        case .speechModel: return ["parakeet", "whisper", "download", "engine"]
        case .privacy: return ["permissions", "accessibility", "microphone", "screen recording"]
        case .storage: return ["history", "audio", "delete", "clear"]
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || ([rawValue] + keywords).contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// Glyph color on the dark tile (dark mode); graphite items stay light.
    var glyphTint: Color {
        switch self {
        case .general, .storage, .appearance: return Color(white: 0.85)
        default: return tint
        }
    }

    public var settingsPane: SettingsPane? {
        switch self {
        case .general: return .general
        case .appearance: return .appearance
        case .dictation: return .dictation
        case .speechModel: return .speechModel
        case .privacy: return .privacy
        case .storage: return .storage
        default: return nil
        }
    }

    public static let primaryItems: [SidebarItem] = [.transcribe, .conversation, .library, .dictations, .vocabulary]
    public static let settingsItems: [SidebarItem] = [.general, .appearance, .dictation, .speechModel, .privacy, .storage]
}

/// Rounded-square icon used in the sidebar and pane headers, matching System Settings:
/// white glyph on a colored tile in light mode, colored glyph on a dark tile in dark mode.
public struct IconTile: View {
    let item: SidebarItem
    var size: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme

    public init(item: SidebarItem, size: CGFloat = 20) {
        self.item = item
        self.size = size
    }

    public var body: some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        let glyph: Color = dark ? item.glyphTint : .white
        ZStack {
            if dark {
                shape.fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.10)], startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(item.tint.gradient)
            }
            if item == .transcribe {
                BrandWaveformView(size: size * 0.7, color: glyph)
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(glyph)
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(.white.opacity(dark ? 0.10 : 0.12), lineWidth: 0.5))
    }
}

/// Sidebar row with System Settings-style selection: solid accent fill, white label,
/// gray when the window is inactive.
struct SidebarRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        Button(action: action) {
            Label {
                Text(item.rawValue)
                    .lineLimit(1)
            } icon: {
                IconTile(item: item)
            }
            .foregroundStyle(isSelected && activeState != .inactive ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                          ? (activeState == .inactive ? Color.primary.opacity(0.12) : DesignSystem.Colors.accent)
                          : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

public struct MainWindowView: View {
    @Bindable var state: MainWindowState

    let transcriptionViewModel: TranscriptionViewModel
    let conversationViewModel: ConversationViewModel
    let historyViewModel: DictationHistoryViewModel
    let settingsViewModel: SettingsViewModel
    let customWordsViewModel: CustomWordsViewModel
    let textSnippetsViewModel: TextSnippetsViewModel
    let libraryViewModel: TranscriptionLibraryViewModel

    @AppStorage(AccentChoice.storageKey) private var accentRaw = AccentChoice.default.rawValue
    @State private var sidebarSearch = ""

    /// Fixed sidebar width; fits the longest label ("Privacy & Security") with icon and padding.
    private static let sidebarWidth: CGFloat = 220

    public init(state: MainWindowState, transcriptionViewModel: TranscriptionViewModel, conversationViewModel: ConversationViewModel, historyViewModel: DictationHistoryViewModel, settingsViewModel: SettingsViewModel, customWordsViewModel: CustomWordsViewModel, textSnippetsViewModel: TextSnippetsViewModel, libraryViewModel: TranscriptionLibraryViewModel) {
        self.state = state
        self.transcriptionViewModel = transcriptionViewModel
        self.conversationViewModel = conversationViewModel
        self.historyViewModel = historyViewModel
        self.settingsViewModel = settingsViewModel
        self.customWordsViewModel = customWordsViewModel
        self.textSnippetsViewModel = textSnippetsViewModel
        self.libraryViewModel = libraryViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                List {
                    Section {
                        ForEach(SidebarItem.primaryItems.filter { $0.matches(sidebarSearch) }) { item in
                            SidebarRow(item: item, isSelected: state.selectedItem == item) {
                                state.selectedItem = item
                            }
                        }
                    }

                    Section {
                        ForEach(SidebarItem.settingsItems.filter { $0.matches(sidebarSearch) }) { item in
                            SidebarRow(item: item, isSelected: state.selectedItem == item) {
                                state.selectedItem = item
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $sidebarSearch, placement: .sidebar, prompt: "Search")
                .navigationSplitViewColumnWidth(min: Self.sidebarWidth, ideal: Self.sidebarWidth, max: Self.sidebarWidth)
                .frame(width: Self.sidebarWidth)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                Group {
                    switch state.selectedItem {
                    case .transcribe:
                        TranscribeView(viewModel: transcriptionViewModel, showingProgressDetail: $state.showingProgressDetail, onNavigateBack: { state.navigateBack() })
                    case .conversation:
                        ConversationView(viewModel: conversationViewModel)
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
                    case .general, .appearance, .dictation, .speechModel, .privacy, .storage:
                        SettingsView(viewModel: settingsViewModel, pane: state.selectedItem.settingsPane ?? .general)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.background)
                // Accent is read from a static token; rebuild the detail when it changes.
                .id(accentRaw)
                .toolbar {
                    // Present on every page so the toolbar (and traffic lights) never change height
                    ToolbarItem(placement: .navigation) {
                        ControlGroup {
                            Button { state.goBack() } label: { Label("Back", systemImage: "chevron.backward") }
                                .disabled(!state.canGoBack)
                                .keyboardShortcut("[", modifiers: .command)
                            Button { state.goForward() } label: { Label("Forward", systemImage: "chevron.forward") }
                                .disabled(!state.canGoForward)
                                .keyboardShortcut("]", modifiers: .command)
                        }
                        .controlGroupStyle(.navigation)
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)

            if showGlobalProgressBar {
                globalTranscriptionBottomBar
            }
        }
        .tint(DesignSystem.Colors.accent)
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
            conversationViewModel: ConversationViewModel(),
            historyViewModel: DictationHistoryViewModel(),
            settingsViewModel: SettingsViewModel(),
            customWordsViewModel: CustomWordsViewModel(),
            textSnippetsViewModel: TextSnippetsViewModel(),
            libraryViewModel: TranscriptionLibraryViewModel()
        )
    }
}
