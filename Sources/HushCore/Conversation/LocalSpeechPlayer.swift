@preconcurrency import Foundation

public actor LocalSpeechPlayer: ConversationSpeechPlaying {
    private var process: Process?

    public init() {}

    public func play(fileURL: URL) async throws {
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [fileURL.path]
        try process.run()
        self.process = process

        await Task.detached { process.waitUntilExit() }.value
        guard self.process === process else { return }
        self.process = nil
        guard process.terminationStatus == 0 else {
            throw VirtualMicOutputError.playbackFailed("afplay exited with status \(process.terminationStatus).")
        }
    }

    public func stop() {
        process?.terminate()
        process = nil
    }
}
