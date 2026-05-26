import Foundation
import Observation

@Observable
public final class MediaPlayerViewModel {
    public var isPlaying: Bool = false
    public var currentTimeMs: Int = 0
    public var durationMs: Int = 0

    public init() {}

    public func togglePlayPause() {
        isPlaying.toggle()
    }

    public func seek(toMs ms: Int) {
        currentTimeMs = max(0, min(ms, durationMs))
    }
}
