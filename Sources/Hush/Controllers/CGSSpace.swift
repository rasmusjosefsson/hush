import AppKit

/// Small CoreGraphicsServices Spaces API wrapper using private SPI.
/// Creates a compositing space at the specified absolute level.
/// Windows added to a CGSSpace at `Int32.max` render above everything,
/// including the menu bar and notch area.
///
/// Ported from boring.notch (original source: github.com/avaidyam/Parrot).
/// Initialized spaces MUST be de-initialized upon app exit.
public final class CGSSpace {
    private let identifier: CGSSpaceID

    public var windows: Set<NSWindow> = [] {
        didSet {
            let remove = oldValue.subtracting(self.windows)
            let add = self.windows.subtracting(oldValue)

            CGSRemoveWindowsFromSpaces(
                _CGSDefaultConnection(),
                remove.map { $0.windowNumber } as NSArray,
                [self.identifier]
            )
            CGSAddWindowsToSpaces(
                _CGSDefaultConnection(),
                add.map { $0.windowNumber } as NSArray,
                [self.identifier]
            )
        }
    }

    public init(level: Int = 0) {
        let flag = 0x1  // MUST be 1, otherwise Finder draws desktop icons
        self.identifier = CGSSpaceCreate(_CGSDefaultConnection(), flag, nil)
        CGSSpaceSetAbsoluteLevel(_CGSDefaultConnection(), self.identifier, level)
        CGSShowSpaces(_CGSDefaultConnection(), [self.identifier])
    }

    deinit {
        CGSHideSpaces(_CGSDefaultConnection(), [self.identifier])
        CGSSpaceDestroy(_CGSDefaultConnection(), self.identifier)
    }
}

// MARK: - Private CGS SPI declarations

private typealias CGSConnectionID = UInt
private typealias CGSSpaceID = UInt64

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID

@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ cid: CGSConnectionID, _ unknown: Int, _ options: NSDictionary?) -> CGSSpaceID

@_silgen_name("CGSSpaceDestroy")
private func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)

@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)

@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)

@_silgen_name("CGSHideSpaces")
private func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)

@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
