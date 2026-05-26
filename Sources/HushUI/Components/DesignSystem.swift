import SwiftUI

/// Centralized design tokens for consistent styling across the app.
/// "Warm Magical" design system — coral-orange accent, generous spacing, rounded headlines.
public enum DesignSystem {
    // MARK: - Colors

    public enum Colors {
        // Accent — warm peach primary
        public static let accent = Color(light: .init(red: 0.91, green: 0.42, blue: 0.23),
                                  dark: .init(red: 1.0, green: 0.878, blue: 0.761))
        public static let accentLight = Color(light: .init(red: 1.0, green: 0.94, blue: 0.92),
                                       dark: .init(red: 0.224, green: 0.188, blue: 0.157))
        public static let accentDark = Color(light: .init(red: 0.77, green: 0.33, blue: 0.16),
                                       dark: .init(red: 0.90, green: 0.75, blue: 0.58))

        // Backgrounds
        public static let background = Color(light: .init(red: 0.98, green: 0.98, blue: 0.97),
                                      dark: .init(red: 0.067, green: 0.067, blue: 0.067))
        public static let surface = Color(light: .white,
                                   dark: .init(red: 0.098, green: 0.098, blue: 0.098))
        public static let surfaceElevated = Color(light: .init(red: 0.96, green: 0.96, blue: 0.94),
                                           dark: .init(red: 0.133, green: 0.133, blue: 0.133))

        // Text
        public static let textPrimary = Color(light: .init(red: 0.10, green: 0.10, blue: 0.10),
                                       dark: .init(red: 0.933, green: 0.933, blue: 0.933))
        public static let textSecondary = Color(light: .init(red: 0.42, green: 0.42, blue: 0.42),
                                         dark: .init(red: 0.706, green: 0.706, blue: 0.706))
        public static let textTertiary = Color(light: .init(red: 0.61, green: 0.61, blue: 0.61),
                                        dark: .init(red: 0.39, green: 0.39, blue: 0.40))

        // Semantic
        public static let successGreen = Color(light: .init(red: 0.20, green: 0.66, blue: 0.33),
                                        dark: .init(red: 0.29, green: 0.87, blue: 0.50))
        public static let warningAmber = Color(light: .init(red: 0.96, green: 0.65, blue: 0.14),
                                        dark: .init(red: 0.98, green: 0.75, blue: 0.14))
        public static let errorRed = Color(light: .init(red: 0.90, green: 0.30, blue: 0.26),
                                    dark: .init(red: 0.898, green: 0.302, blue: 0.180))
        public static let onAccent = Color(light: .white,
                                         dark: .init(red: 0.13, green: 0.10, blue: 0.07))

        // Borders & dividers
        public static let border = Color(light: .init(red: 0.91, green: 0.91, blue: 0.88),
                                  dark: .init(red: 0.125, green: 0.118, blue: 0.094))
        public static let divider = Color(light: .init(red: 0.94, green: 0.94, blue: 0.91),
                                   dark: .init(red: 0.153, green: 0.153, blue: 0.165))

        // Interactive
        public static let rowHoverBackground = Color(light: .init(red: 0.96, green: 0.96, blue: 0.94),
                                              dark: .primary.opacity(0.06))
        public static let cardBackground = Color(light: .white,
                                          dark: .init(red: 0.098, green: 0.098, blue: 0.098))

        // Playback
        public static let playbackTrack = Color.primary.opacity(0.08)
        public static let playbackFill = Color.accentColor

        // Meeting pill
        public static let meetingPillBackground = Color(light: .black.opacity(0.88), dark: .black.opacity(0.90))
        public static let meetingPillBackgroundHover = Color(light: .black.opacity(0.90), dark: .init(red: 0.18, green: 0.18, blue: 0.19).opacity(0.95))
        public static let meetingPillStroke = Color.white.opacity(0.08)
        public static let meetingPillStrokeHover = Color.white.opacity(0.15)
        public static let meetingPillText = Color.white.opacity(0.9)
        public static let meetingPillBadgeBackground = Color.black.opacity(0.8)

        // Speaker diarization palette — distinct, readable in both light/dark
        public static let speakerColors: [Color] = [
            Color(light: .init(red: 0.20, green: 0.51, blue: 0.84),
                  dark: .init(red: 0.42, green: 0.68, blue: 0.96)),   // Blue
            Color(light: .init(red: 0.72, green: 0.33, blue: 0.64),
                  dark: .init(red: 0.85, green: 0.52, blue: 0.78)),   // Purple
            Color(light: .init(red: 0.16, green: 0.60, blue: 0.46),
                  dark: .init(red: 0.30, green: 0.78, blue: 0.62)),   // Teal
            Color(light: .init(red: 0.82, green: 0.52, blue: 0.14),
                  dark: .init(red: 0.95, green: 0.68, blue: 0.30)),   // Amber
            Color(light: .init(red: 0.80, green: 0.28, blue: 0.28),
                  dark: .init(red: 0.95, green: 0.45, blue: 0.45)),   // Red
            Color(light: .init(red: 0.40, green: 0.56, blue: 0.24),
                  dark: .init(red: 0.56, green: 0.76, blue: 0.38)),   // Green
        ]

        public static func speakerColor(for index: Int) -> Color {
            speakerColors[index % speakerColors.count]
        }

        // YouTube badge
        public static let youtubeRed = Color.red

        // Legacy aliases — pill/overlay (UNTOUCHED, these stay as-is for the pill)
        public static let pillBackground = Color.black.opacity(0.9)
        public static let pillBorder = Color.white.opacity(0.15)
        public static let recordingRed = Color.red

        // Sidebar
        public static let contentBackground = Color(nsColor: .textBackgroundColor)
    }

    // MARK: - Spacing

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
        public static let hero: CGFloat = 64
    }

    // MARK: - Typography

    public enum Typography {
        // Headlines — .rounded design = instantly warmer
        public static let heroTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        public static let pageTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
        public static let sectionTitle = Font.system(size: 17, weight: .semibold)

        // Body — larger minimums
        public static let bodyLarge = Font.system(size: 15)
        public static let body = Font.system(size: 14)
        public static let bodySmall = Font.system(size: 13)

        // Metadata
        public static let caption = Font.system(size: 12)
        public static let micro = Font.system(size: 11)

        // Meeting pill
        public static let meetingPillStatus = Font.system(size: 13, weight: .semibold)
        public static let meetingPillBadge = Font.system(size: 10, weight: .medium, design: .monospaced)
        public static let meetingPillCheckmark = Font.system(size: 24, weight: .semibold)

        // Monospace
        public static let timestamp = Font.system(size: 12).monospacedDigit()
        public static let duration = Font.system(size: 11).monospacedDigit()

        // Legacy aliases (kept for existing references)
        public static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
        public static let title = Font.system(size: 22, weight: .semibold, design: .rounded)
        public static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        public static let sectionHeader = Font.system(size: 13, weight: .semibold)
    }

    // MARK: - Layout

    public enum Layout {
        public static let sidebarMinWidth: CGFloat = 260
        public static let contentMinWidth: CGFloat = 500
        public static let windowMinHeight: CGFloat = 560
        public static let cornerRadius: CGFloat = 16
        public static let cardCornerRadius: CGFloat = 14
        public static let rowCornerRadius: CGFloat = 12
        public static let dropZoneCornerRadius: CGFloat = 20
        public static let buttonCornerRadius: CGFloat = 12
        public static let minTouchTarget: CGFloat = 44
        public static let dropZoneHeight: CGFloat = 200
        public static let playbackBarHeight: CGFloat = 6
        public static let videoPlayerMinWidth: CGFloat = 320
        public static let videoPlayerIdealRatio: CGFloat = 0.4
        public static let audioScrubberHeight: CGFloat = 44
        public static let thumbnailCardMinWidth: CGFloat = 200
        public static let thumbnailAspectRatio: CGFloat = 16 / 9
    }

    // MARK: - Animation

    public enum Animation {
        public static let selectionChange: SwiftUI.Animation = .easeInOut(duration: 0.15)
        public static let hoverTransition: SwiftUI.Animation = .easeInOut(duration: 0.12)
        public static let contentSwap: SwiftUI.Animation = .easeInOut(duration: 0.2)
        public static let portalLift: SwiftUI.Animation = .spring(response: 0.3, dampingFraction: 0.7)
        public static let meetingPillHover: SwiftUI.Animation = .easeOut(duration: 0.15)
    }

    // MARK: - Shadows

    public enum Shadows {
        public static let cardRest = ShadowStyle(color: .black.opacity(0.06), radius: 4, y: 2)
        public static let cardHover = ShadowStyle(color: .black.opacity(0.10), radius: 12, y: 6)
        public static let portalLift = ShadowStyle(color: .black.opacity(0.12), radius: 16, y: 8)
        public static let meetingPill = ShadowStyle(color: .black.opacity(0.28), radius: 12, y: 6)
    }
}

// MARK: - Shadow Style

public struct ShadowStyle {
    public let color: Color
    public let radius: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.y = y
    }
}

// MARK: - Adaptive Color Helper

// MARK: - Brand Waveform Icon

/// SwiftUI recreation of the canonical Hush waveform identity (5 rounded bars).
/// Matches the geometry defined in `BreathWaveIcon.drawWaveformBars`.
public struct BrandWaveformView: View {
    var size: CGFloat
    var color: Color = .primary

    /// Heights pattern: symmetric audio waveform with energy peaking at center.
    private static let heights: [CGFloat] = [0.28, 0.58, 0.90, 0.52, 0.32]
    /// Vertical offset per bar (fraction of height). Gives an organic feel.
    private static let offsets: [CGFloat] = [0.0, -0.02, 0.0, 0.04, 0.0]

    public init(size: CGFloat, color: Color = .primary) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let totalBars = Self.heights.count
            let barWidth = canvasSize.width / CGFloat(totalBars * 2 - 1)
            let spacing = barWidth
            let totalWidth = CGFloat(totalBars) * barWidth + CGFloat(totalBars - 1) * spacing
            let startX = (canvasSize.width - totalWidth) / 2
            let centerY = canvasSize.height / 2

            for i in 0..<totalBars {
                let x = startX + CGFloat(i) * (barWidth + spacing)
                let h = Self.heights[i] * canvasSize.height * 0.85
                let yOffset = Self.offsets[i] * canvasSize.height
                let cornerRadius = barWidth / 2
                let rect = CGRect(
                    x: x,
                    y: centerY - h / 2 + yOffset,
                    width: barWidth,
                    height: h
                )
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
                let distFromCenter = abs(CGFloat(i) - CGFloat(totalBars - 1) / 2.0) / (CGFloat(totalBars - 1) / 2.0)
                let alpha = 1.0 - distFromCenter * 0.35
                context.fill(path, with: .color(color.opacity(alpha)))
            }
        }
        .frame(width: size, height: size)
    }
}

extension Color {
    /// Creates a color that adapts to light/dark mode.
    public init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
    }
}

// MARK: - Shadow View Modifier

extension View {
    public func cardShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: 0, y: style.y)
    }
}
