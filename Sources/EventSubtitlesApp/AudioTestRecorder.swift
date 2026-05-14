import CoreAudio
import Foundation

@MainActor
final class AudioTestRecorder {
    private let pipeline = AudioCapturePipeline()

    func record(inputDeviceID: AudioDeviceID?, duration: TimeInterval = 5) async throws -> AudioTestRecordingResult {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EventSubtitles-TestRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = Self.fileStamp.string(from: Date())
        let url = directory.appendingPathComponent("audio-test-\(stamp).caf")
        let stats = AudioTestStats()

        try await pipeline.start(
            inputDeviceID: inputDeviceID,
            recordingURL: url,
            onLevel: { sample in
                stats.ingest(sample)
            },
            onSamples: { _ in },
            onConfigurationChange: {}
        )

        try await Task.sleep(for: .seconds(duration))
        pipeline.stop()

        let peak = stats.peakLevel
        return AudioTestRecordingResult(
            url: url,
            duration: duration,
            peakLevel: peak,
            clipped: stats.didClip,
            silent: peak < 0.05
        )
    }

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

private final class AudioTestStats: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Double = 0
    private var clipped = false

    var peakLevel: Double {
        lock.withLock { peak }
    }

    var didClip: Bool {
        lock.withLock { clipped }
    }

    func ingest(_ sample: AudioLevelSample) {
        let level = Double(max(sample.rms, sample.peak))
        lock.withLock {
            peak = max(peak, level)
            if level > 0.92 {
                clipped = true
            }
        }
    }
}
