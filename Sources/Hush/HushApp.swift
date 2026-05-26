import AppKit
import HushCore

/// Hush - Local-first voice transcription for macOS
@main
struct HushApp {
    static func main() {
        CrashReporter.install()

        let app = NSApplication.shared

        guard #available(macOS 14.2, *) else {
            app.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "macOS 14.2+ Required"
            alert.informativeText = "Hush requires macOS 14.2 (Sonoma) or later."
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            return
        }

        let delegate = AppDelegate()
        app.delegate = delegate

        app.setActivationPolicy(AppPreferences.isMenuBarOnlyModeEnabled() ? .accessory : .regular)

        app.run()
    }
}
