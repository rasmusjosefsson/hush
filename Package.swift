// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Hush",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Hush", targets: ["Hush"]),
        .executable(name: "hush-cli", targets: ["CLI"]),
        .library(name: "HushCore", targets: ["HushCore"]),
        .library(name: "HushUI", targets: ["HushUI"]),
        .library(name: "HushViewModels", targets: ["HushViewModels"])
    ],
    dependencies: [
        // GRDB for SQLite (dictation history + transcription records)
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        // FluidAudio for Parakeet STT on CoreML/ANE
        // v0.13.4+ removed swift-transformers dep, resolving the conflict with WhisperKit.
        .package(url: "https://github.com/FluidInference/FluidAudio", from: "0.14.5"),
        // WhisperKit for Whisper model inference on CoreML/ANE
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.18.0"),
        // ArgumentParser for CLI
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // Main GUI app
        .executableTarget(
            name: "Hush",
            dependencies: [
                "HushCore",
                "HushViewModels",
                "HushUI",
            ],
            path: "Sources/Hush",
            resources: [.process("Resources")]
        ),
        // CLI tool for headless testing and scripting
        .executableTarget(
            name: "CLI",
            dependencies: [
                "HushCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/CLI"
        ),
        // Shared core library (no UI dependencies)
        .target(
            name: "HushCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                "HushObjCShims",
            ],
            path: "Sources/HushCore"
        ),
        // ObjC exception catcher (Swift cannot catch NSException natively)
        .target(
            name: "HushObjCShims",
            path: "Sources/HushObjCShims",
            publicHeadersPath: "include"
        ),
        // ViewModels library (testable, depends on Core + AppKit/SwiftUI)
        .target(
            name: "HushViewModels",
            dependencies: ["HushCore"],
            path: "Sources/HushViewModels"
        ),
        // SwiftUI views library (enables previews)
        .target(
            name: "HushUI",
            dependencies: ["HushCore", "HushViewModels"],
            path: "Sources/HushUI"
        ),
        // Tests
        .testTarget(
            name: "HushTests",
            dependencies: ["HushCore", "HushViewModels"],
            path: "Tests/HushTests"
        ),
        .testTarget(
            name: "CLITests",
            dependencies: ["CLI", "HushCore"],
            path: "Tests/CLITests"
        )
    ]
)
