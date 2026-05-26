import Foundation

@MainActor
@Observable
public final class IdlePillViewModel {
    public var isHovered: Bool = false
    public var isTopPosition: Bool = false
    /// Height of the notch (safeAreaInsets.top). Used to push content below the camera.
    public var notchHeight: CGFloat = 0
    /// Width of the notch camera cutout. Used to size the grow-down background.
    public var notchGapWidth: CGFloat = 0
    public var onStartDictation: (() -> Void)?

    public init() {}
}
