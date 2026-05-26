public actor RecordingHealthWatchdog {
    private let healthCheckInterval: Duration
    private let onStall: @Sendable () async -> Void
    private var monitorTask: Task<Void, Never>?
    private var lastHeartbeat: ContinuousClock.Instant?

    public init(
        healthCheckInterval: Duration = .seconds(10),
        onStall: @escaping @Sendable () async -> Void
    ) {
        self.healthCheckInterval = healthCheckInterval
        self.onStall = onStall
    }

    /// Call each time an audio buffer is successfully written.
    public func heartbeat() {
        lastHeartbeat = .now
    }

    /// Start monitoring. Call when recording begins.
    public func start() {
        lastHeartbeat = .now
        monitorTask = Task { [healthCheckInterval, onStall] in
            while !Task.isCancelled {
                try? await Task.sleep(for: healthCheckInterval)
                guard !Task.isCancelled else { break }
                if let last = self.lastHeartbeat,
                   ContinuousClock.now - last >= healthCheckInterval {
                    await onStall()
                    self.monitorTask = nil
                    return
                }
            }
        }
    }

    /// Stop monitoring. Call when recording ends.
    public func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }
}
