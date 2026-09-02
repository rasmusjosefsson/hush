import FluidAudio
import XCTest
@testable import HushCore

final class ParakeetRuntimeConfigurationTests: XCTestCase {
    func testSonomaConfigurationUsesOneChunkWorker() {
        let config = ParakeetRuntimeConfiguration.managerConfig(
            serializesTopLevelInference: true
        )

        XCTAssertEqual(config.parallelChunkConcurrency, 1)
    }

    func testNewerOSConfigurationPreservesFluidAudioDefaultConcurrency() {
        let config = ParakeetRuntimeConfiguration.managerConfig(
            serializesTopLevelInference: false
        )

        XCTAssertEqual(
            config.parallelChunkConcurrency,
            ASRConfig.default.parallelChunkConcurrency
        )
    }
}
