import Foundation

public enum AppPreferences {
    public static let menuBarOnlyModeKey = "menuBarOnlyMode"

    public static func isMenuBarOnlyModeEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: menuBarOnlyModeKey) as? Bool ?? false
    }
}

/// Where the dictation overlay and idle pill are positioned on screen.
public enum OverlayPosition: String, CaseIterable, Sendable {
    /// Bottom-center, just above the Dock (default).
    case bottom
    /// Top-center, hugging the notch / menu bar area.
    case top
}
