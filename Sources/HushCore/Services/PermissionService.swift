import AppKit
import AVFoundation
import ApplicationServices
import Foundation

public protocol PermissionServiceProtocol: Sendable {
    func checkMicrophonePermission() async -> PermissionStatus
    func requestMicrophonePermission() async -> Bool
    func checkAccessibilityPermission() -> Bool
    func requestAccessibilityPermission(prompt: Bool) -> Bool
    func checkScreenRecordingPermission() -> Bool
    func requestScreenRecordingPermission() -> Bool
    func openMicrophoneSettings()
    func openScreenRecordingSettings()
}

public enum PermissionStatus: Sendable {
    case granted
    case denied
    case notDetermined
}

public final class PermissionService: PermissionServiceProtocol, Sendable {
    public init() {}

    public func checkMicrophonePermission() async -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    public func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func checkAccessibilityPermission() -> Bool {
        // AXIsProcessTrusted() checks if the app has Accessibility permission
        return AXIsProcessTrusted()
    }

    public func requestAccessibilityPermission(prompt: Bool = true) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func checkScreenRecordingPermission() -> Bool {
        if #available(macOS 15, *) {
            return CGPreflightScreenCaptureAccess()
        } else {
            let img = CGWindowListCreateImage(
                CGRect(x: 0, y: 0, width: 1, height: 1),
                .optionOnScreenOnly,
                kCGNullWindowID,
                .bestResolution
            )
            return img != nil
        }
    }

    public func requestScreenRecordingPermission() -> Bool {
        if #available(macOS 15, *) {
            CGRequestScreenCaptureAccess()
            return CGPreflightScreenCaptureAccess()
        } else {
            // Pre-macOS 15: opening System Settings is the only way to prompt
            openScreenRecordingSettings()
            return false
        }
    }

    public func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    public func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
