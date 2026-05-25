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
        hasAvailableInput: Bool,
        audioLevel: Double,
        lastAudibleInputAt: Date?,
        sessionStartedAt: Date?,
        errorMessage: String?,
        now: Date
    ) -> StreamDeckAudioState {
        if !hasAvailableInput || containsAudioFailure(errorMessage) {
            return .warning
        }
        guard isRunning, !isDemo else {
            return .unknown
        }
        if audioLevel > audioSignalThreshold ||
            lastAudibleInputAt.map({ now.timeIntervalSince($0) < audioGraceDuration }) == true {
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
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }
        return String(normalized.prefix(120))
    }

    private static func containsAudioFailure(_ errorMessage: String?) -> Bool {
        guard let errorMessage else {
            return false
        }
        let normalized = errorMessage.lowercased()
        return normalized.contains("audio capture") || normalized.contains("audio input")
    }
}
