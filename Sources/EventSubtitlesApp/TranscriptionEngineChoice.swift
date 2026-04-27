import Foundation

enum TranscriptionEngineChoice: String, CaseIterable, Identifiable {
    case simulator
    case whisperKit
    case audioOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .simulator:
            "Demo captions"
        case .whisperKit:
            "Live subtitles"
        case .audioOnly:
            "Record audio only"
        }
    }

    var statusLabel: String {
        switch self {
        case .simulator:
            "Simulator running"
        case .whisperKit:
            "WhisperKit loading"
        case .audioOnly:
            "Audio recording only"
        }
    }

    var idleStatusLabel: String {
        switch self {
        case .simulator:
            "Demo captions idle"
        case .whisperKit:
            "WhisperKit ready"
        case .audioOnly:
            "Audio recorder idle"
        }
    }

    var helpText: String {
        switch self {
        case .simulator:
            "Uses generated demo captions for testing the screen layout."
        case .whisperKit:
            "Transcribes the stage audio locally and shows live captions."
        case .audioOnly:
            "Records the session audio without creating live captions."
        }
    }
}
