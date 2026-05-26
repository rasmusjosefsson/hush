// Sources/HushCore/STT/ModelRegistry.swift
import Foundation

/// Thread-safe model catalog and selection persistence.
/// Uses @unchecked Sendable because UserDefaults is internally thread-safe
/// but not declared Sendable by the SDK.
public final class ModelRegistry: @unchecked Sendable {
    private static let selectedModelKey = "selectedSpeechModelID"

    private let _allModels: [ModelInfo]
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self._allModels = Self.builtInModels()
    }

    public var allModels: [ModelInfo] { _allModels }

    public var selectedModel: ModelInfo {
        if let savedID = defaults.string(forKey: Self.selectedModelKey),
           let model = _allModels.first(where: { $0.id == savedID }) {
            return model
        }
        return _allModels.first(where: { $0.isDefault })
            ?? _allModels[0]
    }

    public func selectModel(id: String) {
        guard _allModels.contains(where: { $0.id == id }) else { return }
        defaults.set(id, forKey: Self.selectedModelKey)
    }

    public func models(for engine: EngineType) -> [ModelInfo] {
        _allModels.filter { $0.engineType == engine }
    }

    public func model(for id: String) -> ModelInfo? {
        _allModels.first { $0.id == id }
    }

    // MARK: - Built-in model catalog

    private static func builtInModels() -> [ModelInfo] {
        [
            // FluidAudio / Parakeet
            ModelInfo(
                id: "parakeet-tdt-0.6b-v3",
                name: "Parakeet V3",
                engineType: .fluidAudio,
                sizeMB: 6_000,
                supportedLanguages: [],  // 25 EU languages
                isDefault: true,
                summary: "Best accuracy. 25 languages. ~6 GB download."
            ),

            // WhisperKit models (sizes are approximate CoreML weights)
            ModelInfo(
                id: "whisper-large-v3-turbo",
                name: "Whisper Turbo",
                engineType: .whisperKit,
                sizeMB: 1_600,
                supportedLanguages: [],  // 99+ languages
                variant: "openai_whisper-large-v3_turbo",
                summary: "Fast, multilingual. ~1.6 GB download."
            ),
            ModelInfo(
                id: "whisper-large-v3",
                name: "Whisper Large V3",
                engineType: .whisperKit,
                sizeMB: 3_100,
                supportedLanguages: [],
                variant: "openai_whisper-large-v3",
                summary: "Highest Whisper accuracy. ~3.1 GB download."
            ),
            ModelInfo(
                id: "whisper-small",
                name: "Whisper Small",
                engineType: .whisperKit,
                sizeMB: 500,
                supportedLanguages: [],
                variant: "openai_whisper-small",
                summary: "Lightweight, multilingual. ~500 MB download."
            ),
        ]
    }
}
