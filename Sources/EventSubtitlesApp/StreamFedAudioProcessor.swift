@preconcurrency import AVFoundation
import CoreML
import Foundation
@preconcurrency import WhisperKit

/// `AudioProcessing` impl that consumes a `[Float]` stream supplied by AudioCapturePipeline
/// instead of opening its own input device. Keeps the AudioStreamTranscriber happy by
/// maintaining a `audioSamples` buffer that grows from yielded chunks.
final class StreamFedAudioProcessor: AudioProcessing, @unchecked Sendable {
    private let lock = NSLock()
    private var samples = ContiguousArray<Float>()
    private var energy: [Float] = []
    private var energyWindowSize = 100

    var audioSamples: ContiguousArray<Float> {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    var relativeEnergy: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return energy
    }

    var relativeEnergyWindow: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return energyWindowSize
        }
        set {
            lock.lock(); defer { lock.unlock() }
            energyWindowSize = max(1, newValue)
        }
    }

    /// Push samples produced by AudioCapturePipeline into Whisper's view.
    func ingest(_ chunk: [Float]) {
        lock.lock()
        samples.append(contentsOf: chunk)
        let rms = chunk.isEmpty ? 0 : sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        energy.append(rms)
        if energy.count > energyWindowSize * 4 {
            energy.removeFirst(energy.count - energyWindowSize * 4)
        }
        lock.unlock()
    }

    func purgeAudioSamples(keepingLast keep: Int) {
        lock.lock()
        if samples.count > keep {
            samples.removeFirst(samples.count - keep)
        }
        lock.unlock()
    }

    // MARK: - Live-recording entry points are no-ops (we get samples via `ingest`).

    func startRecordingLive(inputDeviceID: DeviceID?, callback: (([Float]) -> Void)?) throws {
        // No-op: capture is owned by AudioCapturePipeline.
    }

    func startStreamingRecordingLive(
        inputDeviceID: DeviceID?
    ) -> (AsyncThrowingStream<[Float], Error>, AsyncThrowingStream<[Float], Error>.Continuation) {
        AsyncThrowingStream<[Float], Error>.makeStream()
    }

    func pauseRecording() { /* no-op */ }
    func stopRecording() { /* no-op */ }
    func resumeRecordingLive(inputDeviceID: DeviceID?, callback: (([Float]) -> Void)?) throws { /* no-op */ }

    // MARK: - File-loading entry points: delegate to WhisperKit's static helpers.

    static func loadAudio(
        fromPath audioFilePath: String,
        channelMode: ChannelMode,
        startTime: Double?,
        endTime: Double?,
        maxReadFrameSize: AVAudioFrameCount?
    ) throws -> AVAudioPCMBuffer {
        try AudioProcessor.loadAudio(
            fromPath: audioFilePath,
            channelMode: channelMode,
            startTime: startTime,
            endTime: endTime,
            maxReadFrameSize: maxReadFrameSize
        )
    }

    static func loadAudio(
        at audioPaths: [String],
        channelMode: ChannelMode
    ) async -> [Result<[Float], Error>] {
        await AudioProcessor.loadAudio(at: audioPaths, channelMode: channelMode)
    }

    static func padOrTrimAudio(
        fromArray audioArray: [Float],
        startAt startIndex: Int,
        toLength frameLength: Int,
        saveSegment: Bool
    ) -> MLMultiArray? {
        AudioProcessor.padOrTrimAudio(
            fromArray: audioArray,
            startAt: startIndex,
            toLength: frameLength,
            saveSegment: saveSegment
        )
    }

    func padOrTrim(
        fromArray audioArray: [Float],
        startAt startIndex: Int,
        toLength frameLength: Int
    ) -> (any AudioProcessorOutputType)? {
        AudioProcessor().padOrTrim(
            fromArray: audioArray,
            startAt: startIndex,
            toLength: frameLength
        )
    }
}
