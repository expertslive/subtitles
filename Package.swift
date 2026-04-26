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
        .executable(name: "PrepareWhisperModel", targets: ["PrepareWhisperModel"]),
        .library(name: "EventSubtitlesCore", targets: ["EventSubtitlesCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.18.0")
    ],
    targets: [
        .target(name: "EventSubtitlesCore"),
        .executableTarget(
            name: "EventSubtitlesApp",
            dependencies: [
                "EventSubtitlesCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .executableTarget(
            name: "EventSubtitlesSmokeTests",
            dependencies: ["EventSubtitlesCore"]
        ),
        .executableTarget(
            name: "PrepareWhisperModel",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        )
    ]
)
