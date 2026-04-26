import Foundation

enum TranslationEngineChoice: String, CaseIterable, Identifiable {
    case ruleBased
    case localCommand

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ruleBased:
            "Glossary/rules"
        case .localCommand:
            "Local command"
        }
    }
}
