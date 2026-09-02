import FluidAudio

/// Centralizes FluidAudio manager policy so every Parakeet entry point uses the
/// same safety posture.
enum ParakeetRuntimeConfiguration {
    static var managerConfigForCurrentOS: ASRConfig {
        managerConfig(
            serializesTopLevelInference: NeuralEngineInferenceGate.serializationRequiredForCurrentOS
        )
    }

    static func managerConfig(
        serializesTopLevelInference: Bool
    ) -> ASRConfig {
        guard serializesTopLevelInference else { return .default }

        // FluidAudio otherwise creates several long-form chunk workers that
        // share the loaded Core ML models. Keep one worker on Sonoma in addition
        // to serializing separate Hush operations at the process boundary.
        return ASRConfig(parallelChunkConcurrency: 1)
    }
}
