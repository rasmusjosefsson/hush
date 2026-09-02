import Foundation

final class ConversationTurnAccumulator: @unchecked Sendable {
    typealias TurnHandler = @Sendable ([Float]) -> Void

    private let lock = NSLock()
    private let sampleRate: Int
    private let speechThreshold: Float
    private let endSilenceSamples: Int
    private let minimumSpeechSamples: Int
    private let maximumTurnSamples: Int
    private let preRollLimit: Int
    private let onTurn: TurnHandler

    private var preRoll: [Float] = []
    private var turn: [Float] = []
    private var speechSamples = 0
    private var silenceSamples = 0
    private var active = false

    init(
        sampleRate: Int = 16_000,
        speechThreshold: Float = 0.004,
        endSilenceSeconds: Double = 0.9,
        minimumSpeechSeconds: Double = 0.5,
        maximumTurnSeconds: Double = 20,
        preRollSeconds: Double = 0.25,
        onTurn: @escaping TurnHandler
    ) {
        self.sampleRate = sampleRate
        self.speechThreshold = speechThreshold
        self.endSilenceSamples = Int(Double(sampleRate) * endSilenceSeconds)
        self.minimumSpeechSamples = Int(Double(sampleRate) * minimumSpeechSeconds)
        self.maximumTurnSamples = Int(Double(sampleRate) * maximumTurnSeconds)
        self.preRollLimit = Int(Double(sampleRate) * preRollSeconds)
        self.onTurn = onTurn
    }

    func ingest(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let rms = sqrt(samples.reduce(0) { $0 + ($1 * $1) } / Float(samples.count))
        var completed: [Float]?

        lock.withLock {
            if active {
                turn.append(contentsOf: samples)
                if rms >= speechThreshold {
                    speechSamples += samples.count
                    silenceSamples = 0
                } else {
                    silenceSamples += samples.count
                }

                if silenceSamples >= endSilenceSamples || turn.count >= maximumTurnSamples {
                    completed = finishLocked()
                }
            } else if rms >= speechThreshold {
                active = true
                turn = preRoll + samples
                speechSamples = samples.count
                silenceSamples = 0
                preRoll.removeAll(keepingCapacity: true)
            } else {
                preRoll.append(contentsOf: samples)
                if preRoll.count > preRollLimit {
                    preRoll.removeFirst(preRoll.count - preRollLimit)
                }
            }
        }

        if let completed { onTurn(completed) }
    }

    func flush() -> [Float]? {
        lock.withLock { finishLocked() }
    }

    func reset() {
        lock.withLock {
            preRoll.removeAll()
            turn.removeAll()
            speechSamples = 0
            silenceSamples = 0
            active = false
        }
    }

    private func finishLocked() -> [Float]? {
        defer {
            turn.removeAll(keepingCapacity: true)
            speechSamples = 0
            silenceSamples = 0
            active = false
            preRoll.removeAll(keepingCapacity: true)
        }
        guard speechSamples >= minimumSpeechSamples else { return nil }
        return turn
    }
}
