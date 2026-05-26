import AppKit

/// Detects the physical notch dimensions on macOS screens with a camera housing.
/// Uses public NSScreen APIs available since macOS 12 (Monterey).
///
/// On a notch MacBook Pro 14"/16", typical values:
///   - notchWidth: ~200pt  (the black camera housing cutout)
///   - notchHeight: ~38pt  (safeAreaInsets.top)
///   - Camera is centered horizontally in the notch cutout.
///   - notchMinX / notchMaxX mark the edges of the INVISIBLE hardware cutout.
///   - Content MUST be placed outside notchMinX...notchMaxX to be visible.
///
/// On non-notch screens: `hasNotch` is false, dimensions are zero.
@MainActor
struct NotchGeometry {
    let hasNotch: Bool
    /// Width of the physical notch cutout (the hardware camera housing).
    let notchWidth: CGFloat
    /// Height of the physical notch (safeAreaInsets.top).
    let notchHeight: CGFloat
    /// The x where the invisible cutout STARTS (left edge). Content left of this is visible.
    let notchMinX: CGFloat
    /// The x where the invisible cutout ENDS (right edge). Content right of this is visible.
    let notchMaxX: CGFloat
    /// The center x of the cutout (where the camera lens is).
    let notchCenterX: CGFloat

    /// Detect notch geometry for the given screen (defaults to main screen).
    static func detect(for screen: NSScreen? = NSScreen.main) -> NotchGeometry {
        guard let screen else {
            return .none
        }

        let safeTop = screen.safeAreaInsets.top
        guard safeTop > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return .none
        }

        let screenFrame = screen.frame
        let leftWidth = leftArea.width
        let rightWidth = rightArea.width
        let notchWidth = screenFrame.width - leftWidth - rightWidth

        let notchMinX = screenFrame.origin.x + leftWidth
        let notchMaxX = screenFrame.origin.x + screenFrame.width - rightWidth

        return NotchGeometry(
            hasNotch: true,
            notchWidth: notchWidth,
            notchHeight: safeTop,
            notchMinX: notchMinX,
            notchMaxX: notchMaxX,
            notchCenterX: (notchMinX + notchMaxX) / 2
        )
    }

    private static let none = NotchGeometry(
        hasNotch: false,
        notchWidth: 0,
        notchHeight: 0,
        notchMinX: 0,
        notchMaxX: 0,
        notchCenterX: 0
    )

    // MARK: - Positioning for single-side pill (idle pill, non-recording states)

    /// X-origin for a small panel in the RIGHT ear (immediately after the notch cutout).
    /// Content is left-aligned in the panel, so it appears right at the notch edge.
    /// Falls back to centered for non-notch screens.
    func rightEarOriginX(panelWidth: CGFloat, screenFrame: NSRect) -> CGFloat {
        guard hasNotch else {
            return screenFrame.midX - panelWidth / 2
        }
        // Panel left edge at the right edge of the cutout (first visible pixel)
        let x = notchMaxX
        return min(x, screenFrame.maxX - panelWidth)
    }

    // MARK: - Positioning for split panel (recording state: content on BOTH sides of camera)

    /// X-origin for a wide panel centered on the notch. The panel spans across the cutout
    /// so content can be placed on BOTH sides. The view uses `notchWidth` to leave a gap
    /// in the center matching the cutout.
    func centeredOriginX(panelWidth: CGFloat, screenFrame: NSRect) -> CGFloat {
        guard hasNotch else {
            return screenFrame.midX - panelWidth / 2
        }
        // Center the panel on the notch center
        return notchCenterX - panelWidth / 2
    }

    /// Y-origin that pins the panel's top edge to the screen top.
    func topOriginY(panelHeight: CGFloat, screenFrame: NSRect) -> CGFloat {
        screenFrame.maxY - panelHeight
    }
}
