import Testing
import Foundation
@testable import HushCore

private final class StallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        _count += 1
        lock.unlock()
    }
}

@Suite("RecordingHealthWatchdog")
struct RecordingHealthWatchdogTests {

    @Test func heartbeatPreventsStall() async throws {
        let counter = StallCounter()
        let watchdog = RecordingHealthWatchdog(healthCheckInterval: .milliseconds(200)) {
            counter.increment()
        }
        await watchdog.start()
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(100))
            await watchdog.heartbeat()
        }
        await watchdog.stop()
        #expect(counter.count == 0)
    }

    @Test func noHeartbeatTriggersStall() async throws {
        let counter = StallCounter()
        let watchdog = RecordingHealthWatchdog(healthCheckInterval: .milliseconds(200)) {
            counter.increment()
        }
        await watchdog.start()
        try await Task.sleep(for: .milliseconds(500))
        #expect(counter.count == 1)
    }

    @Test func stopCancelsMonitoring() async throws {
        let counter = StallCounter()
        let watchdog = RecordingHealthWatchdog(healthCheckInterval: .milliseconds(200)) {
            counter.increment()
        }
        await watchdog.start()
        await watchdog.stop()
        try await Task.sleep(for: .milliseconds(500))
        #expect(counter.count == 0)
    }

    @Test func stallFiresOnlyOnce() async throws {
        let counter = StallCounter()
        let watchdog = RecordingHealthWatchdog(healthCheckInterval: .milliseconds(200)) {
            counter.increment()
        }
        await watchdog.start()
        try await Task.sleep(for: .milliseconds(500))
        try await Task.sleep(for: .milliseconds(500))
        #expect(counter.count == 1)
    }
}
