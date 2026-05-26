import AppKit
import AVFoundation

/// Audio feedback system for Hush.
/// Preloads custom sounds for zero-latency playback. Falls back to macOS system sounds
/// when custom assets aren't bundled yet. Respects macOS sound settings.
public final class SoundManager {
    public static let shared = SoundManager()
    private static let uiAudioEnabledKey = "com.apple.sound.uiaudio.enabled"

    private var players: [AppSound: AVAudioPlayer] = [:]
    private let volume: Float = 0.3

    private init() {
        preloadSounds()
    }

    /// Play a sound effect.
    public func play(_ sound: AppSound) {
        // Respect macOS "Play sound effects" setting
        guard Self.isSystemSoundEffectsEnabled else { return }

        if let player = players[sound] {
            player.currentTime = 0
            player.play()
        } else if let systemName = sound.systemSoundFallback {
            NSSound(named: systemName)?.play()
        }
    }

    private static var isSystemSoundEffectsEnabled: Bool {
        if let value = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[uiAudioEnabledKey] as? Bool {
            return value
        }
        if let value = UserDefaults.standard.object(forKey: uiAudioEnabledKey) as? Bool {
            return value
        }
        // Default to enabled when the preference key is absent.
        return true
    }

    private func preloadSounds() {
        // Search all known bundles: the main bundle, SPM resource bundles embedded
        // next to the executable, and any nested .bundle packages inside the main bundle.
        let bundles = Self.allResourceBundles()

        for sound in AppSound.allCases {
            var url: URL?
            for bundle in bundles {
                url = bundle.url(forResource: sound.rawValue, withExtension: "aif")
                   ?? bundle.url(forResource: sound.rawValue, withExtension: "wav")
                if url != nil { break }
            }
            guard let url else { continue }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = volume
                player.prepareToPlay()
                players[sound] = player
            } catch {
                // Fall through to system sound fallback at play time
            }
        }
    }

    /// Discovers all bundles that might contain sound assets.
    /// Searches Bundle.main's resource directory (for .app bundles where SPM places
    /// resources in Contents/Resources/TargetName_TargetName.bundle), and also
    /// next to the executable (for bare SPM executables).
    private static func allResourceBundles() -> [Bundle] {
        var bundles = [Bundle.main]
        var searchDirs: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            searchDirs.append(resourceURL)
        }
        if let execURL = Bundle.main.executableURL?.deletingLastPathComponent() {
            searchDirs.append(execURL)
        }
        for dir in searchDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }
            for item in contents where item.pathExtension == "bundle" {
                if let b = Bundle(url: item), !bundles.contains(b) {
                    bundles.append(b)
                }
            }
        }
        return bundles
    }
}

/// Named sound effects for Hush.
/// Custom assets will be bundled as .aif files. Until then, system sounds are used.
public enum AppSound: String, CaseIterable {
    case recordStart = "record_start"
    case recordStop = "record_stop"
    case transcriptionComplete = "transcription_complete"
    case fileDropped = "file_dropped"
    case errorSoft = "error_soft"

    /// macOS system sound fallback when custom asset isn't bundled.
    /// recordStart has no system fallback to avoid the jarring "Tink" alert sound.
    public var systemSoundFallback: NSSound.Name? {
        switch self {
        case .recordStart: return "Pop"
        case .recordStop: return "Pop"
        case .transcriptionComplete: return "Glass"
        case .fileDropped: return "Pop"
        case .errorSoft: return "Basso"
        }
    }
}
