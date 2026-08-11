// Sources/HushCore/STT/STTDispatcher.swift
import Foundation

/// Routes STT calls to the correct backend based on the selected model's engine type.
public actor STTDispatcher: STTClientProtocol {
    public typealias BackendFactory = @Sendable (ModelInfo) -> any STTClientProtocol

    private let registry: ModelRegistry
    private let backendFactory: BackendFactory
    private var currentBackend: (any STTClientProtocol)?
    private var currentModelID: String?
    private var backendGeneration: UInt64 = 0

    public init(
        registry: ModelRegistry,
        backendFactory: @escaping BackendFactory
    ) {
        self.registry = registry
        self.backendFactory = backendFactory
    }

    /// Default factory that creates real backends based on engine type.
    public static func defaultFactory() -> BackendFactory {
        { model in
            switch model.engineType {
            case .fluidAudio:
                return STTScheduler()
            case .whisperKit:
                let variant = model.variant ?? String(model.id.dropFirst("whisper-".count))
                return WhisperKitClient(modelVariant: variant)
            }
        }
    }

    public var selectedModelID: String {
        registry.selectedModel.id
    }

    public func switchModel(to modelID: String) async {
        guard registry.model(for: modelID) != nil else { return }
        guard modelID != currentModelID || registry.selectedModel.id != modelID else { return }

        let staleBackend = currentBackend
        currentBackend = nil
        currentModelID = nil
        backendGeneration &+= 1
        registry.selectModel(id: modelID)
        await staleBackend?.shutdown()
    }

    public func transcribe(audioPath: String, job: STTJobKind = .dictation, onProgress: (@Sendable (Int, Int) -> Void)?) async throws -> STTResult {
        let backend = try await ensureBackend()
        return try await backend.transcribe(audioPath: audioPath, job: job, onProgress: onProgress)
    }

    public func warmUp(onProgress: (@Sendable (String) -> Void)?) async throws {
        let backend = try await ensureBackend()
        try await backend.warmUp(onProgress: onProgress)
    }

    public func isReady() async -> Bool {
        guard let backend = currentBackend else { return false }
        return await backend.isReady()
    }

    public func clearModelCache() async {
        guard let backend = currentBackend else { return }
        let generation = backendGeneration
        await backend.clearModelCache()

        guard generation == backendGeneration else { return }
        currentBackend = nil
        currentModelID = nil
        backendGeneration &+= 1
    }

    public func backgroundWarmUp() async {
        let backend = try? await ensureBackend()
        await backend?.backgroundWarmUp()
    }

    public func observeWarmUpProgress() async -> (id: UUID, stream: AsyncStream<STTWarmUpState>) {
        guard let backend = currentBackend else {
            let id = UUID()
            return (id, AsyncStream { $0.finish() })
        }
        return await backend.observeWarmUpProgress()
    }

    public func removeWarmUpObserver(id: UUID) async {
        await currentBackend?.removeWarmUpObserver(id: id)
    }

    public func shutdown() async {
        guard let backend = currentBackend else { return }
        let generation = backendGeneration
        await backend.shutdown()

        guard generation == backendGeneration else { return }
        currentBackend = nil
        currentModelID = nil
        backendGeneration &+= 1
    }

    // MARK: - Private

    private func ensureBackend() async throws -> any STTClientProtocol {
        while true {
            let requestedModel = registry.selectedModel
            if let backend = currentBackend,
               currentModelID == requestedModel.id {
                return backend
            }

            if let staleBackend = currentBackend {
                currentBackend = nil
                currentModelID = nil
                backendGeneration &+= 1
                await staleBackend.shutdown()
                continue
            }

            let latestModel = registry.selectedModel
            guard latestModel.id == requestedModel.id else { continue }

            let backend = backendFactory(latestModel)
            currentBackend = backend
            currentModelID = latestModel.id
            backendGeneration &+= 1
            return backend
        }
    }
}
