import Accelerate
@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

enum AudioCapturePipelineError: LocalizedError {
    case microphoneDenied
    case inputUnavailable
    case deviceConfigurationFailed(OSStatus)
    case recordingUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone/input permission was denied."
        case .inputUnavailable:
            "No audio input device is available."
        case .deviceConfigurationFailed(let status):
            "Selected input device could not be used (\(status))."
        case .recordingUnavailable(let message):
            "Audio recording could not start: \(message)"
        }
    }
}

struct AudioLevelSample: Sendable {
    let rms: Float       // 0..1 normalized
    let peak: Float      // 0..1 normalized
}

/// Single audio capture pipeline. Owns the only AVAudioEngine in the app.
/// Fans the input out to: a level callback, an off-thread CAF writer, and a
/// `[Float]` AsyncStream consumed by the Whisper input adapter.
final class AudioCapturePipeline: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let writeQueue = DispatchQueue(label: "audio.capture.write", qos: .utility)
    private let stateLock = NSLock()
    private let controlLock = NSLock()
    private var controlGeneration: UInt64 = 0
    private var recordingFile: AVAudioFile?
    private var running = false
    private var activeDeliveryGeneration: UInt64?
    private var captureResourcesInstalled = false
    private var converter: AVAudioConverter?

    private let whisperFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }()

    private var levelHandler: (@Sendable (AudioLevelSample) -> Void)?
    private var samplesHandler: (@Sendable ([Float]) -> Void)?
    private var configChangeObserver: NSObjectProtocol?
    private var defaultDeviceListenerInstalled = false
    private var defaultInputListenerBlock: AudioObjectPropertyListenerBlock?
    private var onConfigurationDidChange: (@Sendable () -> Void)?

    init() {}

    deinit {
        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
        }
        if defaultDeviceListenerInstalled {
            removeDefaultInputDeviceListener()
        }
    }

    func start(
        inputDeviceID: AudioDeviceID?,
        recordingURL: URL?,
        onLevel: @escaping @Sendable (AudioLevelSample) -> Void,
        onSamples: @escaping @Sendable ([Float]) -> Void,
        onConfigurationChange: @escaping @Sendable () -> Void
    ) async throws {
        let operationGeneration = beginControlOperation()
        try await start(
            operationGeneration: operationGeneration,
            inputDeviceID: inputDeviceID,
            recordingURL: recordingURL,
            onLevel: onLevel,
            onSamples: onSamples,
            onConfigurationChange: onConfigurationChange
        )
    }

    func start(
        operationGeneration: UInt64,
        inputDeviceID: AudioDeviceID?,
        recordingURL: URL?,
        onLevel: @escaping @Sendable (AudioLevelSample) -> Void,
        onSamples: @escaping @Sendable ([Float]) -> Void,
        onConfigurationChange: @escaping @Sendable () -> Void
    ) async throws {
        let hasAudioAccess = await requestAudioAccess()

        try controlLock.withLock {
            guard controlGeneration == operationGeneration else { throw CancellationError() }
            guard hasAudioAccess else {
                throw AudioCapturePipelineError.microphoneDenied
            }

            try startLocked(
                operationGeneration: operationGeneration,
                inputDeviceID: inputDeviceID,
                recordingURL: recordingURL,
                preserveExistingRecording: false,
                onLevel: onLevel,
                onSamples: onSamples,
                onConfigurationChange: onConfigurationChange
            )
        }
    }

    private func startLocked(
        operationGeneration: UInt64,
        inputDeviceID: AudioDeviceID?,
        recordingURL: URL?,
        preserveExistingRecording: Bool,
        onLevel: @escaping @Sendable (AudioLevelSample) -> Void,
        onSamples: @escaping @Sendable ([Float]) -> Void,
        onConfigurationChange: @escaping @Sendable () -> Void
    ) throws {
        let wasRunning = stateLock.withLock { running }
        if wasRunning {
            stopLocked(keepRecordingFile: preserveExistingRecording)
        }

        do {
            levelHandler = onLevel
            samplesHandler = onSamples
            onConfigurationDidChange = onConfigurationChange

            if let inputDeviceID {
                try setInputDevice(inputDeviceID)
            }

            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
                throw AudioCapturePipelineError.inputUnavailable
            }

            guard let converter = AVAudioConverter(from: inputFormat, to: whisperFormat) else {
                throw AudioCapturePipelineError.recordingUnavailable(
                    "Cannot convert from \(inputFormat) to 16 kHz mono Float32."
                )
            }
            self.converter = converter

            if let recordingURL {
                recordingFile = try openRecordingFile(at: recordingURL)
            } else if !preserveExistingRecording {
                recordingFile = nil
            }
            let installedRecordingFile = recordingFile

            let bufferSize: AVAudioFrameCount = 1024
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
                self?.handleBuffer(
                    buffer,
                    operationGeneration: operationGeneration,
                    converter: converter,
                    recordingFile: installedRecordingFile,
                    onLevel: onLevel,
                    onSamples: onSamples
                )
            }

            installConfigChangeObserver(onConfigurationChange)
            installDefaultInputDeviceListener(onConfigurationChange)
            captureResourcesInstalled = true

            engine.prepare()
            try engine.start()

            stateLock.withLock {
                running = true
                activeDeliveryGeneration = operationGeneration
            }
        } catch {
            cleanupCaptureResourcesLocked(keepRecordingFile: preserveExistingRecording)
            throw error
        }
    }

    func stop() {
        controlLock.withLock {
            controlGeneration &+= 1
            stopLocked(keepRecordingFile: false)
        }
    }

    private func stopLocked(keepRecordingFile: Bool) {
        cleanupCaptureResourcesLocked(keepRecordingFile: keepRecordingFile)
    }

    private func cleanupCaptureResourcesLocked(keepRecordingFile: Bool) {
        stateLock.withLock {
            running = false
            activeDeliveryGeneration = nil
        }

        if captureResourcesInstalled {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        converter = nil

        let drained = recordingFile
        if !keepRecordingFile {
            recordingFile = nil
        }
        writeQueue.sync {
            // Force the queue to drain any in-flight writes referencing `drained`.
            _ = drained
        }

        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
            self.configChangeObserver = nil
        }
        if defaultDeviceListenerInstalled {
            removeDefaultInputDeviceListener()
        }

        levelHandler = nil
        samplesHandler = nil
        onConfigurationDidChange = nil
        captureResourcesInstalled = false
    }

    func restart(
        inputDeviceID: AudioDeviceID?,
        recordingURL: URL?
    ) async throws {
        let operationGeneration = beginControlOperation()
        try await restart(
            operationGeneration: operationGeneration,
            inputDeviceID: inputDeviceID,
            recordingURL: recordingURL
        )
    }

    func restart(
        operationGeneration: UInt64,
        inputDeviceID: AudioDeviceID?,
        recordingURL: URL?
    ) async throws {
        try controlLock.withLock {
            guard controlGeneration == operationGeneration else { throw CancellationError() }

            let level = self.levelHandler
            let samples = self.samplesHandler
            let onChange = self.onConfigurationDidChange
            let shouldPreserveRecording = recordingURL == nil && recordingFile != nil
            stopLocked(keepRecordingFile: shouldPreserveRecording)
            guard let level, let samples, let onChange else {
                throw AudioCapturePipelineError.inputUnavailable
            }
            try startLocked(
                operationGeneration: operationGeneration,
                inputDeviceID: inputDeviceID,
                recordingURL: recordingURL,
                preserveExistingRecording: shouldPreserveRecording,
                onLevel: level,
                onSamples: samples,
                onConfigurationChange: onChange
            )
        }
    }

    // MARK: - Private

    func reserveControlOperation() -> UInt64 {
        beginControlOperation()
    }

    private func beginControlOperation() -> UInt64 {
        controlLock.withLock {
            controlGeneration &+= 1
            return controlGeneration
        }
    }

    private func handleBuffer(
        _ buffer: AVAudioPCMBuffer,
        operationGeneration: UInt64,
        converter: AVAudioConverter,
        recordingFile: AVAudioFile?,
        onLevel: @escaping @Sendable (AudioLevelSample) -> Void,
        onSamples: @escaping @Sendable ([Float]) -> Void
    ) {
        guard canDeliverCallbacks(for: operationGeneration) else { return }

        let inSampleRate = buffer.format.sampleRate
        let outSampleRate = whisperFormat.sampleRate
        let outFrameCapacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * outSampleRate / inSampleRate)
        )
        guard outFrameCapacity > 0,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: outFrameCapacity)
        else {
            guard canDeliverCallbacks(for: operationGeneration) else { return }
            onLevel(AudioLevelSample(rms: 0, peak: 0))
            return
        }

        var error: NSError?
        let inputProvider = SingleBufferConverterInput(buffer: buffer)
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            inputProvider.provide(outStatus: outStatus)
        }

        guard status != .error,
              let channel = outBuffer.floatChannelData?[0] else {
            guard canDeliverCallbacks(for: operationGeneration) else { return }
            onLevel(AudioLevelSample(rms: 0, peak: 0))
            return
        }

        let frameCount = Int(outBuffer.frameLength)
        guard frameCount > 0 else {
            guard canDeliverCallbacks(for: operationGeneration) else { return }
            onLevel(AudioLevelSample(rms: 0, peak: 0))
            return
        }

        // RMS + peak in one pass via vDSP.
        var rms: Float = 0
        var peak: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(frameCount))
        vDSP_maxmgv(channel, 1, &peak, vDSP_Length(frameCount))

        let dbRMS = 20 * log10(max(rms, 0.000_001))
        let dbPeak = 20 * log10(max(peak, 0.000_001))
        let normalizedRMS = min(1, max(0, (dbRMS + 60) / 60))
        let normalizedPeak = min(1, max(0, (dbPeak + 60) / 60))
        guard canDeliverCallbacks(for: operationGeneration) else { return }
        onLevel(AudioLevelSample(rms: normalizedRMS, peak: normalizedPeak))

        // Hand a Float copy to the Whisper consumer via direct callback.
        let samples = Array(UnsafeBufferPointer(start: channel, count: frameCount))
        onSamples(samples)

        // Hand the converted PCM buffer to the write queue (off the audio thread).
        if let file = recordingFile {
            let bufferCopy = outBuffer
            writeQueue.async {
                try? file.write(from: bufferCopy)
            }
        }
    }

    private func canDeliverCallbacks(for operationGeneration: UInt64) -> Bool {
        stateLock.withLock {
            running && activeDeliveryGeneration == operationGeneration
        }
    }

    private func openRecordingFile(at url: URL) throws -> AVAudioFile {
        do {
            return try AVAudioFile(
                forWriting: url,
                settings: whisperFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw AudioCapturePipelineError.recordingUnavailable(error.localizedDescription)
        }
    }

    private func setInputDevice(_ deviceID: AudioDeviceID) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw AudioCapturePipelineError.recordingUnavailable("Input audio unit is unavailable.")
        }

        var device = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioCapturePipelineError.deviceConfigurationFailed(status)
        }
    }

    private func installConfigChangeObserver(_ onConfigurationChange: @escaping @Sendable () -> Void) {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { _ in
            onConfigurationChange()
        }
    }

    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private func installDefaultInputDeviceListener(_ onConfigurationChange: @escaping @Sendable () -> Void) {
        guard !defaultDeviceListenerInstalled else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            onConfigurationChange()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            DispatchQueue.main,
            block
        )
        if status == noErr {
            defaultInputListenerBlock = block
            defaultDeviceListenerInstalled = true
        }
    }

    private func removeDefaultInputDeviceListener() {
        guard let block = defaultInputListenerBlock else {
            defaultDeviceListenerInstalled = false
            return
        }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            DispatchQueue.main,
            block
        )
        defaultInputListenerBlock = nil
        defaultDeviceListenerInstalled = false
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

private final class SingleBufferConverterInput: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var didProvide = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func provide(outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard !didProvide else {
            outStatus.pointee = .noDataNow
            return nil
        }

        didProvide = true
        outStatus.pointee = .haveData
        return buffer
    }
}
