import Darwin
@preconcurrency import Foundation
import HushCore

private enum ChatterboxProcessError: Error, LocalizedError {
    case uvMissing
    case workerStopped
    case invalidResponse
    case timedOut
    case workerFailure(String)

    var errorDescription: String? {
        switch self {
        case .uvMissing: return "The local Chatterbox runtime requires uv. Install it with Homebrew first."
        case .workerStopped: return "The Chatterbox worker stopped unexpectedly."
        case .invalidResponse: return "The Chatterbox worker returned an invalid response."
        case .timedOut: return "The Chatterbox worker did not respond in time."
        case .workerFailure(let message): return "Chatterbox failed: \(message)"
        }
    }
}

actor ChatterboxProcess: ConversationVoiceSynthesizing {
    private let workerURL: URL
    private var process: Process?
    private var input: FileHandle?
    private var reader: BlockingFileReader?
    private var readBuffer = Data()
    private var loadedReferenceWAV: URL?
    private let outputFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("hush-conversation-replies", isDirectory: true)

    init(workerURL: URL) {
        self.workerURL = workerURL
        try? FileManager.default.removeItem(at: outputFolder)
    }

    func start(referenceWAV: URL) async throws {
        let referenceWAV = referenceWAV.standardizedFileURL
        if process?.isRunning == true, loadedReferenceWAV == referenceWAV { return }
        await stop()
        guard let uvURL = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv"]
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ChatterboxProcessError.uvMissing
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = uvURL
        process.arguments = ["run", "--python", "3.11", workerURL.path]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError
        try process.run()

        self.process = process
        input = inputPipe.fileHandleForWriting
        reader = BlockingFileReader(outputPipe.fileHandleForReading)
        readBuffer.removeAll(keepingCapacity: true)

        do {
            try send(["op": "load", "reference_wav": referenceWAV.path])
            let response = try await readResponse(timeoutMilliseconds: 600_000)
            guard response["event"] as? String == "ready" else {
                throw responseError(response)
            }
            loadedReferenceWAV = referenceWAV
        } catch {
            await stop()
            throw error
        }
    }

    func synthesize(text: String) async throws -> URL {
        guard process?.isRunning == true else {
            throw ChatterboxProcessError.workerStopped
        }
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        let id = UUID()
        let outputURL = outputFolder.appendingPathComponent("\(id.uuidString).wav")
        try send([
            "op": "synthesize",
            "id": id.uuidString,
            "text": text,
            "output_wav": outputURL.path,
        ])
        do {
            let response = try await readResponse(timeoutMilliseconds: 120_000)
            guard response["event"] as? String == "completed",
                  response["id"] as? String == id.uuidString,
                  FileManager.default.isReadableFile(atPath: outputURL.path) else {
                throw responseError(response)
            }
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            await stop()
            throw error
        }
    }

    func stop() async {
        let runningProcess = process
        if runningProcess?.isRunning == true {
            try? send(["op": "shutdown"])
        }
        input?.closeFile()
        input = nil
        reader?.close()
        reader = nil
        readBuffer.removeAll()

        if let runningProcess {
            await waitForExit(runningProcess, timeout: .seconds(2))
            if runningProcess.isRunning {
                runningProcess.terminate()
                await waitForExit(runningProcess, timeout: .seconds(1))
            }
        }
        process = nil
        loadedReferenceWAV = nil
        try? FileManager.default.removeItem(at: outputFolder)
    }

    private func send(_ object: [String: Any]) throws {
        guard let input else { throw ChatterboxProcessError.workerStopped }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func readResponse(timeoutMilliseconds: Int32) async throws -> [String: Any] {
        while true {
            if let newline = readBuffer.firstIndex(of: 0x0A) {
                let line = readBuffer[..<newline]
                readBuffer.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw ChatterboxProcessError.invalidResponse
                }
                return object
            }
            guard let reader else { throw ChatterboxProcessError.workerStopped }
            let chunk: Data
            do {
                chunk = try await Task.detached {
                    try reader.read(timeoutMilliseconds: timeoutMilliseconds)
                }.value
            } catch is BlockingFileReader.TimeoutError {
                throw ChatterboxProcessError.timedOut
            }
            guard !chunk.isEmpty else { throw ChatterboxProcessError.workerStopped }
            readBuffer.append(chunk)
        }
    }

    private func waitForExit(_ process: Process, timeout: Duration) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func responseError(_ response: [String: Any]) -> Error {
        if let message = response["message"] as? String {
            return ChatterboxProcessError.workerFailure(message)
        }
        return ChatterboxProcessError.invalidResponse
    }
}

private final class BlockingFileReader: @unchecked Sendable {
    struct TimeoutError: Error {}
    private let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func read(timeoutMilliseconds: Int32) throws -> Data {
        var descriptor = pollfd(
            fd: handle.fileDescriptor,
            events: Int16(POLLIN | POLLHUP),
            revents: 0
        )
        let result = poll(&descriptor, 1, timeoutMilliseconds)
        if result == 0 { throw TimeoutError() }
        if result < 0 { throw POSIXError(.EIO) }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
        if count < 0 { throw POSIXError(.EIO) }
        return Data(bytes.prefix(count))
    }

    func close() {
        try? handle.close()
    }
}
