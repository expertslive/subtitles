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
    private var recordingFile: AVAudioFile?
    private var running = false
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
        guard await requestAudioAccess() else {
            throw AudioCapturePipelineError.microphoneDenied
        }

        let wasRunning = stateLock.withLock { running }
        if wasRunning {
            stop()
        }

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
            do {
                recordingFile = try AVAudioFile(
                    forWriting: recordingURL,
                    settings: whisperFormat.settings,
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
            } catch {
                throw AudioCapturePipelineError.recordingUnavailable(error.localizedDescription)
            }
        } else {
            recordingFile = nil
        }

        let bufferSize: AVAudioFrameCount = 1024
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        installConfigChangeObserver()
        installDefaultInputDeviceListener()

        engine.prepare()
        try engine.start()

        stateLock.withLock { running = true }
    }

    func stop() {
        stateLock.lock()
        guard running else {
            stateLock.unlock()
            return
        }
        running = false
        stateLock.unlock()

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil

        let drained = recordingFile
        recordingFile = nil
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

        samplesHandler = nil
    }

    func restart(
        inputDeviceID: AudioDeviceID?,
        recordingURL: URL?
    ) async throws {
        let level = self.levelHandler
        let samples = self.samplesHandler
        let onChange = self.onConfigurationDidChange
        stop()
        guard let level, let samples, let onChange else {
            throw AudioCapturePipelineError.inputUnavailable
        }
        try await start(
            inputDeviceID: inputDeviceID,
            recordingURL: recordingURL,
            onLevel: level,
            onSamples: samples,
            onConfigurationChange: onChange
        )
    }

    // MARK: - Private

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let inSampleRate = buffer.format.sampleRate
        let outSampleRate = whisperFormat.sampleRate
        let outFrameCapacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * outSampleRate / inSampleRate)
        )
        guard outFrameCapacity > 0,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: outFrameCapacity)
        else {
            levelHandler?(AudioLevelSample(rms: 0, peak: 0))
            return
        }

        var error: NSError?
        var inputProvided = false
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error,
              let channel = outBuffer.floatChannelData?[0] else {
            levelHandler?(AudioLevelSample(rms: 0, peak: 0))
            return
        }

        let frameCount = Int(outBuffer.frameLength)
        guard frameCount > 0 else {
            levelHandler?(AudioLevelSample(rms: 0, peak: 0))
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
        levelHandler?(AudioLevelSample(rms: normalizedRMS, peak: normalizedPeak))

        // Hand a Float copy to the Whisper consumer via direct callback.
        let samples = Array(UnsafeBufferPointer(start: channel, count: frameCount))
        samplesHandler?(samples)

        // Hand the converted PCM buffer to the write queue (off the audio thread).
        let bufferCopy = outBuffer
        writeQueue.async { [weak self] in
            try? self?.recordingFile?.write(from: bufferCopy)
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

    private func installConfigChangeObserver() {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.onConfigurationDidChange?()
        }
    }

    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private func installDefaultInputDeviceListener() {
        guard !defaultDeviceListenerInstalled else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onConfigurationDidChange?()
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
