import AppKit
import HushCore
import HushUI
import HushViewModels
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // MARK: - Menu Bar

    private var statusItem: NSStatusItem?

    // MARK: - Windows

    private var mainWindow: NSWindow?

    // MARK: - Services

    private var appEnvironment: AppEnvironment?
    private var hotkeyManager: HotkeyManager?
    private var dictationFlowCoordinator: DictationFlowCoordinator?

    // MARK: - ViewModels

    private let transcriptionViewModel = TranscriptionViewModel()
    private let historyViewModel = DictationHistoryViewModel()
    private let settingsViewModel = SettingsViewModel()
    private let customWordsViewModel = CustomWordsViewModel()
    private let textSnippetsViewModel = TextSnippetsViewModel()
    private let libraryViewModel = TranscriptionLibraryViewModel()
    private let mainWindowState = MainWindowState()
    private let onboardingWindowController = OnboardingWindowController()
    private var onboardingObserver: Any?
    private var settingsObserver: Any?
    private var hotkeyTriggerObserver: Any?
    private var menuBarOnlyModeObserver: Any?
    private var showIdlePillObserver: Any?
    private var overlayPositionObserver: Any?
    private var stopOnlyViaUIObserver: Any?
    private var hotkeyMenuItem: NSMenuItem?
    private var pasteLastMenuItem: NSMenuItem?
    private var recentDictationsMenuItem: NSMenuItem?
    private var reopenOnboardingOnNextActivate = false
    private var hasPresentedHotkeyUnavailableAlert = false

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileLogger.shared.log("App launched", level: .info, category: .app)
        setupMainMenu()
        setupMenuBar()
        setupEnvironment()
        setupHotkey()
        observeOpenOnboarding()
        observeOpenSettings()
        observeHotkeyTriggerChange()
        observeMenuBarOnlyModeChange()
        observeShowIdlePillChange()
        observeOverlayPositionChange()
        observeStopOnlyViaUIChange()
        applyActivationPolicyFromSettings()
        dictationFlowCoordinator?.showIdlePill()
    }

    func applicationWillTerminate(_ notification: Notification) {
        FileLogger.shared.log("App will terminate", level: .info, category: .app)
        dictationFlowCoordinator?.hideIdlePill()
        hotkeyManager?.stop()
        if let onboardingObserver { NotificationCenter.default.removeObserver(onboardingObserver) }
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let hotkeyTriggerObserver { NotificationCenter.default.removeObserver(hotkeyTriggerObserver) }
        if let menuBarOnlyModeObserver { NotificationCenter.default.removeObserver(menuBarOnlyModeObserver) }
        if let showIdlePillObserver { NotificationCenter.default.removeObserver(showIdlePillObserver) }
        if let overlayPositionObserver { NotificationCenter.default.removeObserver(overlayPositionObserver) }
        let sttClient = appEnvironment?.sttDispatcher
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            await sttClient?.shutdown()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        if hasVisiblePrimaryWindow {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openMainWindow()
        }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Hush", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openMainWindowToSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Hush", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Hush", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let statusItem = statusItem,
              let button = statusItem.button else { return }

        button.image = BreathWaveIcon.menuBarIcon(pointSize: 18)

        let dropView = MenuBarDropView(frame: button.bounds)
        dropView.onDrop = { [weak self] url in
            Task { @MainActor in
                self?.openMainWindow()
                self?.transcriptionViewModel.transcribeFile(url: url)
                SoundManager.shared.play(.fileDropped)
            }
        }
        button.addSubview(dropView)

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        menu.addItem(NSMenuItem(title: "Open Hush", action: #selector(openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())

        let pasteItem = NSMenuItem(title: "Paste Last Dictation", action: #selector(pasteLastDictation), keyEquivalent: "")
        pasteItem.isEnabled = false
        menu.addItem(pasteItem)
        pasteLastMenuItem = pasteItem

        let recentItem = NSMenuItem(title: "Recent Dictations", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        recentItem.isHidden = true
        menu.addItem(recentItem)
        recentDictationsMenuItem = recentItem

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Transcribe File...", action: #selector(transcribeFileFromMenu), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        let hotkeyItem = NSMenuItem(title: hotkeyMenuTitle, action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        hotkeyMenuItem = hotkeyItem

        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openMainWindowToSettings), keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Hush", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Environment Setup

    private func setupEnvironment() {
        do {
            let env = try AppEnvironment()
            appEnvironment = env

            transcriptionViewModel.configure(
                transcriptionService: env.transcriptionService,
                transcriptionRepo: env.transcriptionRepo,
                exportService: env.exportService
            )
            historyViewModel.configure(
                dictationRepo: env.dictationRepo,
                dictationService: env.dictationService,
                exportService: env.exportService
            )
            libraryViewModel.configure(transcriptionRepo: env.transcriptionRepo)
            settingsViewModel.configure(
                permissionService: env.permissionService,
                dictationRepo: env.dictationRepo,
                transcriptionRepo: env.transcriptionRepo,
                launchAtLoginService: env.launchAtLoginService,
                customWordRepo: env.customWordRepo,
                snippetRepo: env.snippetRepo,
                sttClient: env.sttDispatcher,
                modelRegistry: env.modelRegistry
            )
            customWordsViewModel.configure(repo: env.customWordRepo)
            textSnippetsViewModel.configure(repo: env.snippetRepo)
            settingsViewModel.onDictationsCleared = { [weak self] in
                self?.historyViewModel.loadDictations()
            }
            transcriptionViewModel.onTranscribingChanged = { [weak self] isTranscribing in
                guard let self, !(self.dictationFlowCoordinator?.isDictationActive ?? false) else { return }
                self.updateMenuBarIcon(state: isTranscribing ? .processing : .idle)
            }

            let coordinator = DictationFlowCoordinator(
                dictationService: env.dictationService,
                clipboardService: env.clipboardService,
                dictationRepo: env.dictationRepo,
                settingsViewModel: settingsViewModel,
                onMenuBarIconUpdate: { [weak self] state in self?.updateMenuBarIcon(state: state) },
                onHistoryReload: { [weak self] in self?.historyViewModel.loadDictations() }
            )
            dictationFlowCoordinator = coordinator

            maybeShowOnboarding()
        } catch {
            FileLogger.shared.log("App failed to start: \(error.localizedDescription)", level: .error, category: .app)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Hush Failed to Start"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Quit")
            _ = alert.runModal()
            NSApp.terminate(nil)
        }
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        let manager = HotkeyManager(trigger: HotkeyTrigger.current)

        manager.onStartRecording = { [weak self] mode in
            self?.dictationFlowCoordinator?.startDictation(mode: mode, trigger: .hotkey)
        }
        manager.onStopRecording = { [weak self] in
            self?.dictationFlowCoordinator?.stopDictation()
        }
        manager.onCancelRecording = { [weak self] in
            self?.dictationFlowCoordinator?.cancelDictation(reason: .escape)
        }
        manager.onReadyForSecondTap = { [weak self] in
            self?.dictationFlowCoordinator?.showReadyPill()
        }
        manager.onEscapeWhileIdle = { [weak self] in
            self?.dictationFlowCoordinator?.dismissOverlayIfError()
        }

        if manager.start() {
            hotkeyManager = manager
            hotkeyManager?.persistentStopDisabled = settingsViewModel.stopOnlyViaUI
            dictationFlowCoordinator?.hotkeyManager = manager
            hasPresentedHotkeyUnavailableAlert = false
        } else {
            hotkeyManager = nil
            dictationFlowCoordinator?.hotkeyManager = nil
            presentHotkeyUnavailableAlertIfNeeded()
        }
    }

    private func refreshHotkeyAfterPermissions() {
        hotkeyManager?.stop()
        hotkeyManager = nil
        setupHotkey()
    }

    private func observeOpenOnboarding() {
        onboardingObserver = NotificationCenter.default.addObserver(
            forName: .hushOpenOnboarding, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showOnboarding() }
        }
    }

    private func observeOpenSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .hushOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.openMainWindowToSettings() }
        }
    }

    private func observeHotkeyTriggerChange() {
        hotkeyTriggerObserver = NotificationCenter.default.addObserver(
            forName: .hushHotkeyTriggerDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hotkeyManager?.stop()
                self?.hotkeyManager = nil
                self?.setupHotkey()
                self?.hotkeyMenuItem?.title = self?.hotkeyMenuTitle ?? ""
            }
        }
    }

    private func observeMenuBarOnlyModeChange() {
        menuBarOnlyModeObserver = NotificationCenter.default.addObserver(
            forName: .hushMenuBarOnlyModeDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyActivationPolicyFromSettings() }
        }
    }

    private func observeShowIdlePillChange() {
        showIdlePillObserver = NotificationCenter.default.addObserver(
            forName: .hushShowIdlePillDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.settingsViewModel.showIdlePill {
                    self.dictationFlowCoordinator?.showIdlePill()
                } else {
                    self.dictationFlowCoordinator?.hideIdlePill()
                }
            }
        }
    }

    private func observeOverlayPositionChange() {
        overlayPositionObserver = NotificationCenter.default.addObserver(
            forName: .hushOverlayPositionDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Re-show idle pill at new position if it was visible
                let wasShowingIdlePill = self.dictationFlowCoordinator?.isIdlePillVisible ?? false
                if wasShowingIdlePill {
                    self.dictationFlowCoordinator?.hideIdlePill()
                    self.dictationFlowCoordinator?.showIdlePill()
                }
            }
        }
    }

    private func observeStopOnlyViaUIChange() {
        stopOnlyViaUIObserver = NotificationCenter.default.addObserver(
            forName: .hushStopOnlyViaUIDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hotkeyManager?.persistentStopDisabled = self?.settingsViewModel.stopOnlyViaUI ?? false
            }
        }
    }

    private func applyActivationPolicyFromSettings() {
        let menuBarOnly = settingsViewModel.menuBarOnlyMode
        let wasMainWindowVisible = mainWindow?.isVisible ?? false
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
        if menuBarOnly && wasMainWindowVisible {
            mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var hotkeyMenuTitle: String {
        "Hotkey: \(HotkeyTrigger.current.displayName) (double-tap / hold)"
    }

    private func maybeShowOnboarding() {
        guard let env = appEnvironment else { return }
        let completed = UserDefaults.standard.string(forKey: OnboardingViewModel.onboardingCompletedKey) != nil
        if !completed {
            showOnboarding(
                permissionService: env.permissionService,
                sttClient: env.sttDispatcher,
                diarizationService: env.diarizationService
            )
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard reopenOnboardingOnNextActivate else { return }
        maybeShowOnboarding()
    }

    private func showOnboarding() {
        guard let env = appEnvironment else { return }
        showOnboarding(
            permissionService: env.permissionService,
            sttClient: env.sttDispatcher,
            diarizationService: env.diarizationService
        )
    }

    private func showOnboarding(
        permissionService: PermissionServiceProtocol,
        sttClient: STTClientProtocol,
        diarizationService: DiarizationServiceProtocol? = nil
    ) {
        onboardingWindowController.show(
            permissionService: permissionService,
            sttClient: sttClient,
            diarizationService: diarizationService,
            onFinish: { [weak self] in
                self?.reopenOnboardingOnNextActivate = false
                self?.refreshHotkeyAfterPermissions()
            },
            onOpenMainApp: { [weak self] in
                self?.openMainWindow()
            },
            onOpenSettings: {
                NotificationCenter.default.post(name: .hushOpenSettings, object: nil)
            },
            onIncompleteDismiss: { [weak self] in
                self?.reopenOnboardingOnNextActivate = true
            }
        )
    }

    // MARK: - Menu Bar Icon

    private func updateMenuBarIcon(state: BreathWaveIcon.MenuBarState) {
        statusItem?.button?.image = BreathWaveIcon.menuBarIcon(pointSize: 18, state: state)
    }

    private func showDockIconIfNeeded() {
        guard settingsViewModel.menuBarOnlyMode else { return }
        NSApp.setActivationPolicy(.regular)
    }

    private func hideDockIconIfNeeded() {
        guard settingsViewModel.menuBarOnlyMode else { return }
        guard !hasVisiblePrimaryWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    private var hasVisiblePrimaryWindow: Bool {
        (mainWindow?.isVisible ?? false) || onboardingWindowController.isVisible
    }

    // MARK: - Window Management

    @objc private func openMainWindow() {
        if mainWindow == nil { createMainWindow() }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openMainWindowToSettings() {
        mainWindowState.selectedItem = .settings
        openMainWindow()
    }

    @objc private func pasteLastDictation() {
        guard let env = appEnvironment else { return }
        Task {
            guard let dictation = (try? env.dictationRepo.fetchAll(limit: 1))?.first else { return }
            let text = dictation.cleanTranscript ?? dictation.rawTranscript
            await pasteFromMenu(text: text, clipboardService: env.clipboardService)
        }
    }

    @objc private func pasteRecentDictation(_ sender: NSMenuItem) {
        guard let env = appEnvironment,
              let id = sender.representedObject as? UUID else { return }
        Task {
            guard let dictation = try? env.dictationRepo.fetch(id: id) else { return }
            let text = dictation.cleanTranscript ?? dictation.rawTranscript
            await pasteFromMenu(text: text, clipboardService: env.clipboardService)
        }
    }

    private func pasteFromMenu(text: String, clipboardService: ClipboardServiceProtocol) async {
        NSApp.deactivate()
        try? await Task.sleep(for: .milliseconds(200))
        do {
            try await clipboardService.pasteText(text)
        } catch {
            await clipboardService.copyToClipboard(text)
        }
    }

    @objc private func transcribeFileFromMenu() {
        guard appEnvironment != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = AudioFileConverter.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }

        if panel.runModal() == .OK, let url = panel.url {
            openMainWindow()
            transcriptionViewModel.transcribeFile(url: url)
            SoundManager.shared.play(.fileDropped)
        }
    }

    private func rebuildRecentDictationsSubmenu(with dictations: [Dictation]) {
        guard let recentItem = recentDictationsMenuItem else { return }
        recentItem.isHidden = dictations.isEmpty

        let submenu = NSMenu()
        for dictation in dictations {
            let text = (dictation.cleanTranscript ?? dictation.rawTranscript)
                .replacingOccurrences(of: "\n", with: " ")
            let truncated = text.count > 40 ? String(text.prefix(40)) + "…" : text
            let item = NSMenuItem(title: truncated, action: #selector(pasteRecentDictation(_:)), keyEquivalent: "")
            item.representedObject = dictation.id
            submenu.addItem(item)
        }
        recentItem.submenu = submenu
    }

    private func createMainWindow() {
        let contentView = MainWindowView(
            state: mainWindowState,
            transcriptionViewModel: transcriptionViewModel,
            historyViewModel: historyViewModel,
            settingsViewModel: settingsViewModel,
            customWordsViewModel: customWordsViewModel,
            textSnippetsViewModel: textSnippetsViewModel,
            libraryViewModel: libraryViewModel
        )

        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: DesignSystem.Layout.sidebarMinWidth + DesignSystem.Layout.contentMinWidth,
                height: DesignSystem.Layout.windowMinHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = mainWindowState.selectedItem.rawValue
        window.center()
        window.setFrameAutosaveName("MainWindow2")
        window.minSize = NSSize(
            width: DesignSystem.Layout.sidebarMinWidth + DesignSystem.Layout.contentMinWidth,
            height: DesignSystem.Layout.windowMinHeight
        )
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.contentView = NSHostingView(rootView: contentView)
        window.delegate = self
        window.isReleasedWhenClosed = false


        mainWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        showDockIconIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        DispatchQueue.main.async { [weak self] in
            self?.hideDockIconIfNeeded()
        }
    }

    // MARK: - Alerts

    private func presentHotkeyUnavailableAlertIfNeeded() {
        #if !DEBUG
        guard !hasPresentedHotkeyUnavailableAlert else { return }
        guard settingsViewModel.accessibilityGranted == false else { return }
        // Don't nag about the hotkey while onboarding is pending – the user
        // hasn't had a chance to grant Accessibility permission yet.
        guard UserDefaults.standard.string(forKey: OnboardingViewModel.onboardingCompletedKey) != nil else { return }

        hasPresentedHotkeyUnavailableAlert = true
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Global Hotkey Unavailable"
        alert.informativeText =
            "Hush couldn't enable the system-wide hotkey because Accessibility access is missing."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openMainWindowToSettings()
        }
        #endif
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let env = appEnvironment else {
            pasteLastMenuItem?.isEnabled = false
            recentDictationsMenuItem?.isHidden = true
            return
        }
        let dictations = (try? env.dictationRepo.fetchAll(limit: 5)) ?? []
        pasteLastMenuItem?.isEnabled = !dictations.isEmpty
        rebuildRecentDictationsSubmenu(with: dictations)
    }
}
