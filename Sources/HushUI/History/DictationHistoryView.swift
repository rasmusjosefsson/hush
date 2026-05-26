import SwiftUI
import HushCore
import HushViewModels

public struct DictationHistoryView: View {
    @Bindable var viewModel: DictationHistoryViewModel
    @State private var showingProcessingErrorAlert = false
    @AppStorage("dictationStatsExpanded") private var statsExpanded = false

    public init(viewModel: DictationHistoryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.groupedDictations.isEmpty {
                historyHeader
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.sm)
                emptyState
            } else {
                dictationList
            }

            if let error = viewModel.playbackError {
                playbackErrorBanner(error)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let playing = viewModel.playingDictation {
                bottomBarPlayer(playing)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DesignSystem.Animation.contentSwap, value: viewModel.playingDictationId)
        .animation(DesignSystem.Animation.contentSwap, value: viewModel.playbackError != nil)
        .onChange(of: viewModel.processingError) { _, newValue in
            showingProcessingErrorAlert = (newValue != nil)
        }
        .searchable(text: $viewModel.searchText, prompt: "Search dictations")
        .alert(
            "Delete Dictation?",
            isPresented: Binding(
                get: { viewModel.pendingDeleteDictation != nil },
                set: { if !$0 { viewModel.pendingDeleteDictation = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeleteDictation = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            Text("This dictation and its audio file will be permanently deleted.")
        }
        .overlay(alignment: .top) {
            if showingProcessingErrorAlert, let error = viewModel.processingError {
                ProcessingErrorBanner(error: error) {
                    viewModel.processingError = nil
                    showingProcessingErrorAlert = false
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.md)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
    }

    // MARK: - Stats Header

    private var historyHeader: some View {
        let stats = viewModel.stats

        return VStack(alignment: .leading, spacing: statsExpanded ? DesignSystem.Spacing.sm : 0) {
            // Collapsed summary bar (always visible when stats exist)
            Button {
                withAnimation(DesignSystem.Animation.contentSwap) {
                    statsExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    BrandWaveformView(size: 16, color: DesignSystem.Colors.accent)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(DesignSystem.Colors.accent.opacity(0.12))
                        )

                    if stats.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your Voice Stats")
                                .font(DesignSystem.Typography.sectionTitle)
                            Text("Start dictating to see your stats")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        collapsedStatsSummary(stats)
                    }

                    Spacer()

                    if !stats.isEmpty {
                        Image(systemName: statsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(stats.isEmpty)

            // Expanded detail panel
            if statsExpanded && !stats.isEmpty {
                expandedStatsPanel(stats)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, stats.isEmpty || !statsExpanded ? DesignSystem.Spacing.sm : DesignSystem.Spacing.md)
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

    private func collapsedStatsSummary(_ stats: DictationStats) -> some View {
        let parts: [Text] = {
            var result: [Text] = []
            result.append(
                Text("\(stats.totalWords.compactFormatted) words")
                    .fontWeight(.semibold)
            )
            result.append(Text(" · \(stats.totalDurationMs.friendlyDuration)"))
            result.append(Text(" · \(stats.averageWPM.formattedWPM)"))

            return result
        }()
        return parts.reduce(Text("")) { $0 + $1 }
            .font(DesignSystem.Typography.caption)
            .lineLimit(1)
    }

    // MARK: - Stats Panel

    private func expandedStatsPanel(_ stats: DictationStats) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // 2x2 grid of stat cards
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.sm),
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.sm)
                ],
                spacing: DesignSystem.Spacing.sm
            ) {
                statCard(
                    label: "TOTAL WORDS",
                    value: stats.totalWords.compactFormatted,
                    subtitle: wordsComparison(stats),
                    icon: "text.word.spacing"
                )
                statCard(
                    label: "TIME SPEAKING",
                    value: stats.totalDurationMs.friendlyDuration,
                    subtitle: "\(stats.totalCount) dictation\(stats.totalCount == 1 ? "" : "s")",
                    icon: "clock"
                )
                statCard(
                    label: "VOICE SPEED",
                    value: stats.averageWPM.formattedWPM,
                    subtitle: wpmComparison(stats.averageWPM),
                    icon: "gauge.with.dots.needle.33percent"
                )
                statCard(
                    label: "TIME SAVED",
                    value: stats.timeSavedMs.friendlyDuration,
                    subtitle: "vs typing at 40 WPM",
                    icon: "bolt"
                )
            }

            // Fun comparison banner
            if let banner = funComparisonBanner(stats) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(banner)
                        .font(DesignSystem.Typography.caption.weight(.medium))
                        .foregroundStyle(DesignSystem.Colors.accent)
                    Spacer()
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignSystem.Colors.accent.opacity(0.08))
                )
            }
        }
    }

    private func statCard(label: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(subtitle)
                .font(DesignSystem.Typography.micro)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated)
        )
    }

    // MARK: - Fun Comparisons

    private func wordsComparison(_ stats: DictationStats) -> String {
        if stats.totalWords >= 80_000 {
            let books = stats.booksEquivalent
            return String(format: "%.1f novel\(books >= 1.5 ? "s" : "") worth", books)
        } else if stats.totalWords >= 200 {
            let emails = Int(stats.emailsEquivalent)
            return "\(emails) email\(emails == 1 ? "" : "s") worth"
        }
        return "\(stats.totalWords) word\(stats.totalWords == 1 ? "" : "s") total"
    }

    private func wpmComparison(_ wpm: Double) -> String {
        switch wpm {
        case ..<80: return "Thoughtful pace"
        case 80..<120: return "Conversational pace"
        case 120..<160: return "Brisk speaker"
        case 160..<200: return "Fast talker"
        default: return "Lightning speed"
        }
    }

    private func funComparisonBanner(_ stats: DictationStats) -> String? {
        if stats.booksEquivalent >= 1.0 {
            return String(format: "You've dictated %.1f novel\(stats.booksEquivalent >= 1.5 ? "s" : "")!", stats.booksEquivalent)
        } else if stats.emailsEquivalent >= 50 {
            return "That's \(Int(stats.emailsEquivalent)) emails worth of voice!"
        } else if stats.totalWords >= 1000 {
            return "Over \(stats.totalWords.compactFormatted) words and counting!"
        }
        return nil
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            Image(systemName: viewModel.searchText.isEmpty ? "mic.circle" : "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DesignSystem.Colors.accent)
                .opacity(0.5)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(viewModel.searchText.isEmpty
                     ? "Your voice, captured."
                     : "No matching records")
                    .font(DesignSystem.Typography.pageTitle)
                    .foregroundStyle(.primary)

                Text(viewModel.searchText.isEmpty
                     ? "Double-tap \(HotkeyTrigger.current.displayName) to start dictating from any app."
                     : "Try different words or clear your search.")
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Card-Based List

    private var dictationList: some View {
        ScrollView {
            historyHeader
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.sm)

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.groupedDictations, id: \.0) { dateHeader, dictations in
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                        Text(dateHeader.uppercased())
                            .font(DesignSystem.Typography.sectionHeader)
                            .foregroundStyle(DesignSystem.Colors.accent.opacity(0.8))
                        Text("\(dictations.count)")
                            .font(DesignSystem.Typography.duration)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DesignSystem.Colors.surfaceElevated))
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.sm)

                    ForEach(dictations) { dictation in
                        DictationCardRow(
                            dictation: dictation,
                            searchText: viewModel.searchText,
                            isPlayingThis: viewModel.playingDictationId == dictation.id && viewModel.isPlaying,
                            isCopied: viewModel.copiedDictationId == dictation.id,
                            onTogglePlayback: { viewModel.togglePlayback(for: dictation) },
                            onCopy: {
                                viewModel.copyToClipboard(dictation)
                            },
                            onDelete: {
                                viewModel.pendingDeleteDictation = dictation
                            },
                            onDownloadAudio: { viewModel.downloadAudio(for: dictation) },
                            onExportTxt: { viewModel.exportTranscriptAsTxt(for: dictation) },
                            onExportMarkdown: { viewModel.exportTranscriptAsMarkdown(for: dictation) },
                            onReprocessWithSpeakers: { viewModel.reprocessWithSpeakers(dictation) },
                            onRevealInFinder: { viewModel.revealInFinder() },
                            isProcessing: viewModel.processingDictationIDs.contains(dictation.id),
                            reprocessingProgress: viewModel.processingProgress[dictation.id]
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.bottom, DesignSystem.Spacing.sm)
                    }
                }
            }
            .padding(.bottom, DesignSystem.Spacing.md)
        }
    }

    // MARK: - Status Bars

    private func playbackErrorBanner(_ error: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.warningAmber)
            Text(error)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.surfaceElevated)
        .overlay(alignment: .top) { Divider() }
    }

    private func bottomBarPlayer(_ dictation: Dictation) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button {
                viewModel.togglePlayback(for: dictation)
            } label: {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: 32, height: 32)

                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.onAccent)
                        .offset(x: viewModel.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)

            Text(dictation.cleanTranscript ?? dictation.rawTranscript)
                .lineLimit(1)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignSystem.Colors.playbackTrack)
                    Capsule()
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: max(0, geo.size.width * viewModel.playbackProgress))
                        .animation(.linear(duration: 0.12), value: viewModel.playbackProgress)
                }
            }
            .frame(width: 140, height: DesignSystem.Layout.playbackBarHeight)

            Text(viewModel.playbackTimeString)
                .font(DesignSystem.Typography.timestamp)
                .foregroundStyle(.secondary)
                .fixedSize()

            Button {
                viewModel.stopPlayback()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .frame(height: 56)
        .background(
            Rectangle()
                .fill(DesignSystem.Colors.surfaceElevated)
                .overlay(alignment: .top) {
                    Divider()
                }
        )
    }
}

private struct ProcessingErrorBanner: View {
    let error: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Colors.warningAmber)
            Text(error)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Dismiss", action: onDismiss)
                .font(DesignSystem.Typography.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DesignSystem.Colors.warningAmber.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Card Row View

public struct DictationCardRow: View {
    let dictation: Dictation
    var searchText: String = ""
    var isPlayingThis: Bool = false
    var isCopied: Bool = false
    var onTogglePlayback: (() -> Void)?
    var onCopy: () -> Void
    var onDelete: () -> Void
    var onDownloadAudio: (() -> Void)?
    var onExportTxt: (() -> Void)?
    var onExportMarkdown: (() -> Void)?
    var onReprocessWithSpeakers: (() -> Void)?
    var onRevealInFinder: (() -> Void)?
    var isProcessing: Bool = false
    var reprocessingProgress: ReprocessingProgress?

    @State private var isHovered = false
    @State private var showSpeakerView = false
    @AppStorage("showModelNameOnCards") private var showModelName = true

    public init(
        dictation: Dictation,
        searchText: String = "",
        isPlayingThis: Bool = false,
        isCopied: Bool = false,
        onTogglePlayback: (() -> Void)? = nil,
        onCopy: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onDownloadAudio: (() -> Void)? = nil,
        onExportTxt: (() -> Void)? = nil,
        onExportMarkdown: (() -> Void)? = nil,
        onReprocessWithSpeakers: (() -> Void)? = nil,
        onRevealInFinder: (() -> Void)? = nil,
        isProcessing: Bool = false,
        reprocessingProgress: ReprocessingProgress? = nil
    ) {
        self.dictation = dictation
        self.searchText = searchText
        self.isPlayingThis = isPlayingThis
        self.isCopied = isCopied
        self.onTogglePlayback = onTogglePlayback
        self.onCopy = onCopy
        self.onDelete = onDelete
        self.onDownloadAudio = onDownloadAudio
        self.onExportTxt = onExportTxt
        self.onExportMarkdown = onExportMarkdown
        self.onReprocessWithSpeakers = onReprocessWithSpeakers
        self.onRevealInFinder = onRevealInFinder
        self.isProcessing = isProcessing
        self.reprocessingProgress = reprocessingProgress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text(formatTime(dictation.createdAt))
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.secondary)

                        Text("\u{2009}\u{00B7}\u{2009}")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.quaternary)

                        Text(dictation.durationMs.formattedDuration)
                            .font(DesignSystem.Typography.duration)
                            .foregroundStyle(.tertiary)

                        if dictation.audioPath != nil {
                            Text("\u{2009}\u{00B7}\u{2009}")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(.quaternary)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                        }
                    }

                }

                Spacer()

                HStack(spacing: 4) {
                    if showModelName, let modelName = dictation.sttModelName {
                        Text(modelName)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.trailing, 4)
                    }

                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else if dictation.hasSpeakerData {
                        CardActionButton(
                            icon: showSpeakerView ? "person.2.fill" : "person.2",
                            color: showSpeakerView ? DesignSystem.Colors.accent : .secondary,
                            action: { showSpeakerView.toggle() }
                        )
                    }

                    if dictation.audioPath != nil {
                        CardActionButton(
                            icon: isPlayingThis ? "pause.fill" : "play.fill",
                            color: DesignSystem.Colors.accent,
                            action: { onTogglePlayback?() }
                        )
                    }

                    if isCopied {
                        Text("Copied")
                            .font(DesignSystem.Typography.micro)
                            .foregroundStyle(DesignSystem.Colors.successGreen)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }

                    CardActionButton(
                        icon: isCopied ? "checkmark" : "doc.on.clipboard",
                        color: isCopied ? DesignSystem.Colors.successGreen : .secondary,
                        action: { onCopy() }
                    )
                    .animation(DesignSystem.Animation.hoverTransition, value: isCopied)

                        CardMenuButton(
                        hasAudio: dictation.audioPath != nil,
                        isProcessing: isProcessing,
                        onDownloadAudio: { onDownloadAudio?() },
                        onExportTxt: { onExportTxt?() },
                        onExportMarkdown: { onExportMarkdown?() },
                        onReprocessWithSpeakers: { onReprocessWithSpeakers?() },
                        onRevealInFinder: { onRevealInFinder?() },
                        onDelete: { onDelete() }
                    )
                }
            }

            if showSpeakerView, dictation.hasSpeakerData {
                speakerFormattedView
            } else {
                Text(highlightedTranscript)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isProcessing {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: phaseIcon)
                            .font(.system(size: 10))
                        Text(phaseLabel)
                            .font(DesignSystem.Typography.micro)
                        Spacer()
                        Text(progressPercentText)
                            .font(DesignSystem.Typography.micro.monospacedDigit())
                    }
                    .foregroundStyle(DesignSystem.Colors.accent)

                    DeterminateProgressBar(fraction: reprocessingProgress?.fractionCompleted ?? 0)
                        .frame(height: 3)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(DesignSystem.Animation.contentSwap, value: isProcessing)
        .padding(DesignSystem.Spacing.md)
        .scaleEffect(isPlayingThis ? 1.005 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .fill(isPlayingThis
                      ? DesignSystem.Colors.accent.opacity(0.06)
                      : DesignSystem.Colors.cardBackground)
                .cardShadow(isHovered ? DesignSystem.Shadows.cardHover : DesignSystem.Shadows.cardRest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(
                    isPlayingThis ? DesignSystem.Colors.accent.opacity(0.24) : DesignSystem.Colors.border.opacity(0.5),
                    lineWidth: 0.5
                )
                .allowsHitTesting(false)
        )
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.hoverTransition) {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isPlayingThis)
    }

    // MARK: - Highlighted Transcript

    // MARK: Progress Helpers

    private var phaseLabel: String {
        switch reprocessingProgress?.phase {
        case .transcribing: return "Transcribing…"
        case .analyzingSpeakers: return "Analyzing speakers…"
        case .finalizing: return "Finalizing…"
        case nil: return "Processing…"
        }
    }

    private var phaseIcon: String {
        switch reprocessingProgress?.phase {
        case .transcribing: return "text.badge.checkmark"
        case .analyzingSpeakers: return "waveform.badge.magnifyingglass"
        case .finalizing: return "checkmark.circle"
        case nil: return "ellipsis.circle"
        }
    }

    private var progressPercentText: String {
        let pct = Int((reprocessingProgress?.fractionCompleted ?? 0) * 100)
        return "\(pct)%"
    }

    private var highlightedTranscript: AttributedString {
        let text = dictation.cleanTranscript ?? dictation.rawTranscript
        var attributed = AttributedString(text)

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return attributed }

        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex {
            guard let range = attributed[searchStart...].range(
                of: query,
                options: .caseInsensitive
            ) else { break }

            attributed[range].backgroundColor = DesignSystem.Colors.accent.opacity(0.2)
            searchStart = range.upperBound
        }

        return attributed
    }

    // MARK: - Speaker View

    @ViewBuilder
    private var speakerFormattedView: some View {
        let turns = buildSpeakerTurns()
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ForEach(Array(turns.prefix(4).enumerated()), id: \.offset) { _, turn in
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Text(turn.label)
                        .font(DesignSystem.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .frame(width: 72, alignment: .leading)
                        .lineLimit(1)
                    Text(turn.text)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }
            if turns.count > 4 {
                Text("+\(turns.count - 4) more")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildSpeakerTurns() -> [(label: String, text: String)] {
        guard let words = dictation.wordTimestamps, !words.isEmpty,
              let speakers = dictation.speakers else {
            return []
        }

        let speakerMap = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.label) })
        var turns: [(label: String, text: String)] = []
        var currentSpeaker: String?
        var currentWords: [String] = []

        for word in words {
            let spk = word.speakerId ?? ""
            if spk != currentSpeaker {
                if !currentWords.isEmpty, let prevSpk = currentSpeaker {
                    let label = speakerMap[prevSpk] ?? prevSpk
                    turns.append((label: label, text: currentWords.joined(separator: " ")))
                }
                currentSpeaker = spk
                currentWords = [word.word]
            } else {
                currentWords.append(word.word)
            }
        }
        if !currentWords.isEmpty, let spk = currentSpeaker {
            let label = speakerMap[spk] ?? spk
            turns.append((label: label, text: currentWords.joined(separator: " ")))
        }

        return turns
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Hover-Aware Action Button

private struct CardActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : color)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Hover-Aware Menu Button

private struct CardMenuButton: View {
    let hasAudio: Bool
    let isProcessing: Bool
    let onDownloadAudio: () -> Void
    let onExportTxt: () -> Void
    let onExportMarkdown: () -> Void
    let onReprocessWithSpeakers: () -> Void
    let onRevealInFinder: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Menu {
            if hasAudio {
                Button {
                    onDownloadAudio()
                } label: {
                    Label("Export Audio", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                onExportTxt()
            } label: {
                Label("Export .txt", systemImage: "doc.plaintext")
            }

            Button {
                onExportMarkdown()
            } label: {
                Label("Export .md", systemImage: "doc.text")
            }

            Button {
                onReprocessWithSpeakers()
            } label: {
                Label("Analyze Speakers + Re-transcribe", systemImage: "waveform.badge.magnifyingglass")
            }
            .disabled(!hasAudio || isProcessing)

            Button {
                onRevealInFinder()
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Determinate Progress Bar

private struct DeterminateProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DesignSystem.Colors.accent.opacity(0.15))
                Capsule()
                    .fill(DesignSystem.Colors.accent)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.25), value: fraction)
    }
}

// MARK: - Preview

struct DictationHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Empty state
            DictationHistoryView(viewModel: DictationHistoryViewModel())
                .previewDisplayName("Empty State")

            // Card row with sample data
            DictationCardRow(
                dictation: Dictation(
                    durationMs: 12_450,
                    rawTranscript: "Hello world, this is a sample dictation that was captured by Hush.",
                    cleanTranscript: "Hello world, this is a sample dictation that was captured by Hush.",
                    wordCount: 13
                ),
                onCopy: {},
                onDelete: {}
            )
            .padding()
            .background(DesignSystem.Colors.background)
            .previewDisplayName("Card Row")
        }
        .frame(width: 500, height: 400)
    }
}
