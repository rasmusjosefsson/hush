// Tests/HushTests/STT/ModelRegistryTests.swift
import XCTest
@testable import HushCore

final class ModelRegistryTests: XCTestCase {

    func testAllModelsReturnsRegisteredModels() {
        let registry = ModelRegistry(defaults: .testSuite())
        let models = registry.allModels
        XCTAssertFalse(models.isEmpty)
    }

    func testDefaultModelExists() {
        let registry = ModelRegistry(defaults: .testSuite())
        let defaultModel = registry.allModels.first(where: { $0.isDefault })
        XCTAssertNotNil(defaultModel, "Registry must have a default model")
    }

    func testSelectedModelDefaultsToDefaultModel() {
        let defaults = UserDefaults.testSuite()
        let registry = ModelRegistry(defaults: defaults)
        let selected = registry.selectedModel
        XCTAssertTrue(selected.isDefault)
    }

    func testSelectModelPersists() throws {
        let defaults = UserDefaults.testSuite()
        let registry = ModelRegistry(defaults: defaults)
        let models = registry.allModels
        guard let nonDefault = models.first(where: { !$0.isDefault }) else {
            throw XCTSkip("Need at least 2 models")
            return
        }
        registry.selectModel(id: nonDefault.id)
        XCTAssertEqual(registry.selectedModel.id, nonDefault.id)

        // New registry instance reads from same defaults
        let registry2 = ModelRegistry(defaults: defaults)
        XCTAssertEqual(registry2.selectedModel.id, nonDefault.id)
    }

    func testSelectInvalidModelIDKeepsCurrentSelection() {
        let defaults = UserDefaults.testSuite()
        let registry = ModelRegistry(defaults: defaults)
        let before = registry.selectedModel
        registry.selectModel(id: "nonexistent-model-id")
        XCTAssertEqual(registry.selectedModel.id, before.id)
    }

    func testModelsForEngine() {
        let registry = ModelRegistry(defaults: .testSuite())
        let fluidModels = registry.models(for: .fluidAudio)
        XCTAssertTrue(fluidModels.allSatisfy { $0.engineType == .fluidAudio })
    }
}

private extension UserDefaults {
    static func testSuite() -> UserDefaults {
        let suiteName = "com.hush.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
