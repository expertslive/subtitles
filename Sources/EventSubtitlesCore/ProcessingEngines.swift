import Foundation

public struct SpeechEngineConfiguration: Equatable, Sendable {
    public var sourceLanguage: SourceLanguage
    public var sampleRate: Double
    public var glossary: String

    public init(
        sourceLanguage: SourceLanguage = .automatic,
        sampleRate: Double = 16_000,
        glossary: String = ""
    ) {
        self.sourceLanguage = sourceLanguage
        self.sampleRate = sampleRate
        self.glossary = glossary
    }
}

public struct SpeechRecognitionResult: Equatable, Sendable {
    public let text: String
    public let language: SourceLanguage
    public let isFinal: Bool
    public let startedAt: Date?
    public let endedAt: Date?

    public init(
        text: String,
        language: SourceLanguage,
        isFinal: Bool,
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.text = text
        self.language = language
        self.isFinal = isFinal
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public protocol SpeechTranscribing: Sendable {
    func start(
        configuration: SpeechEngineConfiguration,
        onResult: @escaping @Sendable (SpeechRecognitionResult) -> Void
    ) async throws

    func stop() async
}

public struct TranslationRequest: Equatable, Sendable {
    public let text: String
    public let mode: ProcessingMode
    public let glossary: String

    public init(text: String, mode: ProcessingMode, glossary: String = "") {
        self.text = text
        self.mode = mode
        self.glossary = glossary
    }
}

public protocol TextTranslating: Sendable {
    func translate(_ request: TranslationRequest) async throws -> String
}
