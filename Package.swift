// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EventSubtitles",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EventSubtitles", targets: ["EventSubtitlesApp"]),
        .executable(name: "EventSubtitlesSmokeTests", targets: ["EventSubtitlesSmokeTests"]),
        .executable(name: "EventSubtitlesCoreUnitTests", targets: ["EventSubtitlesCoreUnitTests"]),
        .executable(name: "EventSubtitlesRemoteControlUnitTests", targets: ["EventSubtitlesRemoteControlUnitTests"]),
        .executable(name: "PrepareWhisperModel", targets: ["PrepareWhisperModel"]),
        .library(name: "EventSubtitlesCore", targets: ["EventSubtitlesCore"]),
        .library(name: "EventSubtitlesRemoteControl", targets: ["EventSubtitlesRemoteControl"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.18.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.80.0")
    ],
    targets: [
        .target(name: "EventSubtitlesCore"),
        .executableTarget(
            name: "EventSubtitlesApp",
            dependencies: [
                "EventSubtitlesCore",
                "EventSubtitlesRemoteControl",
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .executableTarget(
            name: "EventSubtitlesSmokeTests",
            dependencies: ["EventSubtitlesCore"]
        ),
        .executableTarget(
            name: "EventSubtitlesCoreUnitTests",
            dependencies: ["EventSubtitlesCore"]
        ),
        .target(
            name: "EventSubtitlesRemoteControl",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio")
            ]
        ),
        .executableTarget(
            name: "EventSubtitlesRemoteControlUnitTests",
            dependencies: ["EventSubtitlesRemoteControl"]
        ),
        .executableTarget(
            name: "PrepareWhisperModel",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        )
    ]
)
