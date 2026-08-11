import XCTest
@testable import HushCore

final class NeuralEngineInferenceGateTests: XCTestCase {
    func testSerializesConcurrentOperationsWhenRequired() async throws {
        let gate = NeuralEngineInferenceGate(serializesAccess: true)
        let probe = ConcurrentWorkProbe()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await gate.withExclusiveAccess {
                        await probe.enter()
                        do {
                            try await Task.sleep(for: .milliseconds(20))
                        } catch {
                            await probe.leave()
                            throw error
                        }
                        await probe.leave()
                    }
                }
            }
            try await group.waitForAll()
        }

        let maximum = await probe.maximumConcurrency
        XCTAssertEqual(maximum, 1)
    }

    func testAllowsConcurrentOperationsWhenSerializationIsDisabled() async throws {
        let gate = NeuralEngineInferenceGate(serializesAccess: false)
        let probe = ConcurrentWorkProbe()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await gate.withExclusiveAccess {
                        await probe.enter()
                        do {
                            try await Task.sleep(for: .milliseconds(20))
                        } catch {
                            await probe.leave()
                            throw error
                        }
                        await probe.leave()
                    }
                }
            }
            try await group.waitForAll()
        }

        let maximum = await probe.maximumConcurrency
        XCTAssertGreaterThan(maximum, 1)
    }

    func testThrownOperationReleasesExclusiveAccess() async throws {
        let gate = NeuralEngineInferenceGate(serializesAccess: true)

        do {
            _ = try await gate.withExclusiveAccess { () async throws -> Int in
                throw ExpectedFailure()
            }
            XCTFail("Expected the operation to throw")
        } catch is ExpectedFailure {
            // Expected.
        }

        let value = try await gate.withExclusiveAccess { 42 }
        XCTAssertEqual(value, 42)
    }

    func testCancelledWaiterDoesNotConsumePermit() async throws {
        let gate = NeuralEngineInferenceGate(serializesAccess: true)
        let holderStarted = TestLatch()
        let releaseHolder = TestLatch()

        let holder = Task {
            try await gate.withExclusiveAccess {
                await holderStarted.open()
                await releaseHolder.wait()
            }
        }
        await holderStarted.wait()

        let waiter = Task {
            try await gate.withExclusiveAccess { 7 }
        }
        let waiterQueued = await waitUntilPendingWaiterCount(1, in: gate)
        XCTAssertTrue(waiterQueued)
        waiter.cancel()

        let waiterRemoved = await waitUntilPendingWaiterCount(0, in: gate)
        XCTAssertTrue(waiterRemoved)
        await releaseHolder.open()
        try await holder.value

        do {
            _ = try await waiter.value
            XCTFail("Expected the queued waiter to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        let value = try await gate.withExclusiveAccess { 9 }
        XCTAssertEqual(value, 9)
    }

    func testQueuedOperationsAcquireInFIFOOrder() async throws {
        let gate = NeuralEngineInferenceGate(serializesAccess: true)
        let holderStarted = TestLatch()
        let releaseHolder = TestLatch()
        let order = AcquisitionOrderRecorder()

        let holder = Task {
            try await gate.withExclusiveAccess {
                await holderStarted.open()
                await releaseHolder.wait()
            }
        }
        await holderStarted.wait()

        var waiters: [Task<Int, Error>] = []
        for id in 1...3 {
            waiters.append(Task {
                try await gate.withExclusiveAccess {
                    await order.record(id)
                    return id
                }
            })
            let queued = await waitUntilPendingWaiterCount(id, in: gate)
            XCTAssertTrue(queued)
        }

        await releaseHolder.open()
        try await holder.value
        for waiter in waiters {
            _ = try await waiter.value
        }

        let acquiredOrder = await order.values
        XCTAssertEqual(acquiredOrder, [1, 2, 3])
    }

    func testCurrentOSRequiresSerializationOnlyBeforeMacOS15() {
        if #available(macOS 15, *) {
            XCTAssertFalse(NeuralEngineInferenceGate.serializationRequiredForCurrentOS)
        } else {
            XCTAssertTrue(NeuralEngineInferenceGate.serializationRequiredForCurrentOS)
        }
    }

    private func waitUntilPendingWaiterCount(
        _ expectedCount: Int,
        in gate: NeuralEngineInferenceGate,
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        let startedAt = ContinuousClock.now
        while await gate.pendingWaiterCount != expectedCount {
            if startedAt.duration(to: .now) >= timeout { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }
}

private struct ExpectedFailure: Error {}

private actor AcquisitionOrderRecorder {
    private(set) var values: [Int] = []

    func record(_ value: Int) {
        values.append(value)
    }
}

private actor ConcurrentWorkProbe {
    private var activeCount = 0
    private(set) var maximumConcurrency = 0

    func enter() {
        activeCount += 1
        maximumConcurrency = max(maximumConcurrency, activeCount)
    }

    func leave() {
        activeCount -= 1
    }
}

private actor TestLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
