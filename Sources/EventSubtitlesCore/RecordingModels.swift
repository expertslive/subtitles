import Foundation

public struct CaptionSegmentRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let index: Int
    public let createdAt: Date
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval
    public let sourceText: String
    public let displayText: String
    public let mode: ProcessingMode
    public let sourceLanguage: SourceLanguage

    public init(
        id: UUID = UUID(),
        index: Int,
        createdAt: Date,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        sourceText: String,
        displayText: String,
        mode: ProcessingMode,
        sourceLanguage: SourceLanguage
    ) {
        self.id = id
        self.index = index
        self.createdAt = createdAt
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.sourceText = sourceText
        self.displayText = displayText
        self.mode = mode
        self.sourceLanguage = sourceLanguage
    }
}

public enum SRTFormatter {
    public static func format(_ segments: [CaptionSegmentRecord]) -> String {
        format(segments) { $0.displayText }
    }

    public static func formatSource(_ segments: [CaptionSegmentRecord]) -> String {
        format(segments) { $0.sourceText }
    }

    public static func formatDisplay(_ segments: [CaptionSegmentRecord]) -> String {
        format(segments) { $0.displayText }
    }

    public static func format(
        _ segments: [CaptionSegmentRecord],
        text: (CaptionSegmentRecord) -> String
    ) -> String {
        segments
            .map { segment in
                """
                \(segment.index)
                \(timestamp(segment.startSeconds)) --> \(timestamp(segment.endSeconds))
                \(text(segment))
                """
            }
            .joined(separator: "\n\n")
    }

    public static func timestamp(_ seconds: TimeInterval) -> String {
        let totalMilliseconds = max(0, Int((seconds * 1_000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let remainingSeconds = (totalMilliseconds % 60_000) / 1_000
        let milliseconds = totalMilliseconds % 1_000

        return String(
            format: "%02d:%02d:%02d,%03d",
            hours,
            minutes,
            remainingSeconds,
            milliseconds
        )
    }
}
