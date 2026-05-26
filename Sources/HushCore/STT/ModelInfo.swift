// Sources/HushCore/STT/ModelInfo.swift
import Foundation

public struct ModelInfo: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let engineType: EngineType
    public let sizeMB: Int
    public let supportedLanguages: [String]  // ISO 639-1 codes, empty = all
    public let isDefault: Bool

    /// Backend-specific variant string (e.g. WhisperKit model folder name).
    /// When nil, the backend derives the variant from the model ID.
    public let variant: String?

    /// Human-readable description shown in UI (e.g. "Fast, English only")
    public let summary: String

    public init(
        id: String,
        name: String,
        engineType: EngineType,
        sizeMB: Int,
        supportedLanguages: [String] = [],
        isDefault: Bool = false,
        variant: String? = nil,
        summary: String = ""
    ) {
        self.id = id
        self.name = name
        self.engineType = engineType
        self.sizeMB = sizeMB
        self.supportedLanguages = supportedLanguages
        self.isDefault = isDefault
        self.variant = variant
        self.summary = summary
    }
}
