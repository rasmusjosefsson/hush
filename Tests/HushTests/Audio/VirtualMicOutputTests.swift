import CoreAudio
import Foundation
@testable import HushCore
import XCTest

final class VirtualMicOutputTests: XCTestCase {
    func testSelectsDeviceByStableUID() async throws {
        let playback = FakeVirtualMicPlayback()
        let output = VirtualMicOutput(
            resolveDevice: { $0 == "virtual.uid" ? 42 : nil },
            playback: playback
        )

        try await output.selectDevice(uid: "virtual.uid")

        let selectedDeviceUID = await output.selectedDeviceUID
        XCTAssertEqual(selectedDeviceUID, "virtual.uid")
        XCTAssertEqual(playback.preparedDeviceIDs, [42])
    }

    func testRejectsUnknownDeviceUID() async {
        let output = VirtualMicOutput(
            resolveDevice: { _ in nil },
            playback: FakeVirtualMicPlayback()
        )

        do {
            try await output.selectDevice(uid: "missing.uid")
            XCTFail("Expected selection to fail")
        } catch {
            XCTAssertEqual(error as? VirtualMicOutputError, .deviceNotFound("missing.uid"))
        }
    }

    func testPlayAndStopUpdateStateWithoutAudioHardware() async throws {
        let playback = FakeVirtualMicPlayback()
        let output = VirtualMicOutput(resolveDevice: { _ in 7 }, playback: playback)
        let fileURL = try makeReadableTemporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try await output.selectDevice(uid: "virtual.uid")
        try await output.play(fileURL: fileURL)

        let isPlayingBeforeStop = await output.isPlaying
        XCTAssertTrue(isPlayingBeforeStop)
        XCTAssertEqual(playback.playedFileURLs, [fileURL])

        await output.stop()

        let isPlayingAfterStop = await output.isPlaying
        XCTAssertFalse(isPlayingAfterStop)
        XCTAssertEqual(playback.stopCount, 1)
    }

    func testPlaybackCompletionStopsBackendAndClearsPlayingState() async throws {
        let playback = FakeVirtualMicPlayback()
        let output = VirtualMicOutput(resolveDevice: { _ in 7 }, playback: playback)
        let fileURL = try makeReadableTemporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let stopped = expectation(description: "Playback backend stopped")
        playback.onStop = { stopped.fulfill() }

        try await output.selectDevice(uid: "virtual.uid")
        try await output.play(fileURL: fileURL)
        playback.finishPlayback()

        await fulfillment(of: [stopped], timeout: 1)
        let isPlaying = await output.isPlaying
        XCTAssertFalse(isPlaying)
        XCTAssertEqual(playback.stopCount, 1)
    }

    func testFailedReplacementStopsExistingPlaybackAndClearsState() async throws {
        let playback = FakeVirtualMicPlayback()
        let output = VirtualMicOutput(resolveDevice: { _ in 7 }, playback: playback)
        let firstURL = try makeReadableTemporaryFile()
        let replacementURL = try makeReadableTemporaryFile()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: replacementURL)
        }

        try await output.selectDevice(uid: "virtual.uid")
        try await output.play(fileURL: firstURL)
        playback.failNextPlay()

        do {
            try await output.play(fileURL: replacementURL)
            XCTFail("Expected replacement playback to fail")
        } catch {
            XCTAssertEqual(
                error as? VirtualMicOutputError,
                .playbackFailed(FakeVirtualMicPlayback.failure.localizedDescription)
            )
        }

        let isPlaying = await output.isPlaying
        XCTAssertFalse(isPlaying)
        XCTAssertGreaterThanOrEqual(playback.stopCount, 1)
    }

    func testPlayRequiresSelection() async throws {
        let output = VirtualMicOutput(
            resolveDevice: { _ in 7 },
            playback: FakeVirtualMicPlayback()
        )
        let fileURL = try makeReadableTemporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            try await output.play(fileURL: fileURL)
            XCTFail("Expected playback to fail")
        } catch {
            XCTAssertEqual(error as? VirtualMicOutputError, .noDeviceSelected)
        }
    }

    func testInvalidPIDFailsBeforeCoreAudioLookup() {
        XCTAssertThrowsError(try AudioObjectID.readProcessObjectID(for: 0)) { error in
            XCTAssertEqual(error as? CoreAudioProcessLookupError, .invalidPID(0))
        }
    }

    private func makeReadableTemporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("virtual-mic-test-\(UUID().uuidString).wav")
        try Data([0]).write(to: url)
        return url
    }
}

private final class FakeVirtualMicPlayback: VirtualMicPlayback, @unchecked Sendable {
    static let failure = NSError(domain: "FakeVirtualMicPlayback", code: 1)

    private let lock = NSLock()
    private var _preparedDeviceIDs: [AudioDeviceID] = []
    private var _playedFileURLs: [URL] = []
    private var _stopCount = 0
    private var _failNextPlay = false
    private var completion: (@Sendable () -> Void)?
    var onStop: (@Sendable () -> Void)?

    var preparedDeviceIDs: [AudioDeviceID] {
        lock.withLock { _preparedDeviceIDs }
    }

    var playedFileURLs: [URL] {
        lock.withLock { _playedFileURLs }
    }

    var stopCount: Int {
        lock.withLock { _stopCount }
    }

    func prepare(deviceID: AudioDeviceID) {
        lock.withLock { _preparedDeviceIDs.append(deviceID) }
    }

    func play(fileURL: URL, completion: @escaping @Sendable () -> Void) throws {
        let shouldFail = lock.withLock {
            let value = _failNextPlay
            _failNextPlay = false
            if !value {
                _playedFileURLs.append(fileURL)
                self.completion = completion
            }
            return value
        }
        if shouldFail { throw Self.failure }
    }

    func stop() {
        let callback = lock.withLock {
            _stopCount += 1
            return onStop
        }
        callback?()
    }

    func finishPlayback() {
        lock.withLock { completion }?()
    }

    func failNextPlay() {
        lock.withLock { _failNextPlay = true }
    }
}
