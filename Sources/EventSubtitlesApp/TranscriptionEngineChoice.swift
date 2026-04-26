import Foundation

enum TranscriptionEngineChoice: String, CaseIterable, Identifiable {
    case simulator
    case whisperKit
    case audioOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .simulator:
            "Simulator"
        case .whisperKit:
            "WhisperKit"
        case .audioOnly:
            "Audio only"
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
}
