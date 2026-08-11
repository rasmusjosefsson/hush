import AVFAudio
import FluidAudio
import XCTest
@testable import HushCore

final class ParakeetDictationAudioPaddingTests: XCTestCase {
    func testShortDictationAppendsHalfSecondOfSilence() throws {
        let sourceSamples: [Float] = [0.25, -0.5, 0.75, -1.0]
        let url = try writeWAV(samples: sourceSamples)
        defer { try? FileManager.default.removeItem(at: url) }

        let prepared = ParakeetDictationAudioPadding.samplesIfEligible(
            audioPath: url.path,
            job: .dictation
        )

        let paddingCount = Int(0.5 * Double(ASRConstants.sampleRate))
        XCTAssertEqual(prepared?.count, sourceSamples.count + paddingCount)
        XCTAssertEqual(Array(prepared?.prefix(sourceSamples.count) ?? []), sourceSamples)
        XCTAssertTrue(prepared?.suffix(paddingCount).allSatisfy { $0 == 0 } == true)
    }

    func testOnlyDictationJobsReceivePadding() throws {
        let url = try writeWAV(samples: [Float](repeating: 0.25, count: 4_800))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(ParakeetDictationAudioPadding.samplesIfEligible(audioPath: url.path, job: .fileTranscription))
        XCTAssertNil(ParakeetDictationAudioPadding.samplesIfEligible(audioPath: url.path, job: .meetingFinalize))
        XCTAssertNil(ParakeetDictationAudioPadding.samplesIfEligible(audioPath: url.path, job: .meetingLiveChunk))
    }

    func testMissingAudioFallsBackToFileTranscriptionPath() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).wav")

        XCTAssertNil(
            ParakeetDictationAudioPadding.samplesIfEligible(
                audioPath: missingURL.path,
                job: .dictation
            )
        )
    }

    func testDictationThatWouldCrossSingleWindowLimitFallsBack() throws {
        let paddingCount = Int(0.5 * Double(ASRConstants.sampleRate))
        let sourceCount = ASRConstants.maxModelSamples - paddingCount + 1
        let url = try writeWAV(samples: [Float](repeating: 0.1, count: sourceCount))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(
            ParakeetDictationAudioPadding.samplesIfEligible(
                audioPath: url.path,
                job: .dictation
            )
        )
    }

    private func writeWAV(samples: [Float]) throws -> URL {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(ASRConstants.sampleRate),
            channels: 1,
            interleaved: false
        )!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-padding-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        )!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData?[0].update(from: source.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
        return url
    }
}
