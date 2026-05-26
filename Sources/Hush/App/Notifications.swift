import Foundation

extension Notification.Name {
    static let hushOpenOnboarding = Notification.Name("hush.openOnboarding")
    static let hushOpenSettings = Notification.Name("hush.openSettings")
    static let hushHotkeyTriggerDidChange = Notification.Name("hush.hotkeyTriggerDidChange")
    static let hushMenuBarOnlyModeDidChange = Notification.Name("hush.menuBarOnlyModeDidChange")
    static let hushShowIdlePillDidChange = Notification.Name("hush.showIdlePillDidChange")
    static let hushOverlayPositionDidChange = Notification.Name("hush.overlayPositionDidChange")
    static let hushStopOnlyViaUIDidChange = Notification.Name("hush.stopOnlyViaUIDidChange")
}
