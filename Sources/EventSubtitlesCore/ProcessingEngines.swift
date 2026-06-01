import Foundation

public struct SpeechEngineConfiguration: Equatable, Sendable {
    public var sourceLanguage: SourceLanguage
    public var sampleRate: Double
    public var glossary: String
    public var sessionName: String
    public var whisperDecodeSettings: WhisperDecodeSettings

    public init(
        sourceLanguage: SourceLanguage = .automatic,
        sampleRate: Double = 16_000,
        glossary: String = "",
        sessionName: String = "",
        whisperDecodeSettings: WhisperDecodeSettings = .eventSafeDefaults
    ) {
        self.sourceLanguage = sourceLanguage
        self.sampleRate = sampleRate
        self.glossary = glossary
        self.sessionName = sessionName
        self.whisperDecodeSettings = whisperDecodeSettings
    }
}

public struct WhisperDecodeSettings: Equatable, Codable, Sendable {
    public static let eventSafeDefaults = WhisperDecodeSettings(
        temperature: 0,
        temperatureFallbackCount: 0,
        temperatureFallbackIncrement: 0,
        liveDecodeWindowSeconds: 12,
        minimumDecodeAudioSeconds: 2
    )

    public var temperature: Double
    public var temperatureFallbackCount: Int
    public var temperatureFallbackIncrement: Double
    public var liveDecodeWindowSeconds: Double
    public var minimumDecodeAudioSeconds: Double

    public init(
        temperature: Double = 0,
        temperatureFallbackCount: Int = 0,
        temperatureFallbackIncrement: Double = 0,
        liveDecodeWindowSeconds: Double = 12,
        minimumDecodeAudioSeconds: Double = 2
    ) {
        self.temperature = Self.clamp(temperature, 0...0.8)
        self.temperatureFallbackCount = max(0, min(3, temperatureFallbackCount))
        self.temperatureFallbackIncrement = Self.clamp(temperatureFallbackIncrement, 0...0.3)
        self.liveDecodeWindowSeconds = Self.clamp(liveDecodeWindowSeconds, 6...20)
        self.minimumDecodeAudioSeconds = Self.clamp(minimumDecodeAudioSeconds, 1...4)
    }

    public func clamped() -> WhisperDecodeSettings {
        WhisperDecodeSettings(
            temperature: temperature,
            temperatureFallbackCount: temperatureFallbackCount,
            temperatureFallbackIncrement: temperatureFallbackIncrement,
            liveDecodeWindowSeconds: liveDecodeWindowSeconds,
            minimumDecodeAudioSeconds: minimumDecodeAudioSeconds
        )
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
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
    public let words: [RecognizedWord]

    public init(
        text: String,
        language: SourceLanguage,
        isFinal: Bool,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        words: [RecognizedWord] = []
    ) {
        self.text = text
        self.language = language
        self.isFinal = isFinal
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.words = words
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
