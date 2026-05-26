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
}

private extension UserDefaults {
    static func testSuite() -> UserDefaults {
        let suiteName = "com.hush.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
