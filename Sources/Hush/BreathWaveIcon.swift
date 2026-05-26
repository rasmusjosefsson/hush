import AppKit

/// Generates the Hush waveform icon programmatically.
///
/// Design: White audio waveform bars on a near-black background, symmetric
/// with energy peaking at the center. Bars fade slightly toward the edges.
///
/// The icon is drawn via Core Graphics so it scales perfectly at any size
/// and works as a template image (adapts to light/dark mode automatically).
enum BreathWaveIcon {

    // MARK: - Canonical Geometry (128×128 viewBox)

    // Bowl: circle cx=68, cy=34, r=26
    // Dot: cx=68, cy=34, r=6
    // Stem + cursive loop tail:
    //   M 42,34 L 42,82 C 42,100 30,110 18,112 C 6,114 2,106 8,98 C 14,90 30,88 42,92
    // Stroke width: 7 (large), 10 (small/menu bar)

    /// Menu bar icon state variants.
    enum MenuBarState {
        case idle
        case recording
        case processing
    }

    /// Load the parakeet silhouette as a **template** NSImage for menu bar use.
    /// The image is stored as a processed SwiftPM resource (menubar-icon.png / @2x).
    /// Template images adapt to light/dark mode automatically.
    static func menuBarIcon(pointSize: CGFloat = 18, state: MenuBarState = .idle) -> NSImage {
        let baseIcon = loadBaseMenuBarIcon(pointSize: pointSize)

        switch state {
        case .idle:
            return baseIcon
        case .recording:
            return compositeIcon(base: baseIcon, pointSize: pointSize, badgeColor: .systemRed)
        case .processing:
            return compositeIcon(base: baseIcon, pointSize: pointSize, badgeColor: .systemOrange)
        }
    }

    private static func loadBaseMenuBarIcon(pointSize: CGFloat) -> NSImage {
        // Try loading from SwiftPM resource bundle first, then fall back to main bundle.
        if let url = Bundle.module.url(forResource: "menubar-icon@2x", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: pointSize, height: pointSize)
            image.isTemplate = true
            return image
        }

        // Fallback: 1x version
        if let url = Bundle.module.url(forResource: "menubar-icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: pointSize, height: pointSize)
            image.isTemplate = true
            return image
        }

        // Last resort: return a system symbol
        let fallback = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Hush")
            ?? NSImage()
        fallback.size = NSSize(width: pointSize, height: pointSize)
        fallback.isTemplate = true
        return fallback
    }

    /// Composite the base icon with a colored status dot in the bottom-right corner.
    /// The resulting image is NOT a template (so the dot renders in color).
    /// The base icon is drawn using the menu bar's label color so it matches
    /// the idle template appearance in both light and dark mode.
    private static func compositeIcon(base: NSImage, pointSize: CGFloat, badgeColor: NSColor) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            // Use the base icon alpha channel as a mask, filled with the menu bar
            // foreground color. This replicates template-image rendering while keeping
            // isTemplate=false so the colored dot isn't tinted by the system.
            // NSStatusBar items use controlTextColor which is white on dark menu bars
            // and black on light ones (pre-Sonoma or accessibility settings).
            if let cgBase = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.clip(to: rect, mask: cgBase)
                NSColor.controlTextColor.setFill()
                ctx.fill(rect)
                ctx.restoreGState()
            }

            // Draw colored dot (bottom-right, 5pt diameter)
            let dotSize: CGFloat = 5
            let dotRect = NSRect(
                x: rect.maxX - dotSize - 0.5,
                y: 0.5,
                width: dotSize,
                height: dotSize
            )
            badgeColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        // NOT a template — the dot must render in color
        image.isTemplate = false
        return image
    }

    /// Create the waveform icon as a filled NSImage for app icon / dock use.
    /// White waveform bars on a near-black background.
    static func appIcon(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = size / 128.0
            let cornerRadius = 22 * s

            // Background — dark neutral gradient matching macOS icon style
            let bg = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            let gradient = NSGradient(
                starting: NSColor(red: 0.192, green: 0.192, blue: 0.192, alpha: 1.0),
                ending: NSColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)
            )
            gradient?.draw(in: bg, angle: -90)

            // Waveform bars
            Self.drawWaveformBars(in: rect, scale: s, color: .white)

            return true
        }
        return image
    }

    // MARK: - Shared waveform geometry

    /// Heights pattern: symmetric audio waveform with energy peaking at center.
    static let waveformHeights: [CGFloat] = [
        0.28, 0.58, 0.90, 0.52, 0.32
    ]

    /// Vertical offset per bar (fraction of rect height). Gives an organic feel.
    static let waveformOffsets: [CGFloat] = [
        0.0, -0.02, 0.0, 0.04, 0.0
    ]

    /// Draw the canonical waveform bars centered in the given rect.
    /// `color` is the base bar color; bars fade slightly toward the edges.
    static func drawWaveformBars(in rect: NSRect, scale s: CGFloat, color: NSColor) {
        let totalBars = waveformHeights.count
        let barWidth: CGFloat = 10.0 * s
        let barSpacing: CGFloat = 10.0 * s
        let totalWidth = CGFloat(totalBars) * barWidth + CGFloat(totalBars - 1) * barSpacing
        let startX = rect.midX - totalWidth / 2.0
        let centerY = rect.midY

        for i in 0..<totalBars {
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let h = waveformHeights[i] * rect.height * 0.55
            let yOffset = waveformOffsets[i] * rect.height
            let barRect = NSRect(
                x: x,
                y: centerY - h / 2 + yOffset,
                width: barWidth,
                height: h
            )
            let bar = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)

            let distFromCenter = abs(CGFloat(i) - CGFloat(totalBars - 1) / 2.0) / (CGFloat(totalBars - 1) / 2.0)
            let alpha = 1.0 - distFromCenter * 0.35
            color.withAlphaComponent(alpha).setFill()
            bar.fill()
        }
    }
}
