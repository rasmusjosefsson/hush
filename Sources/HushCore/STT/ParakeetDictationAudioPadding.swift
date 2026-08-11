import AVFAudio
import FluidAudio
import Foundation

/// Prepares short Parakeet dictations with a small real silence tail so the TDT
/// decoder has enough right-side context to emit a word spoken at key release.
///
/// Non-dictation and long inputs return `nil`, which keeps them on FluidAudio's
/// normal URL-backed transcription path. The recorded file is never modified.
enum ParakeetDictationAudioPadding {
    private static let trailingSilenceDuration: TimeInterval = 0.5

    static func samplesIfEligible(
        audioPath: String,
        job: STTJobKind
    ) -> [Float]? {
        guard job == .dictation else { return nil }

        let paddingCount = Int(trailingSilenceDuration * Double(ASRConstants.sampleRate))
        let maximumSourceSamples = ASRConstants.maxModelSamples - paddingCount
        guard maximumSourceSamples > 0,
              var samples = loadSamples(
                audioPath: audioPath,
                maximumOutputSamples: maximumSourceSamples
              ),
              !samples.isEmpty else {
            return nil
        }

        samples.append(contentsOf: repeatElement(0, count: paddingCount))
        return samples
    }

    private static func loadSamples(
        audioPath: String,
        maximumOutputSamples: Int
    ) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: audioPath)) else {
            return nil
        }

        let sourceRate = file.processingFormat.sampleRate
        guard sourceRate > 0, file.length > 0 else { return nil }

        let estimatedOutputCount = Int(
            (Double(file.length) * Double(ASRConstants.sampleRate) / sourceRate).rounded(.up)
        )
        guard estimatedOutputCount <= maximumOutputSamples,
              let frameCount = AVAudioFrameCount(exactly: file.length),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: frameCount
              ) else {
            return nil
        }

        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        return AudioChunker.extractAndResample(from: buffer)
    }
}
