// Tests/HushTests/STT/STTDispatcherTests.swift
import XCTest
import os
@testable import HushCore

final class STTDispatcherTests: XCTestCase {

    func testTranscribeDelegatesToCurrentBackend() async throws {
        let mock = MockSTTClient()
        let expected = STTResult(text: "Hello dispatch")
        await mock.configure(result: expected)

        let registry = ModelRegistry(defaults: .testSuite())
        let dispatcher = STTDispatcher(
            registry: registry,
            backendFactory: { _ in mock }
        )

        let result = try await dispatcher.transcribe(audioPath: "/tmp/test.wav")
        XCTAssertEqual(result.text, "Hello dispatch")
    }

    func testWarmUpDelegatesToCurrentBackend() async throws {
        let mock = MockSTTClient()
        let registry = ModelRegistry(defaults: .testSuite())
        let dispatcher = STTDispatcher(
            registry: registry,
            backendFactory: { _ in mock }
        )

        try await dispatcher.warmUp()
        let called = await mock.warmUpCalled
        XCTAssertTrue(called)
    }

    func testSwitchModelShutsDownPreviousBackend() async throws {
        let mock1 = MockSTTClient()
        let mock2 = MockSTTClient()
        let mocks = [mock1, mock2]
        let callIndex = OSAllocatedUnfairLock(initialState: 0)

        let registry = ModelRegistry(defaults: .testSuite())
        let models = registry.allModels
        guard models.count >= 2 else {
            throw XCTSkip("Need at least 2 models")
        }

        let dispatcher = STTDispatcher(
            registry: registry,
            backendFactory: { _ in
                let index = callIndex.withLock { i -> Int in
                    let current = i
                    i += 1
                    return current
                }
                return mocks[min(index, mocks.count - 1)]
            }
        )

        // Warm up first backend
        try await dispatcher.warmUp()

        // Switch model
        await dispatcher.switchModel(to: models[1].id)

        let shutdown1 = await mock1.shutdownCalled
        XCTAssertTrue(shutdown1, "Previous backend should be shut down")
        XCTAssertEqual(registry.selectedModel.id, models[1].id, "Registry should reflect new selection")
    }

    func testSelectedModelIDReflectsRegistry() async {
        let registry = ModelRegistry(defaults: .testSuite())
        let dispatcher = STTDispatcher(
            registry: registry,
            backendFactory: { _ in MockSTTClient() }
        )
        let selected = await dispatcher.selectedModelID
        XCTAssertEqual(selected, registry.selectedModel.id)
    }

    func testDefaultFactoryUsesScheduledRuntimeForParakeet() {
        let registry = ModelRegistry(defaults: .testSuite())
        let parakeet = registry.allModels.first { $0.engineType == .fluidAudio }

        let backend = parakeet.map(STTDispatcher.defaultFactory())

        XCTAssertTrue(backend is STTScheduler)
    }

    func testOverlappingModelSwitchesKeepNewestSelection() async throws {
        let registry = ModelRegistry(defaults: .testSuite())
        let models = registry.allModels
        guard models.count >= 3 else { throw XCTSkip("Need at least 3 models") }

        let firstShutdownStarted = DispatcherTestLatch()
        let releaseFirstShutdown = DispatcherTestLatch()
        let firstClient = SequencedShutdownSTTClient(
            firstShutdownStarted: firstShutdownStarted,
            releaseFirstShutdown: releaseFirstShutdown
        )
        let secondClient = MockSTTClient()
        let thirdClient = MockSTTClient()
        let clients: [String: any STTClientProtocol] = [
            models[0].id: firstClient,
            models[1].id: secondClient,
            models[2].id: thirdClient,
        ]
        let dispatcher = STTDispatcher(
            registry: registry,
            backendFactory: { clients[$0.id] ?? MockSTTClient() }
        )
        try await dispatcher.warmUp()

        let switchToSecond = Task { await dispatcher.switchModel(to: models[1].id) }
        await firstShutdownStarted.wait()
        let switchToThird = Task { await dispatcher.switchModel(to: models[2].id) }
        await switchToThird.value
        await releaseFirstShutdown.open()
        await switchToSecond.value

        XCTAssertEqual(registry.selectedModel.id, models[2].id)
    }

    func testStaleCacheClearDoesNotDiscardNewBackend() async throws {
        let registry = ModelRegistry(defaults: .testSuite())
        let models = registry.allModels
        guard models.count >= 2 else { throw XCTSkip("Need at least 2 models") }

        let clearStarted = DispatcherTestLatch()
        let releaseClear = DispatcherTestLatch()
        let firstClient = BlockingClearSTTClient(
            clearStarted: clearStarted,
            releaseClear: releaseClear
        )
        let secondClient = MockSTTClient()
        let clients: [String: any STTClientProtocol] = [
            models[0].id: firstClient,
            models[1].id: secondClient,
        ]
        let dispatcher = STTDispatcher(
            registry: registry,
            backendFactory: { clients[$0.id] ?? MockSTTClient() }
        )
        try await dispatcher.warmUp()

        let clearing = Task { await dispatcher.clearModelCache() }
        await clearStarted.wait()
        await dispatcher.switchModel(to: models[1].id)
        try await dispatcher.warmUp()
        await releaseClear.open()
        await clearing.value

        let isReady = await dispatcher.isReady()
        let selectedModelID = await dispatcher.selectedModelID
        XCTAssertTrue(isReady)
        XCTAssertEqual(selectedModelID, models[1].id)
    }
}

private actor SequencedShutdownSTTClient: STTClientProtocol {
    private let firstShutdownStarted: DispatcherTestLatch
    private let releaseFirstShutdown: DispatcherTestLatch
    private var shutdownCallCount = 0

    init(
        firstShutdownStarted: DispatcherTestLatch,
        releaseFirstShutdown: DispatcherTestLatch
    ) {
        self.firstShutdownStarted = firstShutdownStarted
        self.releaseFirstShutdown = releaseFirstShutdown
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
        return (id, AsyncStream { $0.finish() })
    }
    func removeWarmUpObserver(id: UUID) async {}
    func isReady() async -> Bool { true }
    func clearModelCache() async {}

    func shutdown() async {
        shutdownCallCount += 1
        guard shutdownCallCount == 1 else { return }
        await firstShutdownStarted.open()
        await releaseFirstShutdown.wait()
    }
}

private actor BlockingClearSTTClient: STTClientProtocol {
    private let clearStarted: DispatcherTestLatch
    private let releaseClear: DispatcherTestLatch

    init(clearStarted: DispatcherTestLatch, releaseClear: DispatcherTestLatch) {
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
        return (id, AsyncStream { $0.finish() })
    }
    func removeWarmUpObserver(id: UUID) async {}
    func isReady() async -> Bool { true }

    func clearModelCache() async {
        await clearStarted.open()
        await releaseClear.wait()
    }

    func shutdown() async {}
}

private actor DispatcherTestLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private extension UserDefaults {
    static func testSuite() -> UserDefaults {
        let suiteName = "com.hush.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
