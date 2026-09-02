import AVFoundation
import CoreAudio
import Foundation

public enum VirtualMicOutputError: Error, LocalizedError, Equatable, Sendable {
    case deviceNotFound(String)
    case deviceUnavailable(String)
    case noDeviceSelected
    case audioFileNotFound(String)
    case playbackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound(let uid):
            return "Audio output device not found: \(uid)."
        case .deviceUnavailable(let uid):
            return "Audio output device is unavailable: \(uid)."
        case .noDeviceSelected:
            return "No virtual microphone output device is selected."
        case .audioFileNotFound(let path):
            return "Audio file not found: \(path)."
        case .playbackFailed(let reason):
            return "Virtual microphone playback failed: \(reason)"
        }
    }
}

protocol VirtualMicPlayback: Sendable {
    func prepare(deviceID: AudioDeviceID) throws
    func play(fileURL: URL, completion: @escaping @Sendable () -> Void) throws
    func stop()
}

/// Routes a local audio file to one explicitly selected Core Audio output device.
/// It never changes the system default output device.
public actor VirtualMicOutput {
    typealias DeviceResolver = @Sendable (String) -> AudioDeviceID?

    private let resolveDevice: DeviceResolver
    private let playback: any VirtualMicPlayback
    private var playbackGeneration = UUID()

    public private(set) var selectedDeviceUID: String?
    public private(set) var isPlaying = false

    public init() {
        self.resolveDevice = { AudioDeviceManager.outputDevice(uid: $0)?.id }
        self.playback = EngineVirtualMicPlayback()
    }

    init(
        resolveDevice: @escaping DeviceResolver,
        playback: any VirtualMicPlayback
    ) {
        self.resolveDevice = resolveDevice
        self.playback = playback
    }

    public func selectDevice(uid: String) throws {
        guard let deviceID = resolveDevice(uid) else {
            throw VirtualMicOutputError.deviceNotFound(uid)
        }
        do {
            try playback.prepare(deviceID: deviceID)
        } catch {
            selectedDeviceUID = nil
            isPlaying = false
            playbackGeneration = UUID()
            throw VirtualMicOutputError.deviceUnavailable(uid)
        }
        selectedDeviceUID = uid
        isPlaying = false
        playbackGeneration = UUID()
    }

    public func play(fileURL: URL) throws {
        guard selectedDeviceUID != nil else {
            throw VirtualMicOutputError.noDeviceSelected
        }
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw VirtualMicOutputError.audioFileNotFound(fileURL.path)
        }

        let generation = UUID()
        playbackGeneration = generation
        if isPlaying {
            playback.stop()
            isPlaying = false
        }
        do {
            try playback.play(fileURL: fileURL) { [weak self] in
                Task { await self?.playbackFinished(generation: generation) }
            }
            isPlaying = true
        } catch {
            playback.stop()
            isPlaying = false
            throw VirtualMicOutputError.playbackFailed(error.localizedDescription)
        }
    }

    public func stop() {
        playbackGeneration = UUID()
        playback.stop()
        isPlaying = false
    }

    private func playbackFinished(generation: UUID) {
        guard playbackGeneration == generation else { return }
        playbackGeneration = UUID()
        playback.stop()
        isPlaying = false
    }
}

private final class EngineVirtualMicPlayback: VirtualMicPlayback, @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    func prepare(deviceID: AudioDeviceID) throws {
        stop()

        let engine = AVAudioEngine()
        _ = engine.outputNode
        guard AudioDeviceManager.setOutputDevice(deviceID, on: engine) else {
            throw VirtualMicOutputError.deviceUnavailable(String(deviceID))
        }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        self.engine = engine
        self.player = player
    }

    func play(fileURL: URL, completion: @escaping @Sendable () -> Void) throws {
        guard let engine, let player else {
            throw VirtualMicOutputError.noDeviceSelected
        }

        let file = try AVAudioFile(forReading: fileURL)
        player.stop()
        engine.stop()
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { _ in
            completion()
        }

        engine.prepare()
        do {
            try engine.start()
            player.play()
        } catch {
            player.stop()
            engine.stop()
            throw error
        }
    }

    func stop() {
        player?.stop()
        engine?.stop()
    }
}
