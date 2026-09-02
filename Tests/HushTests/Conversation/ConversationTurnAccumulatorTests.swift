@testable import HushCore
import XCTest

final class ConversationTurnAccumulatorTests: XCTestCase {
    func testFinalizesAfterSilence() {
        let turns = TurnBox()
        let accumulator = ConversationTurnAccumulator(
            sampleRate: 100,
            speechThreshold: 0.1,
            endSilenceSeconds: 0.2,
            minimumSpeechSeconds: 0.1,
            maximumTurnSeconds: 5,
            preRollSeconds: 0,
            onTurn: { turns.append($0) }
        )

        accumulator.ingest(Array(repeating: 0.5, count: 15))
        accumulator.ingest(Array(repeating: 0, count: 20))

        XCTAssertEqual(turns.values.count, 1)
        XCTAssertEqual(turns.values[0].count, 35)
    }

    func testIgnoresShortNoise() {
        let turns = TurnBox()
        let accumulator = ConversationTurnAccumulator(
            sampleRate: 100,
            speechThreshold: 0.1,
            endSilenceSeconds: 0.2,
            minimumSpeechSeconds: 0.5,
            maximumTurnSeconds: 5,
            preRollSeconds: 0,
            onTurn: { turns.append($0) }
        )

        accumulator.ingest(Array(repeating: 0.5, count: 10))
        accumulator.ingest(Array(repeating: 0, count: 20))

        XCTAssertTrue(turns.values.isEmpty)
    }

    func testFlushReturnsPendingSpeech() {
        let accumulator = ConversationTurnAccumulator(
            sampleRate: 100,
            speechThreshold: 0.1,
            endSilenceSeconds: 1,
            minimumSpeechSeconds: 0.1,
            maximumTurnSeconds: 5,
            preRollSeconds: 0,
            onTurn: { _ in }
        )

        accumulator.ingest(Array(repeating: 0.5, count: 20))

        XCTAssertEqual(accumulator.flush()?.count, 20)
        XCTAssertNil(accumulator.flush())
    }
}

private final class TurnBox: @unchecked Sendable {
    private let lock = NSLock()
    private var turns: [[Float]] = []

    var values: [[Float]] { lock.withLock { turns } }

    func append(_ turn: [Float]) {
        lock.withLock { turns.append(turn) }
    }
}
