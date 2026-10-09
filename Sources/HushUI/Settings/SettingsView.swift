import SwiftUI
import HushCore
import HushViewModels

public enum SettingsPane: String, CaseIterable, Sendable {
    case general, appearance, dictation, speechModel, privacy, storage

    var item: SidebarItem {
        switch self {
        case .general: .general
        case .appearance: .appearance
        case .dictation: .dictation
        case .speechModel: .speechModel
        case .privacy: .privacy
        case .storage: .storage
        }
    }

    var summary: String {
        switch self {
        case .general: "Startup behavior, diagnostics and information about Hush."
        case .appearance: "Choose an accent color and where the dictation overlay appears."
        case .dictation: "Click or hold your shortcut to dictate into any app. Text is pasted at your cursor."
        case .speechModel: "Speech recognition runs on your Mac's Neural Engine. Audio never leaves your device."
        case .privacy: "Hush needs these permissions to hear you and paste text. Nothing is sent off your Mac."
        case .storage: "Choose what Hush keeps on this Mac."
        }
    }
}

public struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    var pane: SettingsPane

    @State private var showClearDictationsAlert = false
    @State private var showClearStatsAlert = false
    @AppStorage("showModelNameOnCards") private var showModelName = true
    @AppStorage(AccentChoice.storageKey) private var accentRaw = AccentChoice.default.rawValue

    public init(viewModel: SettingsViewModel, pane: SettingsPane = .general) {
        self.viewModel = viewModel
        self.pane = pane
    }

    public var body: some View {
        Form {
            paneHeader
            switch pane {
            case .general:
                generalSection
                diagnosticsSection
                aboutSection
            case .appearance: appearanceSection
            case .dictation: dictationSection
            case .speechModel: modelSection
            case .privacy: permissionsSection
            case .storage: storageSection
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .navigationTitle(pane.item.rawValue)
        .alert("Clear All Dictations?", isPresented: $showClearDictationsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                viewModel.clearAllDictations()
            }
        } message: {
            Text("This will permanently delete all dictation history and saved audio.")
        }
        .alert("Reset Private Statistics?", isPresented: $showClearStatsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                viewModel.resetPrivateStatistics()
            }
        } message: {
            Text("This will delete hidden dictation records used for voice statistics.")
        }
        .onAppear {
            viewModel.refreshPermissions()
            viewModel.refreshStats()
            viewModel.refreshModelStatus()
            viewModel.refreshInputDevices()
        }
    }

    // MARK: - Header

    /// Icon + title + description card, as at the top of each System Settings pane.
    private var paneHeader: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                IconTile(item: pane.item, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pane.item.rawValue)
                        .font(.headline)
                    Text(pane.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section {
            Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
            if let error = viewModel.launchAtLoginError {
                footnote(error, color: DesignSystem.Colors.errorRed)
            }
            Toggle(isOn: $viewModel.menuBarOnlyMode) {
                Text("Menu bar only")
                Text("Hide Hush from the Dock and app switcher.")
            }
        }
    }

    // MARK: - Appearance

    private var accentBinding: Binding<AccentChoice> {
        Binding(
            get: { AccentChoice(rawValue: accentRaw) ?? .default },
            set: { accentRaw = $0.rawValue }
        )
    }

    private var appearanceSection: some View {
        Section {
            LabeledContent("Accent color") {
                AccentSwatchPicker(selection: accentBinding)
            }
            LabeledContent {
                Picker("Dictation overlay", selection: $viewModel.overlayPosition) {
                    Text("Notch").tag(OverlayPosition.top)
                    Text("Bottom").tag(OverlayPosition.bottom)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            } label: {
                Text("Dictation overlay")
                Text("Where the recording indicator appears.")
            }
            Toggle(isOn: $viewModel.showIdlePill) {
                Text("Show idle indicator")
                Text(viewModel.overlayPosition == .top
                     ? "Hover the notch to see your shortcut."
                     : "A small handle at the bottom of the screen.")
            }
            Toggle("Show model name on cards", isOn: $showModelName)
        }
    }

    // MARK: - Dictation

    private var dictationSection: some View {
        Section {
            LabeledContent("Shortcut") {
                HotkeyRecorderView(trigger: $viewModel.hotkeyTrigger)
            }

            Picker("Microphone", selection: $viewModel.selectedInputDeviceID) {
                if let defaultName = viewModel.defaultInputDeviceName {
                    Text("System Default (\(defaultName))").tag(UInt32(0))
                } else {
                    Text("System Default").tag(UInt32(0))
                }
                if !viewModel.availableInputDevices.isEmpty {
                    Divider()
                }
                ForEach(viewModel.availableInputDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }

            Toggle("Stop automatically on silence", isOn: $viewModel.silenceAutoStop)
            if viewModel.silenceAutoStop {
                LabeledContent("After") {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Slider(value: $viewModel.silenceDelay, in: 1...10, step: 0.5)
                            .frame(width: 160)
                        Text(String(format: "%.1f s", viewModel.silenceDelay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Toggle(isOn: $viewModel.stopOnlyViaUI) {
                Text("Stop only from the overlay")
                Text("The shortcut starts dictation; finish with the stop button.")
            }
            Toggle("Sound effects", isOn: $viewModel.dictationSoundEffects)

            if viewModel.screenRecordingGranted {
                Toggle(isOn: $viewModel.captureSystemAudio) {
                    Text("Capture system audio")
                    Text("Record Zoom, Teams and other apps alongside your microphone.")
                }
            } else {
                LabeledContent {
                    Button("Grant Access…") {
                        viewModel.openScreenRecordingSettings()
                    }
                } label: {
                    Text("Capture system audio")
                    Text("Requires Screen & System Audio Recording permission.")
                }
            }
        }
    }

    // MARK: - Speech Model

    private var modelBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedModelID },
            set: { viewModel.selectModel(id: $0) }
        )
    }

    private var selectedModel: ModelInfo? {
        viewModel.availableModels.first(where: { $0.id == viewModel.selectedModelID })
    }

    private var modelSection: some View {
        Section {
            if viewModel.availableModels.isEmpty {
                LabeledContent("Model", value: "Parakeet TDT v3")
            } else {
                Picker(selection: modelBinding) {
                    ForEach(viewModel.availableModels) { model in
                        Text(model.name).tag(model.id)
                    }
                } label: {
                    Text("Model")
                    if let summary = selectedModel?.summary, !summary.isEmpty {
                        Text(summary)
                    }
                }
                .disabled(viewModel.parakeetRepairing)
            }

            LabeledContent("Status") {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if viewModel.parakeetRepairing {
                        if let progress = viewModel.modelDownloadProgress,
                           viewModel.parakeetStatusDetail.contains("%") {
                            ProgressView(value: progress)
                                .frame(width: 120)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    } else {
                        modelStatusDot
                    }
                    Text(viewModel.parakeetStatusDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if !viewModel.parakeetRepairing,
               viewModel.parakeetStatus == .notDownloaded || viewModel.parakeetStatus == .failed {
                HStack {
                    Spacer()
                    Button("Download / Repair Model") {
                        viewModel.repairParakeetModel()
                    }
                }
            }
        }
    }

    private var modelStatusDot: some View {
        let color: Color = switch viewModel.parakeetStatus {
        case .ready: DesignSystem.Colors.successGreen
        case .failed, .notDownloaded: DesignSystem.Colors.errorRed
        case .notLoaded, .checking, .repairing: DesignSystem.Colors.warningAmber
        case .unknown: DesignSystem.Colors.textTertiary
        }
        return Circle().fill(color).frame(width: 7, height: 7)
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        Section {
            permissionRow(
                "Microphone",
                detail: "Hear your voice while dictating.",
                granted: viewModel.microphoneGranted,
                message: viewModel.microphoneResetMessage,
                open: viewModel.openMicrophoneSettings,
                request: viewModel.reRequestMicrophone
            )
            permissionRow(
                "Accessibility",
                detail: "Paste text into the app you're using.",
                granted: viewModel.accessibilityGranted,
                message: viewModel.accessibilityResetMessage,
                open: viewModel.openAccessibilitySettings,
                request: viewModel.reRequestAccessibility
            )
            permissionRow(
                "Screen & System Audio",
                detail: "Capture audio from Zoom, Teams and other apps.",
                granted: viewModel.screenRecordingGranted,
                message: nil,
                open: viewModel.openScreenRecordingSettings,
                request: viewModel.reRequestScreenRecording
            )
        }
    }

    @ViewBuilder
    private func permissionRow(
        _ title: String,
        detail: String,
        granted: Bool,
        message: String?,
        open: @escaping () -> Void,
        request: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DesignSystem.Colors.successGreen)
                    .contextMenu {
                        Button("Open System Settings…", action: open)
                    }
            } else {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button("Request", action: request)
                    Button("Open Settings…", action: open)
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accent)
                }
            }
        } label: {
            Text(title)
            Text(detail)
        }
        if let message {
            footnote(message)
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section {
            Toggle("Save dictation history", isOn: $viewModel.saveDictationHistory)
            Toggle("Keep dictation audio", isOn: $viewModel.saveAudioRecordings)
            Toggle("Keep transcription audio", isOn: $viewModel.saveTranscriptionAudio)
            LabeledContent("Saved dictations") {
                Text("\(viewModel.dictationCount)")
                    .monospacedDigit()
            }
            HStack {
                Spacer()
                Button("Reset Private Stats…", role: .destructive) {
                    showClearStatsAlert = true
                }
                Button("Clear All Dictations…", role: .destructive) {
                    showClearDictationsAlert = true
                }
            }
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        Section {
            LabeledContent("Log file") {
                Button("Reveal in Finder") {
                    viewModel.openLogFile()
                }
                .disabled(!viewModel.logFileExists)
            }
            LabeledContent("Logs folder") {
                Button("Open") {
                    viewModel.openLogFolder()
                }
            }
            LabeledContent("App data folder") {
                Button("Open") {
                    viewModel.openAppSupportFolder()
                }
            }
            LabeledContent("Onboarding") {
                Button("Show Again") {
                    viewModel.resetOnboarding()
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            footer("Logs help troubleshoot issues like missing recordings and persist across restarts.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack(spacing: DesignSystem.Spacing.md) {
                BrandWaveformView(size: 28, color: DesignSystem.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DesignSystem.Colors.accent.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hush")
                        .font(.headline)
                    Text("Local-first voice transcription")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Version \(version)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func footnote(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: SettingsViewModel(
            defaults: .init(suiteName: "SettingsPreview")!,
            isSpeechModelCached: { false }
        ))
        .frame(width: 640, height: 900)
    }
}
