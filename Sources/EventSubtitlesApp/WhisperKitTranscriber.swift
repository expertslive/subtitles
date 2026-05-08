@preconcurrency import AVFoundation
import EventSubtitlesCore
import Foundation
@preconcurrency import WhisperKit

final class WhisperKitTranscriber: SpeechTranscribing, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private var streamTranscriber: AudioStreamTranscriber?
    private var streamProcessor: StreamFedAudioProcessor?
    private var sampleFeederTask: Task<Void, Never>?
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

    func start(
        configuration: SpeechEngineConfiguration,
        onResult: @escaping @Sendable (SpeechRecognitionResult) -> Void
    ) async throws {
        // Protocol conformance fallback — should not be called in the unified pipeline path.
        // Throws to make a misuse loud rather than silently launching with no audio.
        throw WhisperKitTranscriberError.streamNotProvided
    }

    func start(
        sampleStream: AsyncStream<[Float]>,
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

        let promptText = SpeechPromptBuilder.promptText(
            sessionName: configuration.sessionName,
            glossary: configuration.glossary
        )
        let promptTokens: [Int]? = promptText.isEmpty
            ? nil
            : Array(tokenizer.encode(text: " " + promptText).suffix(224))

        let decodeOptions = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: whisperLanguageCode(for: configuration.sourceLanguage),
            usePrefillPrompt: true,
            detectLanguage: configuration.sourceLanguage == .automatic,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            promptTokens: promptTokens,
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
        try await transcriber.startStreamTranscription()

        // Pump samples from AudioCapturePipeline into the processor, on a background task.
        sampleFeederTask = Task.detached(priority: .userInitiated) { [weak processor] in
            for await chunk in sampleStream {
                guard !Task.isCancelled else { break }
                processor?.ingest(chunk)
            }
        }
    }

    func stop() async {
        await stop(unloadModel: false)
    }

    private func stop(unloadModel: Bool) async {
        sampleFeederTask?.cancel()
        sampleFeederTask = nil
        streamProcessor = nil

        await streamTranscriber?.stopStreamTranscription()
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

        return state.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
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
    case streamNotProvided

    var errorDescription: String? {
        switch self {
        case .tokenizerUnavailable:
            "WhisperKit tokenizer was not loaded."
        case .streamNotProvided:
            "WhisperKit transcriber requires an audio sample stream."
        }
    }
}

