@preconcurrency import AVFoundation
import CoreML
import EventSubtitlesCore
import Foundation
@preconcurrency import WhisperKit

struct StreamFedAudioSnapshot: Sendable {
    let samples: [Float]
    let relativeEnergy: [Float]
    let totalSampleCount: Int
    let droppedSampleCount: Int
    let streamOffsetSeconds: TimeInterval
}

/// `AudioProcessing` impl that consumes a `[Float]` stream supplied by AudioCapturePipeline
/// instead of opening its own input device. Keeps a bounded rolling sample window
/// so live transcription does not retain an entire event day in memory.
final class StreamFedAudioProcessor: AudioProcessing, @unchecked Sendable {
    private let lock = NSLock()
    private var sampleBuffer: RollingAudioSampleBuffer
    private var audioEnergy: [(rel: Float, avg: Float, max: Float, min: Float)] = []
    private var energyWindowSize = 20
    private let sampleRate: Int

    init(maximumRetainedSeconds: TimeInterval = 30, sampleRate: Int = WhisperKit.sampleRate) {
        self.sampleRate = max(1, sampleRate)
        let maximumRetainedSamples = max(1, Int(maximumRetainedSeconds * TimeInterval(self.sampleRate)))
        self.sampleBuffer = RollingAudioSampleBuffer(
            maximumRetainedSamples: maximumRetainedSamples,
            sampleRate: self.sampleRate
        )
    }

    var audioSamples: ContiguousArray<Float> {
        lock.lock()
        defer { lock.unlock() }
        return ContiguousArray(sampleBuffer.samples)
    }

    var relativeEnergy: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return audioEnergy.map { $0.rel }
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
    /// Computes per-buffer relative energy using WhisperKit's own formula so that
    /// `AudioStreamTranscriber`'s VAD can detect speech.
    func ingest(_ chunk: [Float]) {
        lock.lock()
        sampleBuffer.append(chunk)

        // Match WhisperKit's AudioProcessor.processBuffer: silence baseline = min avg energy
        // over the last `relativeEnergyWindow` buffers.
        let minAvgEnergy = audioEnergy.suffix(energyWindowSize).reduce(Float.infinity) { min($0, $1.avg) }
        let referenceEnergy: Float? = minAvgEnergy.isFinite ? minAvgEnergy : nil
        let relative = AudioProcessor.calculateRelativeEnergy(of: chunk, relativeTo: referenceEnergy)
        let signalEnergy = AudioProcessor.calculateEnergy(of: chunk)

        audioEnergy.append((rel: relative, avg: signalEnergy.avg, max: signalEnergy.max, min: signalEnergy.min))
        if audioEnergy.count > energyWindowSize * 8 {
            audioEnergy.removeFirst(audioEnergy.count - energyWindowSize * 8)
        }
        lock.unlock()
    }

    func snapshot() -> StreamFedAudioSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return StreamFedAudioSnapshot(
            samples: sampleBuffer.samples,
            relativeEnergy: audioEnergy.map { $0.rel },
            totalSampleCount: sampleBuffer.totalSampleCount,
            droppedSampleCount: sampleBuffer.droppedSampleCount,
            streamOffsetSeconds: sampleBuffer.streamOffsetSeconds
        )
    }

    func reset() {
        lock.lock()
        sampleBuffer.reset()
        audioEnergy.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func purgeAudioSamples(keepingLast keep: Int) {
        lock.lock()
        let retained = sampleBuffer.samples
        sampleBuffer.reset()
        sampleBuffer.append(Array(retained.suffix(max(0, keep))))
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
