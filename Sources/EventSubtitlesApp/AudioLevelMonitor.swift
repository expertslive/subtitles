@preconcurrency import AVFoundation
import Foundation

enum AudioLevelMonitorError: LocalizedError {
    case microphoneDenied
    case inputUnavailable
    case recordingUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone/input permission was denied."
        case .inputUnavailable:
            "No audio input device is available."
        case .recordingUnavailable(let message):
            "Audio recording could not start: \(message)"
        }
    }
}

final class AudioLevelMonitor: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var running = false
    private var recordingFile: AVAudioFile?

    func start(
        recordingURL: URL? = nil,
        onLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        guard await requestAudioAccess() else {
            throw AudioLevelMonitorError.microphoneDenied
        }

        if running {
            stop()
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            throw AudioLevelMonitorError.inputUnavailable
        }

        if let recordingURL {
            do {
                recordingFile = try AVAudioFile(
                    forWriting: recordingURL,
                    settings: format.settings,
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved
                )
            } catch {
                throw AudioLevelMonitorError.recordingUnavailable(error.localizedDescription)
            }
        } else {
            recordingFile = nil
        }

        let file = recordingFile
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            try? file?.write(from: buffer)
            guard let channels = buffer.floatChannelData else {
                onLevel(0)
                return
            }

            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(format.channelCount)
            guard frameLength > 0, channelCount > 0 else {
                onLevel(0)
                return
            }

            var sum: Float = 0
            for channel in 0..<channelCount {
                let channelData = channels[channel]
                for frame in 0..<frameLength {
                    let sample = channelData[frame]
                    sum += sample * sample
                }
            }

            let rms = sqrt(sum / Float(frameLength * channelCount))
            let decibels = 20 * log10(max(rms, 0.000_001))
            let normalized = min(1, max(0, (decibels + 60) / 60))
            onLevel(normalized)
        }

        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() {
        guard running else {
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        recordingFile = nil
        running = false
    }

    private func requestAudioAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
