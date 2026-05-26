import ArgumentParser
import XCTest
@testable import HushCore
@testable import CLI

final class ModelLifecycleCommandTests: XCTestCase {
    func testValidatedAttemptsRejectsZero() {
        XCTAssertThrowsError(try validatedAttempts(0)) { error in
            XCTAssertTrue(error is ValidationError)
        }
    }

    func testValidatedAttemptsAcceptsPositiveValues() throws {
        XCTAssertEqual(try validatedAttempts(1), 1)
        XCTAssertEqual(try validatedAttempts(5), 5)
    }

    func testWarmUpRetriesConfiguredAttempts() async {
        let stt = StubSTTClient()
        await stt.setFailuresBeforeSuccess(2)

        do {
            try await warmUpModels(
                attempts: 3,
                sttClient: stt,
                log: { _ in }
            )
        } catch {
            XCTFail("Expected warm-up to succeed after retries, got \(error)")
        }

        let sttCalls = await stt.warmUpCalls
        XCTAssertEqual(sttCalls, 3)
    }
}

private actor StubSTTClient: STTClientProtocol {
    private(set) var warmUpCalls = 0
    private var alwaysFail = false
    private var failuresBeforeSuccess = 0
    private var ready = false
    private var warmUpObservers: [UUID: AsyncStream<STTWarmUpState>.Continuation] = [:]

    func setAlwaysFail(_ value: Bool) {
        alwaysFail = value
    }

    func setFailuresBeforeSuccess(_ count: Int) {
        failuresBeforeSuccess = max(0, count)
    }

    // STTTranscribing
    func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult {
        STTResult(text: "", words: [])
    }

    // STTRuntimeManaging
    func warmUp(onProgress: (@Sendable (String) -> Void)?) async throws {
        warmUpCalls += 1
        if alwaysFail {
            throw STTError.engineStartFailed("forced failure")
        }
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw STTError.engineStartFailed("transient failure")
        }
        ready = true
    }

    func backgroundWarmUp() async {
        try? await warmUp(onProgress: nil)
    }

    func observeWarmUpProgress() async -> (id: UUID, stream: AsyncStream<STTWarmUpState>) {
        let id = UUID()
        let stream = AsyncStream<STTWarmUpState> { continuation in
            warmUpObservers[id] = continuation
            continuation.yield(ready ? .ready : .idle)
        }
        return (id, stream)
    }

    func removeWarmUpObserver(id: UUID) async {
        warmUpObservers[id]?.finish()
        warmUpObservers[id] = nil
    }

    func isReady() async -> Bool {
        ready
    }

    func clearModelCache() async {
        ready = false
    }

    func shutdown() async {}
}
