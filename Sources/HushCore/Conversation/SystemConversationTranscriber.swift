import AVFoundation
import Foundation

public actor SystemConversationTranscriber: ConversationTranscribing {
    private let stt: any STTTranscribing
    private let fileManager: FileManager
    private var tap: AnyObject?
    private var handoff: ConversationAudioHandoff?
    private var accumulator: ConversationTurnAccumulator?
    private var transcriptionTask: Task<Void, Never>?
    private var pendingSamples: [Float]?
    private var sessionID: UUID?
    private var continuation: AsyncStream<String>.Continuation?
    private var cachedTurns: AsyncStream<String>?

    public init(stt: any STTTranscribing, fileManager: FileManager = .default) {
        self.stt = stt
        self.fileManager = fileManager
    }

    public var finalizedTurns: AsyncStream<String> {
        if let cachedTurns { return cachedTurns }
        var continuation: AsyncStream<String>.Continuation?
        let stream = AsyncStream<String>(bufferingPolicy: .bufferingNewest(16)) {
            continuation = $0
        }
        self.continuation = continuation
        cachedTurns = stream
        return stream
    }

    public func start() throws {
        guard sessionID == nil else { return }
        guard #available(macOS 14.2, *) else {
            throw MeetingAudioError.unsupportedPlatform
        }

        removeStaleSessionFolders()
        let id = UUID()
        let accumulator = ConversationTurnAccumulator { [weak self] samples in
            Task { await self?.enqueue(samples: samples, sessionID: id) }
        }
        let handoff = ConversationAudioHandoff { samples in
            accumulator.ingest(samples)
        }
        let tap = SystemAudioTap()
        try tap.start { buffer, _ in
            handoff.submit(buffer)
        }

        sessionID = id
        self.accumulator = accumulator
        self.handoff = handoff
        self.tap = tap
    }

    public func stop() {
        guard let id = sessionID else { return }
        sessionID = nil
        if #available(macOS 14.2, *), let tap = tap as? SystemAudioTap {
            tap.stop()
        }
        tap = nil
        handoff?.stop()
        handoff = nil
        accumulator?.reset()
        accumulator = nil
        pendingSamples = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        try? fileManager.removeItem(at: sessionFolder(for: id))
    }

    private func enqueue(samples: [Float], sessionID id: UUID) {
        guard sessionID == id else { return }
        guard transcriptionTask == nil else {
            // Keep only the newest complete turn while STT is occupied.
            pendingSamples = samples
            return
        }

        transcriptionTask = Task { [weak self, stt, fileManager] in
            guard let self else { return }
            let folder = await self.sessionFolder(for: id)
            let url = folder.appendingPathComponent("turn-\(UUID().uuidString).wav")
            defer { try? fileManager.removeItem(at: url) }
            do {
                try Task.checkCancellation()
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try Self.writeWAV(samples: samples, to: url)
                let result = try await stt.transcribe(
                    audioPath: url.path,
                    job: .meetingLiveChunk,
                    onProgress: nil
                )
                try Task.checkCancellation()
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { await self.emit(text, sessionID: id) }
            } catch {
                // Cancellation and per-turn STT failures do not keep Conversation from stopping.
            }
            await self.transcriptionFinished(sessionID: id)
        }
    }

    private func transcriptionFinished(sessionID id: UUID) {
        transcriptionTask = nil
        guard sessionID == id, let samples = pendingSamples else { return }
        pendingSamples = nil
        enqueue(samples: samples, sessionID: id)
    }

    private func emit(_ text: String, sessionID id: UUID) {
        guard sessionID == id else { return }
        continuation?.yield(text)
    }

    private func sessionFolder(for id: UUID) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("hush-conversation-\(id.uuidString)", isDirectory: true)
    }

    private func removeStaleSessionFolders() {
        let temporary = fileManager.temporaryDirectory
        guard let urls = try? fileManager.contentsOfDirectory(
            at: temporary,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in urls where url.lastPathComponent.hasPrefix("hush-conversation-") {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func writeWAV(samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw MeetingAudioError.storageFailed("Unable to create conversation audio buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let destination = buffer.floatChannelData?[0], let base = source.baseAddress {
                destination.update(from: base, count: samples.count)
            }
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }
}

private final class ConversationAudioHandoff: @unchecked Sendable {
    private final class CapturedBuffer: @unchecked Sendable {
        let value: AVAudioPCMBuffer
        init(_ value: AVAudioPCMBuffer) { self.value = value }
    }

    private let queue = DispatchQueue(label: "com.hush.conversation.audio", qos: .userInitiated)
    private let capacity = DispatchSemaphore(value: 8)
    private let lock = NSLock()
    private let handler: @Sendable ([Float]) -> Void
    private var accepting = true

    init(handler: @escaping @Sendable ([Float]) -> Void) {
        self.handler = handler
    }

    func submit(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard accepting, capacity.wait(timeout: .now()) == .success else {
            lock.unlock()
            return
        }
        guard let copy = Self.copy(buffer) else {
            capacity.signal()
            lock.unlock()
            return
        }
        let captured = CapturedBuffer(copy)
        queue.async { [capacity, handler] in
            defer { capacity.signal() }
            guard let samples = AudioChunker.extractAndResample(from: captured.value) else { return }
            handler(samples)
        }
        lock.unlock()
    }

    func stop() {
        lock.withLock { accepting = false }
        queue.sync {}
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format: AVAudioFormat
        if buffer.format.isInterleaved {
            guard let value = AVAudioFormat(
                commonFormat: buffer.format.commonFormat,
                sampleRate: buffer.format.sampleRate,
                channels: buffer.format.channelCount,
                interleaved: false
            ) else { return nil }
            format = value
        } else {
            format = buffer.format
        }
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: buffer.frameLength
        ) else { return nil }
        copy.frameLength = buffer.frameLength

        let frames = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        if buffer.format.isInterleaved {
            let sourceBuffer = buffer.audioBufferList.pointee.mBuffers
            guard let sourceData = sourceBuffer.mData else { return nil }
            switch buffer.format.commonFormat {
            case .pcmFormatFloat32:
                guard let destination = copy.floatChannelData else { return nil }
                let source = sourceData.assumingMemoryBound(to: Float.self)
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        destination[channel][frame] = source[(frame * channels) + channel]
                    }
                }
            case .pcmFormatInt16:
                guard let destination = copy.int16ChannelData else { return nil }
                let source = sourceData.assumingMemoryBound(to: Int16.self)
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        destination[channel][frame] = source[(frame * channels) + channel]
                    }
                }
            case .pcmFormatInt32:
                guard let destination = copy.int32ChannelData else { return nil }
                let source = sourceData.assumingMemoryBound(to: Int32.self)
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        destination[channel][frame] = source[(frame * channels) + channel]
                    }
                }
            default:
                return nil
            }
        } else if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int32ChannelData, let destination = copy.int32ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else {
            return nil
        }
        return copy
    }
}
