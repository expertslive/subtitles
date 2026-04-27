import EventSubtitlesCore
import Foundation
@preconcurrency import WhisperKit

final class WhisperKitTranscriber: SpeechTranscribing, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private var streamTranscriber: AudioStreamTranscriber?
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

        let decodeOptions = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: whisperLanguageCode(for: configuration.sourceLanguage),
            usePrefillPrompt: configuration.sourceLanguage != .automatic,
            detectLanguage: configuration.sourceLanguage == .automatic,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: false,
            chunkingStrategy: .vad
        )

        let transcriber = AudioStreamTranscriber(
            audioEncoder: kit.audioEncoder,
            featureExtractor: kit.featureExtractor,
            segmentSeeker: kit.segmentSeeker,
            textDecoder: kit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: kit.audioProcessor,
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
    }

    func stop() async {
        await stop(unloadModel: false)
    }

    private func stop(unloadModel: Bool) async {
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
                        endedAt: absoluteDate(for: segment.end)
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
                    endedAt: Date()
                )
            )
        }
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

    var errorDescription: String? {
        switch self {
        case .tokenizerUnavailable:
            "WhisperKit tokenizer was not loaded."
        }
    }
}
