import Foundation
import WhisperKit

let modelName = CommandLine.arguments.dropFirst().first ?? "large-v3-v20240930_626MB"

print("Preparing WhisperKit model: \(modelName)")
print("This may download model files the first time it runs.")

let startedAt = Date()
_ = try await WhisperKit(
    WhisperKitConfig(
        model: modelName,
        verbose: true,
        prewarm: true,
        load: true,
        download: true
    )
)

let elapsed = Date().timeIntervalSince(startedAt)
print("Prepared \(modelName) in \(String(format: "%.1f", elapsed))s")
