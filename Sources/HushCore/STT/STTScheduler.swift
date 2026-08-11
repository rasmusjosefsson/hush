import Foundation
import OSLog
import os

public enum STTSchedulerError: Error, LocalizedError, Equatable {
    case droppedDueToBackpressure(job: STTJobKind)
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .droppedDueToBackpressure(let job):
            return "Speech job dropped due to backpressure: \(String(describing: job))"
        case .unavailable:
            return "Speech scheduler is temporarily unavailable"
        }
    }
}

private final class STTJobCancellation: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var isCancelled: Bool {
        state.withLock { $0 }
    }

    func cancel() {
        state.withLock { $0 = true }
    }
}

/// Centralized broker for all STT work in the app process.
///
/// Jobs execute independently per slot so dictation can remain responsive while
/// meeting and file work share an explicitly prioritized background path.
public actor STTScheduler: STTManaging {
    private struct ScheduledJob: Sendable {
        let id: UUID
        let audioPath: String
        let job: STTJobKind
        let enqueueOrder: UInt64
        let onProgress: (@Sendable (Int, Int) -> Void)?
        let cancellation: STTJobCancellation

        var slot: SchedulerSlot {
            SchedulerSlot(job: job)
        }
    }

    private struct SlotState {
        var pendingJobs: [ScheduledJob] = []
        var currentJob: ScheduledJob?
        var currentExecutionTask: Task<STTResult, Error>?
        var currentWaitTask: Task<Void, Never>?
    }

    private struct CacheClearOperation {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct ShutdownOperation {
        let id: UUID
        let task: Task<Void, Never>
    }

    private let logger = Logger(subsystem: "com.hush.core", category: "STTScheduler")
    private let runtime: STTRuntimeProtocol
    private let meetingLiveChunkBacklogLimit: Int

    private var enqueueCounter: UInt64 = 0
    private var continuations: [UUID: CheckedContinuation<STTResult, Error>] = [:]
    private var slotStates: [SchedulerSlot: SlotState] = Dictionary(
        uniqueKeysWithValues: SchedulerSlot.allCases.map { ($0, SlotState()) }
    )
    private var acceptsNewJobs = true
    private var cacheClearOperation: CacheClearOperation?
    private var shutdownOperation: ShutdownOperation?
    private var isPermanentlyShutDown = false

    /// - Parameter meetingLiveChunkBacklogLimit: Maximum pending live-preview chunks before the
    ///   oldest is dropped. 120 ≈ 4 minutes of dual-source 5-second chunks emitted every ~4
    ///   seconds, enough to absorb a prolonged dictation burst before preview starts dropping.
    public init(
        runtime: STTRuntime = STTRuntime(),
        meetingLiveChunkBacklogLimit: Int = 120
    ) {
        self.runtime = runtime as STTRuntimeProtocol
        self.meetingLiveChunkBacklogLimit = max(1, meetingLiveChunkBacklogLimit)
    }

    init(
        runtimeProvider: STTRuntimeProtocol,
        meetingLiveChunkBacklogLimit: Int = 120
    ) {
        self.runtime = runtimeProvider
        self.meetingLiveChunkBacklogLimit = max(1, meetingLiveChunkBacklogLimit)
    }

    public func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> STTResult {
        let id = UUID()
        let cancellation = STTJobCancellation()
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(
                    ScheduledJob(
                        id: id,
                        audioPath: audioPath,
                        job: job,
                        enqueueOrder: nextEnqueueOrder(),
                        onProgress: onProgress,
                        cancellation: cancellation
                    ),
                    continuation: continuation
                )
            }
        } onCancel: {
            cancellation.cancel()
            Task { [weak self] in
                await self?.cancel(jobID: id)
            }
        }
    }

    public func warmUp(onProgress: (@Sendable (String) -> Void)?) async throws {
        guard acceptsNewJobs else { throw STTSchedulerError.unavailable }
        try await runtime.warmUp(onProgress: onProgress)
    }

    public func backgroundWarmUp() async {
        guard acceptsNewJobs else { return }
        await runtime.backgroundWarmUp()
    }

    public func observeWarmUpProgress() async -> (id: UUID, stream: AsyncStream<STTWarmUpState>) {
        await runtime.observeWarmUpProgress()
    }

    public func removeWarmUpObserver(id: UUID) async {
        await runtime.removeWarmUpObserver(id: id)
    }

    public func isReady() async -> Bool {
        await runtime.isReady()
    }

    public func clearModelCache() async {
        guard !isPermanentlyShutDown else { return }
        if let cacheClearOperation {
            await cacheClearOperation.task.value
            return
        }

        acceptsNewJobs = false
        let operationID = UUID()
        let task = Task {
            await self.performCacheClear(operationID: operationID)
        }
        cacheClearOperation = CacheClearOperation(id: operationID, task: task)
        await task.value
    }

    public func shutdown() async {
        if let shutdownOperation {
            await shutdownOperation.task.value
            return
        }
        guard !isPermanentlyShutDown else { return }
        isPermanentlyShutDown = true
        acceptsNewJobs = false

        let operationID = UUID()
        let task = Task {
            await self.performShutdown()
        }
        shutdownOperation = ShutdownOperation(id: operationID, task: task)
        await task.value
        if shutdownOperation?.id == operationID {
            shutdownOperation = nil
        }
    }

    private func enqueue(
        _ job: ScheduledJob,
        continuation: CheckedContinuation<STTResult, Error>
    ) {
        if job.cancellation.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }

        guard acceptsNewJobs else {
            continuation.resume(throwing: STTSchedulerError.unavailable)
            return
        }

        continuations[job.id] = continuation
        var currentSlotState = slotState(for: job.slot)

        if job.job == .meetingLiveChunk,
           pendingMeetingLiveJobCount(in: currentSlotState) >= meetingLiveChunkBacklogLimit,
           let droppedJob = dropOldestPendingMeetingLiveJob(in: &currentSlotState) {
            logger.notice(
                "stt_backpressure drop_pending_meeting_live_chunk id=\(droppedJob.id.uuidString, privacy: .public)"
            )
            let droppedError: Error = droppedJob.cancellation.isCancelled
                ? CancellationError()
                : STTSchedulerError.droppedDueToBackpressure(job: .meetingLiveChunk)
            continuations.removeValue(forKey: droppedJob.id)?.resume(
                throwing: droppedError
            )
        }

        currentSlotState.pendingJobs.append(job)
        setSlotState(currentSlotState, for: job.slot)
        startNextJobIfNeeded(in: job.slot)
    }

    private func nextEnqueueOrder() -> UInt64 {
        defer { enqueueCounter &+= 1 }
        return enqueueCounter
    }

    private func slotState(for slot: SchedulerSlot) -> SlotState {
        slotStates[slot, default: SlotState()]
    }

    private func setSlotState(_ slotState: SlotState, for slot: SchedulerSlot) {
        slotStates[slot] = slotState
    }

    private func pendingMeetingLiveJobCount(in slotState: SlotState) -> Int {
        slotState.pendingJobs.reduce(into: 0) { count, job in
            if job.job == .meetingLiveChunk {
                count += 1
            }
        }
    }

    private func dropOldestPendingMeetingLiveJob(in slotState: inout SlotState) -> ScheduledJob? {
        guard let index = slotState.pendingJobs.enumerated()
            .filter({ $0.element.job == .meetingLiveChunk })
            .min(by: { $0.element.enqueueOrder < $1.element.enqueueOrder })?
            .offset else {
            return nil
        }
        return slotState.pendingJobs.remove(at: index)
    }

    private func startNextJobIfNeeded(in slot: SchedulerSlot) {
        var currentSlotState = slotState(for: slot)
        guard currentSlotState.currentJob == nil else { return }

        while let next = dequeueNextJob(in: &currentSlotState) {
            if next.cancellation.isCancelled {
                continuations.removeValue(forKey: next.id)?.resume(
                    throwing: CancellationError()
                )
                continue
            }

            currentSlotState.currentJob = next
            currentSlotState.currentExecutionTask = Task {
                try await runtime.transcribe(
                    audioPath: next.audioPath,
                    job: next.job,
                    onProgress: next.onProgress
                )
            }
            currentSlotState.currentWaitTask = Task { [weak self] in
                await self?.awaitCurrentJobCompletion(jobID: next.id, in: slot)
            }
            setSlotState(currentSlotState, for: slot)
            return
        }

        setSlotState(currentSlotState, for: slot)
    }

    private func dequeueNextJob(in slotState: inout SlotState) -> ScheduledJob? {
        guard let index = slotState.pendingJobs.indices.min(by: { lhs, rhs in
            let left = slotState.pendingJobs[lhs]
            let right = slotState.pendingJobs[rhs]
            if left.job.priorityRank != right.job.priorityRank {
                return left.job.priorityRank < right.job.priorityRank
            }
            return left.enqueueOrder < right.enqueueOrder
        }) else {
            return nil
        }
        return slotState.pendingJobs.remove(at: index)
    }

    private func awaitCurrentJobCompletion(jobID: UUID, in slot: SchedulerSlot) async {
        let slotState = slotState(for: slot)
        guard slotState.currentJob?.id == jobID, let executionTask = slotState.currentExecutionTask else { return }

        let result: Result<STTResult, Error>
        do {
            result = .success(try await executionTask.value)
        } catch {
            result = .failure(error)
        }

        finishCurrentJob(jobID: jobID, in: slot, result: result)
    }

    private func finishCurrentJob(jobID: UUID, in slot: SchedulerSlot, result: Result<STTResult, Error>) {
        var slotState = slotState(for: slot)
        guard slotState.currentJob?.id == jobID else { return }

        let continuation = continuations.removeValue(forKey: jobID)
        let jobWasCancelled = slotState.currentJob?.cancellation.isCancelled == true
        slotState.currentJob = nil
        slotState.currentExecutionTask = nil
        slotState.currentWaitTask = nil
        setSlotState(slotState, for: slot)

        if jobWasCancelled {
            continuation?.resume(throwing: CancellationError())
        } else {
            switch result {
            case .success(let value):
                continuation?.resume(returning: value)
            case .failure(let error):
                continuation?.resume(throwing: error)
            }
        }

        startNextJobIfNeeded(in: slot)
    }

    private func cancel(jobID: UUID) {
        for slot in SchedulerSlot.allCases {
            var currentSlotState = slotState(for: slot)
            if let index = currentSlotState.pendingJobs.firstIndex(where: { $0.id == jobID }) {
                currentSlotState.pendingJobs.remove(at: index)
                setSlotState(currentSlotState, for: slot)
                continuations.removeValue(forKey: jobID)?.resume(throwing: CancellationError())
                return
            }

            if currentSlotState.currentJob?.id == jobID {
                currentSlotState.currentExecutionTask?.cancel()
                setSlotState(currentSlotState, for: slot)
                return
            }
        }
    }

    private func cancelAllPendingJobs() {
        let pendingIDs = SchedulerSlot.allCases.flatMap { slotState(for: $0).pendingJobs.map(\.id) }
        for slot in SchedulerSlot.allCases {
            var currentSlotState = slotState(for: slot)
            currentSlotState.pendingJobs.removeAll()
            setSlotState(currentSlotState, for: slot)
        }
        for id in pendingIDs {
            continuations.removeValue(forKey: id)?.resume(throwing: CancellationError())
        }
    }

    private func performCacheClear(operationID: UUID) async {
        await quiesce()
        if !isPermanentlyShutDown {
            await runtime.clearModelCache()
        }

        guard cacheClearOperation?.id == operationID else { return }
        cacheClearOperation = nil
        if !isPermanentlyShutDown {
            acceptsNewJobs = true
        }
    }

    private func performShutdown() async {
        await quiesce()
        if let cacheClearOperation {
            await cacheClearOperation.task.value
        }
        await runtime.shutdown()
    }

    private func quiesce() async {
        acceptsNewJobs = false
        cancelAllPendingJobs()
        await cancelAndDrainRunningJobs()
    }

    private func cancelAndDrainRunningJobs() async {
        let waitTasks = SchedulerSlot.allCases.compactMap { slot -> Task<Void, Never>? in
            let slotState = slotState(for: slot)
            slotState.currentJob?.cancellation.cancel()
            slotState.currentExecutionTask?.cancel()
            return slotState.currentWaitTask
        }
        for task in waitTasks {
            await task.value
        }
    }
}

private enum SchedulerSlot: CaseIterable, Sendable {
    case interactive
    case background

    init(job: STTJobKind) {
        switch job {
        case .dictation:
            self = .interactive
        case .meetingFinalize, .meetingLiveChunk, .fileTranscription:
            self = .background
        }
    }
}

private extension STTJobKind {
    // Priority is compared only within a slot. `dictation` and `meetingFinalize`
    // both rank highest, but they never contend because they execute on different slots.
    var priorityRank: Int {
        switch self {
        case .dictation:
            0
        case .meetingFinalize:
            0
        case .meetingLiveChunk:
            1
        case .fileTranscription:
            2
        }
    }
}
