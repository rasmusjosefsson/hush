// Sources/HushCore/STT/EngineType.swift
import Foundation

public enum EngineType: String, Codable, Sendable, CaseIterable {
    case fluidAudio   // Parakeet via FluidAudio CoreML/ANE
    case whisperKit   // Whisper models via WhisperKit CoreML/ANE
}
