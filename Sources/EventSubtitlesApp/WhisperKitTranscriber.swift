@preconcurrency import AVFoundation
import EventSubtitlesCore
import Foundation
@preconcurrency import WhisperKit

final class WhisperKitTranscriber: SpeechTranscribing, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private var streamTranscriber: AudioStreamTranscriber?
    private var streamProcessor: StreamFedAudioProcessor?
    private var streamRunnerTask: Task<Void, Never>?
    private var lastConfirmedSegmentCount = 0
    private var lastPartialText = ""
    private var modelName: String
    private var loadedModelName: String?
    private var streamStartedAt: Date?

    init(modelName: String = "large-v3-v20240930_626MB") {
        self.modelName = modelName
    }

    func setModelName(_ modelName: String) {
        self.modelName = modelName
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
        lastConfirmedSegmentCount = 0
        lastPartialText = ""
        streamStartedAt = Date()

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

        let decodeOptions = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: whisperLanguageCode(for: configuration.sourceLanguage),
            usePrefillPrompt: true,
            detectLanguage: configuration.sourceLanguage == .automatic,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            promptTokens: nil,
            chunkingStrategy: .vad
        )

        let processor = StreamFedAudioProcessor()
        self.streamProcessor = processor

        let transcriber = AudioStreamTranscriber(
            audioEncoder: kit.audioEncoder,
            featureExtractor: kit.featureExtractor,
            segmentSeeker: kit.segmentSeeker,
            textDecoder: kit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: processor,
            decodingOptions: decodeOptions,
            requiredSegmentsForConfirmation: 1,
            silenceThreshold: 0.25,
            compressionCheckWindow: 60,
            useVAD: true
        ) { [weak self] _, newState in
            self?.handleState(newState, configuredLanguage: configuration.sourceLanguage, onResult: onResult)
        }

        streamTranscriber = transcriber

        // `startStreamTranscription()` enters a realtime loop that does not return until
        // `stopStreamTranscription()` flips `state.isRecording = false`. Run it as a
        // detached background task instead of awaiting it here, otherwise this method
        // (and every caller) would hang forever and `stop` would never run.
        // Audio samples are pushed in via `ingest(_:)` from the capture pipeline's tap.
        streamRunnerTask = Task.detached(priority: .userInitiated) { [weak transcriber] in
            guard let transcriber else { return }
            do {
                try await transcriber.startStreamTranscription()
            } catch {
                // WhisperKit logs internally; a clean error path from the detached task
                // is not part of the SpeechTranscribing contract.
            }
        }
    }

    func stop() async {
        await stop(unloadModel: false)
    }

    private func stop(unloadModel: Bool) async {
        streamProcessor = nil

        await streamTranscriber?.stopStreamTranscription()
        streamRunnerTask?.cancel()
        streamRunnerTask = nil
        streamTranscriber = nil
        if unloadModel {
            whisperKit = nil
            loadedModelName = nil
        }
        streamStartedAt = nil
        lastConfirmedSegmentCount = 0
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

    private func handleState(
        _ state: AudioStreamTranscriber.State,
        configuredLanguage: SourceLanguage,
        onResult: @escaping @Sendable (SpeechRecognitionResult) -> Void
    ) {
        let confirmedSegments = state.confirmedSegments
        if confirmedSegments.count > lastConfirmedSegmentCount {
            let newSegments = confirmedSegments[lastConfirmedSegmentCount...]
            lastConfirmedSegmentCount = confirmedSegments.count

            for segment in newSegments {
                let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    continue
                }

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
        }

        let partialText = partialText(from: state)
        if !partialText.isEmpty, partialText != lastPartialText {
            lastPartialText = partialText
            onResult(
                SpeechRecognitionResult(
                    text: partialText,
                    language: configuredLanguage,
                    isFinal: false,
                    startedAt: nil,
                    endedAt: Date(),
                    words: recognizedWords(in: state.unconfirmedSegments)
                )
            )
        }
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

    private func partialText(from state: AudioStreamTranscriber.State) -> String {
        let segmentText = state.unconfirmedSegments
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !segmentText.isEmpty {
            return segmentText
        }

        let currentText = state.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        // WhisperKit sets `state.currentText = "Waiting for speech..."` as an internal
        // idle placeholder when the realtime loop has no audio to transcribe. That string
        // is not a transcript — filter it before it reaches the operator/audience UI.
        if currentText == "Waiting for speech..." {
            return ""
        }
        return currentText
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

