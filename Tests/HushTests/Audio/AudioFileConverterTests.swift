import XCTest
@testable import HushCore

final class AudioFileConverterTests: XCTestCase {

    func testSupportedAudioExtensions() {
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "mp3"))
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "wav"))
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "m4a"))
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "flac"))
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "ogg"))
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "opus"))
    }

    func testSupportedVideoExtensions() {
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "mp4"))
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "mov"))
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "mkv"))
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "webm"))
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "avi"))
    }

    func testUnsupportedExtensions() {
        XCTAssertFalse(AudioFileConverter.isSupported(extension: "txt"))
        XCTAssertFalse(AudioFileConverter.isSupported(extension: "pdf"))
        XCTAssertFalse(AudioFileConverter.isSupported(extension: "doc"))
        XCTAssertFalse(AudioFileConverter.isSupported(extension: "jpg"))
    }

    func testCaseInsensitiveExtension() {
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "MP3"))
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "WAV"))
        XCTAssertTrue(AudioFileConverter.isSupported(extension: "Mp4"))
    }

    func testConvertUnsupportedFormat() async {
        let converter = AudioFileConverter()
        let url = URL(fileURLWithPath: "/tmp/test.txt")

        do {
            _ = try await converter.convert(fileURL: url)
            XCTFail("Should have thrown for unsupported format")
        } catch let error as AudioProcessorError {
            if case .unsupportedFormat(let ext) = error {
                XCTAssertEqual(ext, "txt")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testAudioProcessorErrorDescriptions() {
        XCTAssertNotNil(AudioProcessorError.microphonePermissionDenied.errorDescription)
        XCTAssertNotNil(AudioProcessorError.microphoneNotAvailable.errorDescription)
        XCTAssertNotNil(AudioProcessorError.recordingFailed("test").errorDescription)
        XCTAssertNotNil(AudioProcessorError.conversionFailed("test").errorDescription)
        XCTAssertNotNil(AudioProcessorError.unsupportedFormat("xyz").errorDescription)
        XCTAssertNotNil(AudioProcessorError.fileTooLarge("test").errorDescription)
        XCTAssertNotNil(AudioProcessorError.insufficientSamples.errorDescription)
    }
}
