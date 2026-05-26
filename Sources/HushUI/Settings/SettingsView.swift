import SwiftUI
import HushCore
import HushViewModels

public struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    @State private var showClearDictationsAlert = false
    @State private var showClearStatsAlert = false
    @AppStorage("showModelNameOnCards") private var showModelName = true

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.md) {
                generalSection
                dictationSection
                storageSection
                permissionsSection
                modelSection
                aboutSection
                diagnosticsSection
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
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

    // MARK: - General

    private var generalSection: some View {
        settingsCard("General") {
            settingsToggle("Launch at login", icon: "clock", isOn: $viewModel.launchAtLogin)

            if let error = viewModel.launchAtLoginError {
                Text(error)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.errorRed)
                    .padding(.leading, DesignSystem.Spacing.md + 28)
                    .padding(.trailing, DesignSystem.Spacing.md)
            }

            settingsDivider()

            settingsToggle("Show in menu bar only", icon: "menubar.rectangle", isOn: $viewModel.menuBarOnlyMode)

            settingsDivider()

            settingsToggle("Show idle pill", icon: "eye", isOn: $viewModel.showIdlePill)

            settingsDivider()

            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("rectangle.topthird.inset.filled")
                Text("Overlay position")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Picker("", selection: $viewModel.overlayPosition) {
                    Text("Bottom").tag(OverlayPosition.bottom)
                    Text("Top (Notch)").tag(OverlayPosition.top)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .frame(width: 200)
            }
            .settingsRow()
        }
    }

    // MARK: - Dictation

    private var dictationSection: some View {
        settingsCard("Dictation") {
            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("keyboard")
                Text("Hotkey")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                HotkeyRecorderView(trigger: $viewModel.hotkeyTrigger)
            }
            .settingsRow()

            settingsDivider()

            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("mic.fill")
                Text("Input device")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Picker("", selection: $viewModel.selectedInputDeviceID) {
                    if let defaultName = viewModel.defaultInputDeviceName {
                        Text("System Default (\(defaultName))").tag(UInt32(0))
                    } else {
                        Text("System Default").tag(UInt32(0))
                    }
                    ForEach(viewModel.availableInputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 250)
            }
            .settingsRow()

            settingsDivider()

            settingsToggle("Auto-stop on silence", icon: "stop.circle", isOn: $viewModel.silenceAutoStop)

            if viewModel.silenceAutoStop {
                settingsDivider()

                settingsLabelValue("Silence delay", icon: "timer", value: String(format: "%.1fs", viewModel.silenceDelay))

                Slider(value: $viewModel.silenceDelay, in: 1...10, step: 0.5)
                .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.xs)
            }

            settingsDivider()

            settingsToggle("Stop only via UI button", icon: "hand.raised", isOn: $viewModel.stopOnlyViaUI)

            settingsDivider()

            settingsToggle("Sound effects", icon: "speaker.wave.2", isOn: $viewModel.dictationSoundEffects)

            settingsDivider()

            if viewModel.screenRecordingGranted {
                settingsToggle("Capture system audio", icon: "waveform.badge.mic", isOn: $viewModel.captureSystemAudio)

                if viewModel.captureSystemAudio {
                    Text("Records system audio (Zoom, Teams, etc.) alongside your microphone.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .padding(.leading, DesignSystem.Spacing.md + 28)
                        .padding(.trailing, DesignSystem.Spacing.md)
                        .padding(.bottom, DesignSystem.Spacing.sm)
                }
            } else {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    settingsIcon("waveform.badge.mic")
                    Text("Capture system audio")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Button("Grant Permission") {
                        viewModel.openScreenRecordingSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .settingsRow()

                Text("Requires Screen & System Audio Recording permission to capture Zoom, Teams, etc.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .padding(.leading, DesignSystem.Spacing.md + 28)
                    .padding(.trailing, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.sm)
            }
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        settingsCard("Storage") {
            settingsToggle("Save dictation history", icon: "archivebox", isOn: $viewModel.saveDictationHistory)

            settingsDivider()

            settingsToggle("Save audio recordings", icon: "waveform", isOn: $viewModel.saveAudioRecordings)

            settingsDivider()

            settingsToggle("Save transcription audio", icon: "mic", isOn: $viewModel.saveTranscriptionAudio)

            settingsDivider()

            settingsToggle("Show model name on cards", icon: "tag", isOn: $showModelName)

            settingsDivider()

            settingsLabelValue("Dictations", icon: "doc.text", value: "\(viewModel.dictationCount)")

            settingsDivider()

            HStack(spacing: DesignSystem.Spacing.sm) {
                Button(role: .destructive) {
                    showClearDictationsAlert = true
                } label: {
                    Text("Clear All Dictations...")
                        .font(DesignSystem.Typography.body)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(role: .destructive) {
                    showClearStatsAlert = true
                } label: {
                    Text("Reset Private Stats...")
                        .font(DesignSystem.Typography.body)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        settingsCard("Permissions") {
            // Microphone row
            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("mic.fill")
                Text("Microphone")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button("Open System Settings") {
                    viewModel.openMicrophoneSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if !viewModel.microphoneGranted {
                    Button("Re-request") {
                        viewModel.reRequestMicrophone()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Circle()
                        .fill(viewModel.microphoneGranted ? DesignSystem.Colors.successGreen : DesignSystem.Colors.errorRed)
                        .frame(width: 8, height: 8)
                    Text(viewModel.microphoneGranted ? "Granted" : "Not Granted")
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(viewModel.microphoneGranted ? DesignSystem.Colors.successGreen : DesignSystem.Colors.errorRed)
                }
            }
            .settingsRow()

            if let message = viewModel.microphoneResetMessage {
                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .padding(.leading, DesignSystem.Spacing.md + 28)
                    .padding(.trailing, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.sm)
            }

            settingsDivider()

            // Accessibility row
            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("accessibility")
                Text("Accessibility")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button("Open System Settings") {
                    viewModel.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if !viewModel.accessibilityGranted {
                    Button("Re-request") {
                        viewModel.reRequestAccessibility()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Circle()
                        .fill(viewModel.accessibilityGranted ? DesignSystem.Colors.successGreen : DesignSystem.Colors.errorRed)
                        .frame(width: 8, height: 8)
                    Text(viewModel.accessibilityGranted ? "Granted" : "Not Granted")
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(viewModel.accessibilityGranted ? DesignSystem.Colors.successGreen : DesignSystem.Colors.errorRed)
                }
            }
            .settingsRow()

            if let message = viewModel.accessibilityResetMessage {
                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .padding(.leading, DesignSystem.Spacing.md + 28)
                    .padding(.trailing, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.sm)
            }

            settingsDivider()

            // Screen Recording row
            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("rectangle.dashed.badge.record")
                Text("Screen & System Audio")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button("Open System Settings") {
                    viewModel.openScreenRecordingSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if !viewModel.screenRecordingGranted {
                    Button("Re-request") {
                        viewModel.reRequestScreenRecording()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Circle()
                        .fill(viewModel.screenRecordingGranted ? DesignSystem.Colors.successGreen : DesignSystem.Colors.errorRed)
                        .frame(width: 8, height: 8)
                    Text(viewModel.screenRecordingGranted ? "Granted" : "Not Granted")
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(viewModel.screenRecordingGranted ? DesignSystem.Colors.successGreen : DesignSystem.Colors.errorRed)
                }
            }
            .settingsRow()

            if !viewModel.screenRecordingGranted {
                Text("Required for capturing system audio (Zoom, Teams, etc.) during dictation.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .padding(.leading, DesignSystem.Spacing.md + 28)
                    .padding(.trailing, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.sm)
            }
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        settingsCard("Speech Model") {
            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("cpu")
                if viewModel.availableModels.isEmpty {
                    Text("Parakeet TDT v3")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                } else {
                    let selectedName = viewModel.availableModels
                        .first(where: { $0.id == viewModel.selectedModelID })?.name ?? "Unknown"
                    ModelSelectorView(
                        currentModel: selectedName,
                        displayName: selectedName,
                        availableModels: viewModel.availableModels.map(\.name),
                        disabled: viewModel.parakeetRepairing,
                        onSelect: { name in
                            if let model = viewModel.availableModels.first(where: { $0.name == name }) {
                                viewModel.selectModel(id: model.id)
                            }
                        }
                    )
                }
                Spacer()
                if !viewModel.parakeetRepairing {
                    Text(viewModel.parakeetStatusDetail)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .font(DesignSystem.Typography.caption)
                }
            }
            .settingsRow()

            if viewModel.parakeetRepairing, let progress = viewModel.modelDownloadProgress {
                Text(viewModel.parakeetStatusDetail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                if viewModel.parakeetStatusDetail.contains("%") {
                    ProgressView(value: progress)
                        .tint(.green)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.bottom, DesignSystem.Spacing.sm)
                } else {
                    ProgressView()
                        .tint(.green)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.bottom, DesignSystem.Spacing.sm)
                }
            }

            if let selectedModel = viewModel.availableModels.first(where: { $0.id == viewModel.selectedModelID }),
               !selectedModel.summary.isEmpty,
               !viewModel.parakeetRepairing {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(selectedModel.summary)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    if (viewModel.parakeetStatus == .notDownloaded || viewModel.parakeetStatus == .failed) {
                        Button("Download / Repair Model") {
                            viewModel.repairParakeetModel()
                        }
                        .font(DesignSystem.Typography.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.sm)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsCard("About") {
            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("info.circle")
                Text("Hush")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Text("Local-first voice transcription")
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .font(DesignSystem.Typography.bodySmall)
            }
            .settingsRow()

            settingsDivider()

            Text("All speech recognition runs on-device using Apple's Neural Engine. Your audio never leaves your Mac.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .padding(.leading, DesignSystem.Spacing.md + 28)
                .padding(.trailing, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        settingsCard("Diagnostics") {
            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("doc.text")
                Text("Log File")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button("Reveal") {
                    viewModel.openLogFile()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!viewModel.logFileExists)
            }
            .settingsRow()

            settingsDivider()

            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("folder")
                Text("Logs Folder")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button("Open") {
                    viewModel.openLogFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .settingsRow()

            settingsDivider()

            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("folder.badge.gearshape")
                Text("App Data Folder")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button("Open") {
                    viewModel.openAppSupportFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .settingsRow()

            settingsDivider()

            HStack(spacing: DesignSystem.Spacing.sm) {
                settingsIcon("arrow.counterclockwise")
                Text("Reset Onboarding")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button("Reset") {
                    viewModel.resetOnboarding()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .settingsRow()

            Text("Diagnostic logs help troubleshoot issues like missing recordings. The log file persists across app restarts.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .padding(.leading, DesignSystem.Spacing.md + 28)
                .padding(.trailing, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.sm)
        }
    }

    // MARK: - Reusable Components

    private func settingsCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DesignSystem.Typography.sectionHeader)
                .foregroundStyle(.primary)
                .padding(.horizontal, DesignSystem.Spacing.xs)
                .padding(.bottom, DesignSystem.Spacing.sm)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                    .fill(DesignSystem.Colors.cardBackground)
                    .cardShadow(DesignSystem.Shadows.cardRest)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                    .strokeBorder(DesignSystem.Colors.border.opacity(0.6), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private func settingsIcon(_ name: String) -> some View {
        if name == "waveform" {
            BrandWaveformView(size: 14, color: DesignSystem.Colors.textSecondary)
                .frame(width: 20, alignment: .center)
        } else {
            Image(systemName: name)
                .font(.system(size: 14))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 20, alignment: .center)
        }
    }

    private func settingsToggle(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            settingsIcon(icon)
            Text(label)
                .font(DesignSystem.Typography.body)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .settingsRow()
    }

    private func settingsLabelValue(_ label: String, icon: String, value: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            settingsIcon(icon)
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .settingsRow()
    }

    private func settingsDivider() -> some View {
        Divider()
            .foregroundStyle(DesignSystem.Colors.divider)
            .padding(.leading, DesignSystem.Spacing.md + 28)
    }
}

// MARK: - Settings Row Modifier

private struct SettingsRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DesignSystem.Typography.body)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func settingsRow() -> some View {
        modifier(SettingsRowModifier())
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: SettingsViewModel(
            defaults: .init(suiteName: "SettingsPreview")!,
            isSpeechModelCached: { false }
        ))
        .frame(width: 480, height: 700)
        .padding()
    }
}
