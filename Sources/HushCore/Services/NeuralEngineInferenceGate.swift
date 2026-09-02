import Foundation

/// Serializes Hush-managed Core ML inference pipelines on macOS versions where
/// separate top-level submissions can crash inside the system runtime.
///
/// The gate is process-wide and cancellation-aware on macOS 14. It is a direct
/// pass-through on macOS 15 and newer so supported systems keep concurrent STT
/// lanes. Third-party pipelines can retain internal concurrency; Hush separately
/// restricts FluidAudio's long-form ASR workers on affected systems. Callers
/// must not nest acquisitions.
public final class NeuralEngineInferenceGate: Sendable {
    public static let shared = NeuralEngineInferenceGate()

    public static var serializationRequiredForCurrentOS: Bool {
        if #available(macOS 15, *) {
            return false
        }
        return true
    }

    private let mutex: AsyncMutex?

    public convenience init() {
        self.init(serializesAccess: Self.serializationRequiredForCurrentOS)
    }

    init(serializesAccess: Bool) {
        mutex = serializesAccess ? AsyncMutex() : nil
    }

    public func withExclusiveAccess<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        guard let mutex else {
            return try await operation()
        }

        try await mutex.acquire()
        do {
            try Task.checkCancellation()
            let value = try await operation()
            await mutex.release()
            return value
        } catch {
            await mutex.release()
            throw error
        }
    }

    var pendingWaiterCount: Int {
        get async {
            guard let mutex else { return 0 }
            return await mutex.pendingWaiterCount
        }
    }
}

private actor AsyncMutex {
    private var isLocked = false
    private var waiterOrder: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    func acquire() async throws {
        try Task.checkCancellation()
        guard isLocked else {
            isLocked = true
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiterOrder.append(id)
                waiters[id] = continuation
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    var pendingWaiterCount: Int {
        waiters.count
    }

    func release() {
        while !waiterOrder.isEmpty {
            let id = waiterOrder.removeFirst()
            guard let continuation = waiters.removeValue(forKey: id) else {
                continue
            }
            continuation.resume()
            return
        }
        isLocked = false
    }

    private func cancelWaiter(id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
    }
}
