import SwiftUI

enum WorkspaceGroup: String, CaseIterable, Identifiable {
    case event = "Event"
    case hardware = "Hardware"
    case session = "Session"

    var id: String { rawValue }
}

enum OperatorWorkspace: String, CaseIterable, Identifiable, Hashable {
    case live
    case style
    case glossary
    case translation
    case audio
    case models
    case output
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .style: "Style"
        case .glossary: "Glossary"
        case .translation: "Translation"
        case .audio: "Audio"
        case .models: "Models"
        case .output: "Output"
        case .logs: "Logs"
        }
    }

    var systemImage: String {
        switch self {
        case .live: "captions.bubble"
        case .style: "textformat.size"
        case .glossary: "list.bullet.rectangle"
        case .translation: "arrow.left.arrow.right"
        case .audio: "waveform"
        case .models: "cpu"
        case .output: "display"
        case .logs: "folder"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .live: "1"
        case .style: "2"
        case .glossary: "3"
        case .translation: "4"
        case .audio: "5"
        case .models: "6"
        case .output: "7"
        case .logs: "8"
        }
    }

    var group: WorkspaceGroup {
        switch self {
        case .live, .style, .glossary, .translation:
            .event
        case .audio, .models, .output:
            .hardware
        case .logs:
            .session
        }
    }
}
