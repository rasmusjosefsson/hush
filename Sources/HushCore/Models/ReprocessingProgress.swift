import Foundation

/// Progress information for the reprocess-with-speakers pipeline.
public struct ReprocessingProgress: Sendable {
    public enum Phase: Sendable, Equatable {
        case transcribing
        case analyzingSpeakers
        case finalizing
    }

    /// Current pipeline phase.
    public let phase: Phase

    /// Overall progress from 0.0 to 1.0 across all phases.
    public let fractionCompleted: Double

    public init(phase: Phase, fractionCompleted: Double) {
        self.phase = phase
        self.fractionCompleted = min(1.0, max(0.0, fractionCompleted))
    }
}
