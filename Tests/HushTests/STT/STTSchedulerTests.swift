import XCTest
@testable import HushCore

final class STTSchedulerTests: XCTestCase {
    func testInteractiveAndBackgroundJobsCanRunConcurrently() async throws {
        let runtime = SchedulerRuntimeProbe(delay: .milliseconds(40))
        let scheduler = STTScheduler(runtimeProvider: runtime)

        async let dictation = scheduler.transcribe(audioPath: "dictation.wav", job: .dictation)
        async let file = scheduler.transcribe(audioPath: "file.wav", job: .fileTranscription)
        _ = try await (dictation, file)

        let maximum = await runtime.maximumConcurrency
        XCTAssertEqual(maximum, 2)
    }

    func testBackgroundJobsRunOneAtATime() async throws {
        let runtime = SchedulerRuntimeProbe(delay: .milliseconds(20))
        let scheduler = STTScheduler(runtimeProvider: runtime)

        async let first = scheduler.transcribe(audioPath: "one.wav", job: .fileTranscription)
        async let second = scheduler.transcribe(audioPath: "two.wav", job: .meetingLiveChunk)
        async let third = scheduler.transcribe(audioPath: "three.wav", job: .meetingFinalize)
        _ = try await (first, second, third)

        let maximum = await runtime.maximumConcurrency
        XCTAssertEqual(maximum, 1)
    }

    func testMeetingFinalizationRunsBeforeQueuedFileTranscription() async throws {
        let blocker = SchedulerTestLatch()
        let runtime = SchedulerRuntimeProbe(blocker: blocker)
        let scheduler = STTScheduler(runtimeProvider: runtime)

        let runningFile = Task {
            try await scheduler.transcribe(audioPath: "running.wav", job: .fileTranscription)
        }
        let runningFileStarted = await runtime.waitUntilStarted(count: 1)
        XCTAssertTrue(runningFileStarted)

        let queuedFile = Task {
            try await scheduler.transcribe(audioPath: "queued.wav", job: .fileTranscription)
        }
        let finalization = Task {
            try await scheduler.transcribe(audioPath: "meeting.wav", job: .meetingFinalize)
        }
        try await Task.sleep(for: .milliseconds(20))
        await blocker.open()

        _ = try await runningFile.value
        _ = try await queuedFile.value
        _ = try await finalization.value

        let jobs = await runtime.startedJobs
        XCTAssertEqual(jobs, [.fileTranscription, .meetingFinalize, .fileTranscription])
    }

    func testCancellingQueuedJobDoesNotRunIt() async throws {
        let blocker = SchedulerTestLatch()
        let runtime = SchedulerRuntimeProbe(blocker: blocker)
        let scheduler = STTScheduler(runtimeProvider: runtime)

        let running = Task {
            try await scheduler.transcribe(audioPath: "running.wav", job: .fileTranscription)
        }
        let runningFileStarted = await runtime.waitUntilStarted(count: 1)
        XCTAssertTrue(runningFileStarted)

        let queued = Task {
            try await scheduler.transcribe(audioPath: "queued.wav", job: .fileTranscription)
        }
        try await Task.sleep(for: .milliseconds(10))
        queued.cancel()
        await blocker.open()

        _ = try await running.value
        do {
            _ = try await queued.value
            XCTFail("Expected queued work to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        let jobs = await runtime.startedJobs
        XCTAssertEqual(jobs, [.fileTranscription])
    }

    func testShutdownCancelsRunningWorkAndRejectsNewJobs() async throws {
        let runtime = SchedulerRuntimeProbe(delay: .seconds(10))
        let scheduler = STTScheduler(runtimeProvider: runtime)
        let running = Task {
            try await scheduler.transcribe(audioPath: "running.wav", job: .dictation)
        }
        let dictationStarted = await runtime.waitUntilStarted(count: 1)
        XCTAssertTrue(dictationStarted)

        await scheduler.shutdown()

        do {
            _ = try await running.value
            XCTFail("Expected running work to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        do {
            _ = try await scheduler.transcribe(audioPath: "later.wav", job: .dictation)
            XCTFail("Expected a shut down scheduler to reject work")
        } catch let error as STTSchedulerError {
            XCTAssertEqual(error, .unavailable)
        }
    }

    func testCacheClearRejectsJobsUntilRuntimeMaintenanceFinishes() async throws {
        let cacheClearStarted = SchedulerTestLatch()
        let releaseCacheClear = SchedulerTestLatch()
        let runtime = CacheClearRuntimeProbe(
            started: cacheClearStarted,
            release: releaseCacheClear
        )
        let scheduler = STTScheduler(runtimeProvider: runtime)

        let clearing = Task { await scheduler.clearModelCache() }
        await cacheClearStarted.wait()

        do {
            _ = try await scheduler.transcribe(audioPath: "during-clear.wav", job: .dictation)
            XCTFail("Expected cache maintenance to reject new work")
        } catch let error as STTSchedulerError {
            XCTAssertEqual(error, .unavailable)
        }

        await releaseCacheClear.open()
        await clearing.value

        let result = try await scheduler.transcribe(audioPath: "after-clear.wav", job: .dictation)
        XCTAssertEqual(result.text, "after-clear.wav")
    }

    func testCancellationWinsWhenRunningRuntimeReturnsSuccess() async throws {
        let started = SchedulerTestLatch()
        let release = SchedulerTestLatch()
        let runtime = NonCooperativeRuntimeProbe(started: started, release: release)
        let scheduler = STTScheduler(runtimeProvider: runtime)
        let running = Task {
            try await scheduler.transcribe(audioPath: "running.wav", job: .dictation)
        }
        await started.wait()

        running.cancel()
        await release.open()

        do {
            _ = try await running.value
            XCTFail("Expected caller cancellation to win over a late runtime result")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testShutdownCancellationWinsOverNonCooperativeRuntimeSuccess() async throws {
        let started = SchedulerTestLatch()
        let release = SchedulerTestLatch()
        let runtime = NonCooperativeRuntimeProbe(started: started, release: release)
        let scheduler = STTScheduler(runtimeProvider: runtime)
        let running = Task {
            try await scheduler.transcribe(audioPath: "running.wav", job: .dictation)
        }
        await started.wait()

        let shuttingDown = Task { await scheduler.shutdown() }
        try await Task.sleep(for: .milliseconds(10))
        await release.open()
        await shuttingDown.value

        do {
            _ = try await running.value
            XCTFail("Expected shutdown to cancel the caller's running job")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testConcurrentCacheClearsJoinOneRuntimeOperation() async throws {
        let started = SchedulerTestLatch()
        let release = SchedulerTestLatch()
        let runtime = CacheClearRuntimeProbe(started: started, release: release)
        let scheduler = STTScheduler(runtimeProvider: runtime)

        let first = Task { await scheduler.clearModelCache() }
        await started.wait()
        let second = Task { await scheduler.clearModelCache() }
        try await Task.sleep(for: .milliseconds(20))

        let clearCallCount = await runtime.clearCallCount
        XCTAssertEqual(clearCallCount, 1)
        do {
            _ = try await scheduler.transcribe(audioPath: "during-clears.wav", job: .dictation)
            XCTFail("Expected joined cache maintenance to keep rejecting work")
        } catch let error as STTSchedulerError {
            XCTAssertEqual(error, .unavailable)
        }

        await release.open()
        await first.value
        await second.value
    }

    func testShutdownWaitsForInFlightCacheClear() async throws {
        let clearStarted = SchedulerTestLatch()
        let releaseClear = SchedulerTestLatch()
        let runtime = MaintenanceSerializationRuntimeProbe(
            clearStarted: clearStarted,
            releaseClear: releaseClear
        )
        let scheduler = STTScheduler(runtimeProvider: runtime)

        let clearing = Task { await scheduler.clearModelCache() }
        await clearStarted.wait()
        let shuttingDown = Task { await scheduler.shutdown() }
        try await Task.sleep(for: .milliseconds(20))

        let overlapBeforeRelease = await runtime.maximumMaintenanceConcurrency
        XCTAssertEqual(overlapBeforeRelease, 1)
        await releaseClear.open()
        await clearing.value
        await shuttingDown.value

        let maximum = await runtime.maximumMaintenanceConcurrency
        XCTAssertEqual(maximum, 1)
        do {
            _ = try await scheduler.transcribe(audioPath: "after-shutdown.wav", job: .dictation)
            XCTFail("Expected shutdown to remain permanent")
        } catch let error as STTSchedulerError {
            XCTAssertEqual(error, .unavailable)
        }
    }

    func testConcurrentShutdownCallersJoinRuntimeShutdown() async throws {
        let shutdownStarted = SchedulerTestLatch()
        let releaseShutdown = SchedulerTestLatch()
        let runtime = BlockingShutdownRuntimeProbe(
            started: shutdownStarted,
            release: releaseShutdown
        )
        let scheduler = STTScheduler(runtimeProvider: runtime)
        let secondReturned = AsyncBoolean()

        let first = Task { await scheduler.shutdown() }
        await shutdownStarted.wait()
        let second = Task {
            await scheduler.shutdown()
            await secondReturned.setTrue()
        }
        try await Task.sleep(for: .milliseconds(20))

        let returnedBeforeRelease = await secondReturned.value
        let shutdownCallCount = await runtime.shutdownCallCount
        XCTAssertFalse(returnedBeforeRelease)
        XCTAssertEqual(shutdownCallCount, 1)
        await releaseShutdown.open()
        await first.value
        await second.value
        let returnedAfterRelease = await secondReturned.value
        XCTAssertTrue(returnedAfterRelease)
    }
}

private actor SchedulerRuntimeProbe: STTRuntimeProtocol {
    private let delay: Duration?
    private let blocker: SchedulerTestLatch?
    private var activeCount = 0
    private(set) var maximumConcurrency = 0
    private(set) var startedJobs: [STTJobKind] = []

    init(delay: Duration) {
        self.delay = delay
        blocker = nil
    }

    init(blocker: SchedulerTestLatch) {
        delay = nil
        self.blocker = blocker
    }

    func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult {
        activeCount += 1
        maximumConcurrency = max(maximumConcurrency, activeCount)
        startedJobs.append(job)

        do {
            if let blocker {
                await blocker.wait()
            } else if let delay {
                try await Task.sleep(for: delay)
            }
            try Task.checkCancellation()
            activeCount -= 1
            return STTResult(text: audioPath)
        } catch {
            activeCount -= 1
            throw error
        }
    }

    func waitUntilStarted(
        count: Int,
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        let startedAt = ContinuousClock.now
        while startedJobs.count < count {
            if startedAt.duration(to: .now) >= timeout { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    func warmUp(onProgress: (@Sendable (String) -> Void)?) async throws {}
    func backgroundWarmUp() async {}

    func observeWarmUpProgress() async -> (id: UUID, stream: AsyncStream<STTWarmUpState>) {
        let id = UUID()
        return (id, AsyncStream { continuation in
            continuation.yield(.ready)
            continuation.finish()
        })
    }

    func removeWarmUpObserver(id: UUID) async {}
    func isReady() async -> Bool { true }
    func clearModelCache() async {}
    func shutdown() async {}
}

private actor NonCooperativeRuntimeProbe: STTRuntimeProtocol {
    private let started: SchedulerTestLatch
    private let release: SchedulerTestLatch

    init(started: SchedulerTestLatch, release: SchedulerTestLatch) {
        self.started = started
        self.release = release
    }

    func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult {
        await started.open()
        await release.wait()
        return STTResult(text: audioPath)
    }

    func warmUp(onProgress: (@Sendable (String) -> Void)?) async throws {}
    func backgroundWarmUp() async {}

    func observeWarmUpProgress() async -> (id: UUID, stream: AsyncStream<STTWarmUpState>) {
        let id = UUID()
        return (id, AsyncStream { continuation in
            continuation.yield(.ready)
            continuation.finish()
        })
    }

    func removeWarmUpObserver(id: UUID) async {}
    func isReady() async -> Bool { true }
    func clearModelCache() async {}
    func shutdown() async {}
}

private actor CacheClearRuntimeProbe: STTRuntimeProtocol {
    private let started: SchedulerTestLatch
    private let release: SchedulerTestLatch
    private(set) var clearCallCount = 0

    init(started: SchedulerTestLatch, release: SchedulerTestLatch) {
        self.started = started
        self.release = release
    }

    func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult {
        STTResult(text: audioPath)
    }

    func warmUp(onProgress: (@Sendable (String) -> Void)?) async throws {}
    func backgroundWarmUp() async {}

    func observeWarmUpProgress() async -> (id: UUID, stream: AsyncStream<STTWarmUpState>) {
        let id = UUID()
        return (id, AsyncStream { continuation in
            continuation.yield(.ready)
            continuation.finish()
        })
    }

    func removeWarmUpObserver(id: UUID) async {}
    func isReady() async -> Bool { true }

    func clearModelCache() async {
        clearCallCount += 1
        await started.open()
        await release.wait()
    }

    func shutdown() async {}
}

private actor MaintenanceSerializationRuntimeProbe: STTRuntimeProtocol {
    private let clearStarted: SchedulerTestLatch
    private let releaseClear: SchedulerTestLatch
    private var activeMaintenanceCount = 0
    private(set) var maximumMaintenanceConcurrency = 0

    init(clearStarted: SchedulerTestLatch, releaseClear: SchedulerTestLatch) {
        self.clearStarted = clearStarted
        self.releaseClear = releaseClear
    }

    func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult {
        STTResult(text: audioPath)
    }

    func warmUp(onProgress: (@Sendable (String) -> Void)?) async throws {}
    func backgroundWarmUp() async {}

    func observeWarmUpProgress() async -> (id: UUID, stream: AsyncStream<STTWarmUpState>) {
        let id = UUID()
        return (id, AsyncStream { continuation in
            continuation.yield(.ready)
            continuation.finish()
        })
    }

    func removeWarmUpObserver(id: UUID) async {}
    func isReady() async -> Bool { true }

    func clearModelCache() async {
        beginMaintenance()
        await clearStarted.open()
        await releaseClear.wait()
        endMaintenance()
    }

    func shutdown() async {
        beginMaintenance()
        endMaintenance()
    }

    private func beginMaintenance() {
        activeMaintenanceCount += 1
        maximumMaintenanceConcurrency = max(
            maximumMaintenanceConcurrency,
            activeMaintenanceCount
        )
    }

    private func endMaintenance() {
        activeMaintenanceCount -= 1
    }
}

private actor BlockingShutdownRuntimeProbe: STTRuntimeProtocol {
    private let started: SchedulerTestLatch
    private let release: SchedulerTestLatch
    private(set) var shutdownCallCount = 0

    init(started: SchedulerTestLatch, release: SchedulerTestLatch) {
        self.started = started
        self.release = release
    }

    func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult {
        STTResult(text: audioPath)
    }

    func warmUp(onProgress: (@Sendable (String) -> Void)?) async throws {}
    func backgroundWarmUp() async {}

    func observeWarmUpProgress() async -> (id: UUID, stream: AsyncStream<STTWarmUpState>) {
        let id = UUID()
        return (id, AsyncStream { continuation in
            continuation.yield(.ready)
            continuation.finish()
        })
    }

    func removeWarmUpObserver(id: UUID) async {}
    func isReady() async -> Bool { true }
    func clearModelCache() async {}

    func shutdown() async {
        shutdownCallCount += 1
        await started.open()
        await release.wait()
    }
}

private actor AsyncBoolean {
    private(set) var value = false

    func setTrue() {
        value = true
    }
}

private actor SchedulerTestLatch {
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
