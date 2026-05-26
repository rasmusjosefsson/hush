import Foundation

/// Singleton that holds a CGSSpace at the maximum absolute level.
/// Any NSWindow added to `notchSpace.windows` will be composited above
/// everything else on screen, including the menu bar and notch region.
///
/// Matching boring.notch's approach: they create one CGSSpace at Int32.max
/// and add their notch windows to it.
final class NotchSpaceManager {
    static let shared = NotchSpaceManager()

    let notchSpace: CGSSpace

    private init() {
        notchSpace = CGSSpace(level: Int(Int32.max))
    }
}
