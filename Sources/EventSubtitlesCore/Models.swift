import Foundation

public enum SourceLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case english
    case dutch

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .automatic: "Automatic"
        case .english: "English"
        case .dutch: "Dutch"
        }
    }
}

public enum ProcessingMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case subtitlesOnly
    case englishToDutch
    case dutchToEnglish

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .subtitlesOnly: "Subtitles only"
        case .englishToDutch: "English -> Dutch"
        case .dutchToEnglish: "Dutch -> English"
        }
    }

    public var sourceLanguage: SourceLanguage {
        switch self {
        case .subtitlesOnly: .automatic
        case .englishToDutch: .english
        case .dutchToEnglish: .dutch
        }
    }
}

public struct TranscriptEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceText: String
    public let displayText: String
    public let isFinal: Bool
    public let createdAt: Date
    public let startedAt: Date?
    public let endedAt: Date?

    public init(
        id: UUID = UUID(),
        sourceText: String,
        displayText: String,
        isFinal: Bool,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.sourceText = sourceText
        self.displayText = displayText
        self.isFinal = isFinal
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct CaptionLayout: Equatable, Sendable {
    public let lines: [String]

    public init(lines: [String]) {
        self.lines = lines
    }

    public var text: String {
        lines.joined(separator: "\n")
    }
}

public struct RecognizedWord: Equatable, Sendable {
    public let text: String
    public let normalized: String
    public let probability: Float
    public let startSeconds: Double?
    public let endSeconds: Double?

    public init(
        text: String,
        normalized: String? = nil,
        probability: Float,
        startSeconds: Double? = nil,
        endSeconds: Double? = nil
    ) {
        self.text = text
        self.normalized = normalized ?? text
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
        self.probability = probability
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}
