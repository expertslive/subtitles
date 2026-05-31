import Foundation

public enum StreamDeckStatusPolicy {
    public static let captionActiveDuration: TimeInterval = 2
    public static let audioSignalThreshold = 0.05
    public static let audioGraceDuration: TimeInterval = 10

    public static func captionState(
        text: String,
        lastActivityAt: Date?,
        now: Date
    ) -> StreamDeckCaptionState {
        guard !text.isEmpty else {
            return .clear
        }
        guard let lastActivityAt,
              now.timeIntervalSince(lastActivityAt) < captionActiveDuration
        else {
            return .idle
        }
        return .active
    }

    public static func audioState(
        isRunning: Bool,
        isDemo: Bool,
        isSelectedInputAvailable: Bool,
        hasAudioFailure: Bool,
        audioLevel: Double,
        lastAudibleInputAt: Date?,
        sessionStartedAt: Date?,
        now: Date
    ) -> StreamDeckAudioState {
        if !isSelectedInputAvailable || hasAudioFailure {
            return .warning
        }
        guard isRunning, !isDemo else {
            return .unknown
        }
        let heardRecently = lastAudibleInputAt.map { audibleAt in
            let isInCurrentSession = sessionStartedAt.map { audibleAt >= $0 } ?? true
            return isInCurrentSession && now.timeIntervalSince(audibleAt) < audioGraceDuration
        } ?? false
        if audioLevel > audioSignalThreshold ||
            heardRecently {
            return .healthy
        }
        if sessionStartedAt.map({ now.timeIntervalSince($0) < audioGraceDuration }) == true {
            return .unknown
        }
        return .silent
    }

    public static func errorSummary(_ errorMessage: String?) -> String? {
        guard let errorMessage else {
            return nil
        }
        let normalized = errorMessage
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else {
            return nil
        }
        let label = normalized.split(separator: ":", maxSplits: 1).first.map(String.init) ?? normalized
        if allowedErrorSummaries.contains(label) {
            return label
        }
        return "App error"
    }

    private static let allowedErrorSummaries: Set<String> = [
        "App unavailable",
        "App error",
        "Audio capture unavailable",
        "Audio capture restart failed",
        "Audio device changed",
        "Audio test recording failed",
        "Glossary export failed",
        "Glossary import failed",
        "Session log save failed",
        "Session log unavailable",
        "Sleep prevention unavailable",
        "Transcription unavailable",
        "Translation failed",
        "WhisperKit model prepare failed",
        "WhisperKit unavailable"
    ]
}
