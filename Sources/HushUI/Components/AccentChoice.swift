import AppKit
import SwiftUI

/// User-selectable accent color, persisted in UserDefaults and read by `DesignSystem.Colors.accent`.
public enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case coral, system, blue, purple, pink, red, orange, yellow, green, graphite

    public static let storageKey = "appearance.accentChoice"
    public static let `default`: AccentChoice = .coral

    public static var current: AccentChoice {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AccentChoice.init) ?? .default
    }

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .coral: "Hush Coral"
        case .system: "System"
        case .graphite: "Graphite"
        default: rawValue.capitalized
        }
    }

    private var nsColor: NSColor {
        switch self {
        case .coral:
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(srgbRed: 1.0, green: 0.52, blue: 0.34, alpha: 1)
                    : NSColor(srgbRed: 0.91, green: 0.40, blue: 0.22, alpha: 1)
            }
        case .system: .controlAccentColor
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .graphite: .systemGray
        }
    }

    public var color: Color { Color(nsColor: nsColor) }

    /// Slightly deeper variant for pressed states and text on tinted fills.
    public var pressedColor: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            var resolved = nsColor
            appearance.performAsCurrentDrawingAppearance { resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor }
            return resolved.blended(withFraction: 0.18, of: .black) ?? resolved
        })
    }

    /// Variant that reads well on the always-dark notch / pill.
    public var overlayColor: Color {
        Color(nsColor: NSColor(name: nil) { _ in
            var resolved = nsColor
            NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
                resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor
            }
            return self == .graphite ? .white : resolved
        })
    }
}
