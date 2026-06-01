@preconcurrency import AVFoundation
import EventSubtitlesCore
import Foundation
@preconcurrency import WhisperKit

final class WhisperKitTranscriber: SpeechTranscribing, @unchecked Sendable {
    private let settingsLock = NSLock()
    private var whisperKit: WhisperKit?
    private var streamProcessor: StreamFedAudioProcessor?
    private var streamTranscribeTask: TranscribeTask?
    private var streamRunnerTask: Task<Void, Never>?
    private let maximumRetainedAudioSeconds: TimeInterval
    private var lastProcessedTotalSampleCount = 0
    private var lastConfirmedSegmentEndSeconds: Float = 0
    private var lastPartialText = ""
    private var modelName: String
    private var loadedModelName: String?
    private var streamStartedAt: Date?
    private let requiredSegmentsForConfirmation = 0
    private let silenceThreshold: Float = 0.25
    private let compressionCheckWindow = 60
    private var decodeSettings = WhisperDecodeSettings.eventSafeDefaults

    init(modelName: String = "large-v3-v20240930_626MB", maximumRetainedAudioSeconds: TimeInterval = 30) {
        self.modelName = modelName
        self.maximumRetainedAudioSeconds = maximumRetainedAudioSeconds
    }

    func setModelName(_ modelName: String) {
        self.modelName = modelName
    }

    func setDecodeSettings(_ settings: WhisperDecodeSettings) {
        settingsLock.lock()
        decodeSettings = settings
        settingsLock.unlock()
    }

    func prepareModel() async throws {
        await stop(unloadModel: loadedModelName != modelName)
        if whisperKit == nil || loadedModelName != modelName {
            whisperKit = try await loadWhisperKit()
            loadedModelName = modelName
        }
    }

    /// Push a chunk of 16 kHz mono Float samples directly into Whisper's audio buffer.
    /// Called from the AudioCapturePipeline's tap callback (audio thread). Cheap, no
    /// async hop, no stream allocation. Returns immediately if the transcriber is not
    /// running yet (samples before start are dropped).
    func ingest(_ samples: [Float]) {
        streamProcessor?.ingest(samples)
    }

    func start(
        configuration: SpeechEngineConfiguration,
        onResult: @escaping @Sendable (SpeechRecognitionResult) -> Void
    ) async throws {
        await stop(unloadModel: loadedModelName != modelName)
        lastProcessedTotalSampleCount = 0
        lastConfirmedSegmentEndSeconds = 0
        lastPartialText = ""
        streamStartedAt = Date()
        setDecodeSettings(configuration.whisperDecodeSettings)

        let kit: WhisperKit
        if let preparedKit = whisperKit, loadedModelName == modelName {
            kit = preparedKit
        } else {
            kit = try await loadWhisperKit()
            whisperKit = kit
            loadedModelName = modelName
        }

        guard let tokenizer = kit.tokenizer else {
            throw WhisperKitTranscriberError.tokenizerUnavailable
        }

        // promptTokens are intentionally disabled: Whisper echoes the prompt text back
        // into the first transcribed segment when the prompt does not look like natural
        // speech (e.g. "Event: <name>. Vocabulary: term1, term2."). The GlossaryCorrector
        // already fixes spelling for the same terms post-recognition, so we keep that
        // outcome without the echo risk. Re-enable once we have reliable anti-echo
        // post-processing.
        _ = SpeechPromptBuilder.promptText(
            sessionName: configuration.sessionName,
            glossary: configuration.glossary
        )

        let detectLanguage = configuration.sourceLanguage == .automatic

        let processor = StreamFedAudioProcessor(maximumRetainedSeconds: maximumRetainedAudioSeconds)
        self.streamProcessor = processor

        let transcribeTask = TranscribeTask(
            currentTimings: TranscriptionTimings(),
            progress: Progress(),
            audioProcessor: processor,
            audioEncoder: kit.audioEncoder,
            featureExtractor: kit.featureExtractor,
            segmentSeeker: kit.segmentSeeker,
            textDecoder: kit.textDecoder,
            tokenizer: tokenizer
        )
        streamTranscribeTask = transcribeTask

        // Own the streaming loop instead of using WhisperKit's AudioStreamTranscriber.
        // That actor tracks progress by retained buffer length, which stalls once a
        // rolling buffer reaches its cap. We track total ingested samples instead.
        streamRunnerTask = Task.detached(priority: .userInitiated) { [weak self, weak processor, weak transcribeTask] in
            guard let self, let processor, let transcribeTask else { return }
            await self.runRealtimeLoop(
                processor: processor,
                transcribeTask: transcribeTask,
                configuredLanguageCode: self.whisperLanguageCode(for: configuration.sourceLanguage),
                detectLanguage: detectLanguage,
                configuredLanguage: configuration.sourceLanguage,
                onResult: onResult
            )
        }
    }

    func stop() async {
        await stop(unloadModel: false)
    }

    private func stop(unloadModel: Bool) async {
        streamProcessor = nil
        streamTranscribeTask = nil
        streamRunnerTask?.cancel()
        streamRunnerTask = nil
        if unloadModel {
            whisperKit = nil
            loadedModelName = nil
        }
        streamStartedAt = nil
        lastProcessedTotalSampleCount = 0
        lastConfirmedSegmentEndSeconds = 0
        lastPartialText = ""
    }

    private func loadWhisperKit() async throws -> WhisperKit {
        try await WhisperKit(
            WhisperKitConfig(
                model: modelName,
                verbose: false,
                prewarm: true,
                load: true,
                download: true
            )
        )
    }

    private func runRealtimeLoop(
        processor: StreamFedAudioProcessor,
        transcribeTask: TranscribeTask,
        configuredLanguageCode: String?,
        detectLanguage: Bool,
        configuredLanguage: SourceLanguage,
        onResult: @escaping @Sendable (SpeechRecognitionResult) -> Void
    ) async {
        while !Task.isCancelled, streamProcessor === processor, streamTranscribeTask === transcribeTask {
            do {
                try await transcribeCurrentBuffer(
                    processor: processor,
                    transcribeTask: transcribeTask,
                    configuredLanguageCode: configuredLanguageCode,
                    detectLanguage: detectLanguage,
                    configuredLanguage: configuredLanguage,
                    onResult: onResult
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func transcribeCurrentBuffer(
        processor: StreamFedAudioProcessor,
        transcribeTask: TranscribeTask,
        configuredLanguageCode: String?,
        detectLanguage: Bool,
        configuredLanguage: SourceLanguage,
        onResult: @escaping @Sendable (SpeechRecognitionResult) -> Void
    ) async throws {
        let settings = currentDecodeSettings()
        let minimumDecodeAudioSeconds = Float(settings.minimumDecodeAudioSeconds)
        let maximumLiveDecodeWindowSeconds = Float(settings.liveDecodeWindowSeconds)
        let snapshot = processor.snapshot()
        let nextBufferSize = snapshot.totalSampleCount - lastProcessedTotalSampleCount
        let nextBufferSeconds = Float(nextBufferSize) / Float(WhisperKit.sampleRate)

        guard nextBufferSeconds >= minimumDecodeAudioSeconds else {
            try await Task.sleep(nanoseconds: 100_000_000)
            return
        }

        let voiceDetected = AudioProcessor.isVoiceDetected(
            in: snapshot.relativeEnergy,
            nextBufferInSeconds: nextBufferSeconds,
            silenceThreshold: silenceThreshold
        )
        guard voiceDetected else {
            try await Task.sleep(nanoseconds: 100_000_000)
            return
        }

        lastProcessedTotalSampleCount = snapshot.totalSampleCount

        var options = decodeOptions(
            settings: settings,
            languageCode: configuredLanguageCode,
            detectLanguage: detectLanguage
        )
        let snapshotDurationSeconds = Float(snapshot.samples.count) / Float(WhisperKit.sampleRate)
        let confirmedClipTimestamp = max(0, lastConfirmedSegmentEndSeconds - Float(snapshot.streamOffsetSeconds))
        let recentWindowStart = max(0, snapshotDurationSeconds - maximumLiveDecodeWindowSeconds)
        let clipTimestamp = max(confirmedClipTimestamp, recentWindowStart)
        options.clipTimestamps = [clipTimestamp]
        let offset = Float(snapshot.streamOffsetSeconds)
        let checkWindow = compressionCheckWindow

        let transcription = try await transcribeTask.run(audioArray: snapshot.samples, decodeOptions: options) { progress in
            return Self.shouldStopEarly(progress: progress, options: options, compressionCheckWindow: checkWindow)
        }

        let absoluteSegments = transcription.segments.map { offsetSegment($0, by: offset) }
        publishConfirmedSegments(
            absoluteSegments,
            configuredLanguage: configuredLanguage,
            onResult: onResult
        )
    }

    private func currentDecodeSettings() -> WhisperDecodeSettings {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return decodeSettings
    }

    private func decodeOptions(
        settings: WhisperDecodeSettings,
        languageCode: String?,
        detectLanguage: Bool
    ) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: languageCode,
            temperature: Float(settings.temperature),
            temperatureIncrementOnFallback: Float(settings.temperatureFallbackIncrement),
            temperatureFallbackCount: settings.temperatureFallbackCount,
            usePrefillPrompt: true,
            detectLanguage: detectLanguage,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: false,
            promptTokens: nil,
            chunkingStrategy: .vad
        )
    }

    private func publishConfirmedSegments(
        _ segments: [TranscriptionSegment],
        configuredLanguage: SourceLanguage,
        onResult: @escaping @Sendable (SpeechRecognitionResult) -> Void
    ) {
        guard segments.count > requiredSegmentsForConfirmation else {
            publishPartialText(
                partialText(from: segments),
                configuredLanguage: configuredLanguage,
                words: recognizedWords(in: segments),
                onResult: onResult
            )
            return
        }

        let confirmed = segments.dropLast(requiredSegmentsForConfirmation)
        let unconfirmed = segments.suffix(requiredSegmentsForConfirmation)

        for segment in confirmed where segment.end > lastConfirmedSegmentEndSeconds {
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            lastConfirmedSegmentEndSeconds = max(lastConfirmedSegmentEndSeconds, segment.end)
            onResult(
                SpeechRecognitionResult(
                    text: trimmed,
                    language: configuredLanguage,
                    isFinal: true,
                    startedAt: absoluteDate(for: segment.start),
                    endedAt: absoluteDate(for: segment.end),
                    words: recognizedWords(in: [segment])
                )
            )
        }

        publishPartialText(
            partialText(from: unconfirmed),
            configuredLanguage: configuredLanguage,
            words: recognizedWords(in: unconfirmed),
            onResult: onResult
        )
    }

    private func publishPartialText(
        _ partialText: String,
        configuredLanguage: SourceLanguage,
        words: [RecognizedWord],
        onResult: @escaping @Sendable (SpeechRecognitionResult) -> Void
    ) {
        guard !partialText.isEmpty, partialText != lastPartialText else {
            return
        }
        lastPartialText = partialText
        onResult(
            SpeechRecognitionResult(
                text: partialText,
                language: configuredLanguage,
                isFinal: false,
                startedAt: nil,
                endedAt: Date(),
                words: words
            )
        )
    }

    private static func shouldStopEarly(
        progress: TranscriptionProgress,
        options: DecodingOptions,
        compressionCheckWindow: Int
    ) -> Bool? {
        let currentTokens = progress.tokens
        if currentTokens.count > compressionCheckWindow {
            let checkTokens = Array(currentTokens.suffix(compressionCheckWindow))
            let compressionRatio = TextUtilities.compressionRatio(of: checkTokens)
            if compressionRatio > options.compressionRatioThreshold ?? 0.0 {
                return false
            }
        }
        if let avgLogprob = progress.avgLogprob, let logProbThreshold = options.logProbThreshold {
            if avgLogprob < logProbThreshold {
                return false
            }
        }
        return nil
    }

    private func recognizedWords(in segments: some Sequence<TranscriptionSegment>) -> [RecognizedWord] {
        var words: [RecognizedWord] = []
        for segment in segments {
            guard let segmentWords = segment.words else {
                continue
            }
            for word in segmentWords {
                let trimmed = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                words.append(
                    RecognizedWord(
                        text: trimmed,
                        probability: Float(word.probability),
                        startSeconds: Double(word.start),
                        endSeconds: Double(word.end)
                    )
                )
            }
        }
        return words
    }

    private func partialText(from segments: some Sequence<TranscriptionSegment>) -> String {
        segments
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func whisperLanguageCode(for language: SourceLanguage) -> String? {
        switch language {
        case .automatic:
            nil
        case .english:
            "en"
        case .dutch:
            "nl"
        }
    }

    private func absoluteDate(for streamSeconds: Float) -> Date? {
        streamStartedAt?.addingTimeInterval(TimeInterval(streamSeconds))
    }

    private func offsetSegment(_ segment: TranscriptionSegment, by offset: Float) -> TranscriptionSegment {
        var copy = segment
        copy.start += offset
        copy.end += offset
        copy.words = segment.words?.map { word in
            var copy = word
            copy.start += offset
            copy.end += offset
            return copy
        }
        return copy
    }
}
enum WhisperKitTranscriberError: LocalizedError {
    case tokenizerUnavailable

    var errorDescription: String? {
        switch self {
        case .tokenizerUnavailable:
            "WhisperKit tokenizer was not loaded."
        }
    }
}
