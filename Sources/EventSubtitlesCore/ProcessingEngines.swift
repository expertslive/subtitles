import Foundation

public struct SpeechEngineConfiguration: Equatable, Sendable {
    public var sourceLanguage: SourceLanguage
    public var sampleRate: Double
    public var glossary: String
    public var sessionName: String

    public init(
        sourceLanguage: SourceLanguage = .automatic,
        sampleRate: Double = 16_000,
        glossary: String = "",
        sessionName: String = ""
    ) {
        self.sourceLanguage = sourceLanguage
        self.sampleRate = sampleRate
        self.glossary = glossary
        self.sessionName = sessionName
    }
}

public enum SpeechPromptBuilder {
    /// Builds a free-text Whisper prompt from the operator's session name and glossary.
    /// Whisper's prompt window holds ~224 BPE tokens; the caller is expected to encode and
    /// truncate to that limit. We keep the builder text-only and deterministic so it is unit-testable.
    public static func promptText(sessionName: String, glossary: String, maxCharacters: Int = 1_000) -> String {
        let trimmedName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)

        let glossaryTerms: [String] = glossary
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#") else {
                    return nil
                }
                if let range = line.range(of: "=>") {
                    return line[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return line
            }
            .filter { !$0.isEmpty }

        var parts: [String] = []
        if !trimmedName.isEmpty {
            parts.append("Event: \(trimmedName).")
        }
        if !glossaryTerms.isEmpty {
            parts.append("Vocabulary: \(glossaryTerms.joined(separator: ", ")).")
        }

        let joined = parts.joined(separator: " ")
        guard joined.count > maxCharacters else {
            return joined
        }
        let truncated = joined.prefix(maxCharacters)
        return String(truncated)
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
