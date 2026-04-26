import Foundation

public struct RuleBasedTranslator: Sendable {
    public init() {}

    public func translate(_ text: String, mode: ProcessingMode) -> String {
        switch mode {
        case .subtitlesOnly:
            text
        case .englishToDutch:
            replaceTerms(in: text, terms: [
                "welcome": "welkom",
                "conference": "conferentie",
                "deployment": "deployment",
                "database": "database",
                "latency": "latency",
                "security": "security",
                "cloud": "cloud",
                "developers": "ontwikkelaars",
                "model": "model",
                "models": "modellen",
                "real time": "real-time"
            ])
        case .dutchToEnglish:
            replaceTerms(in: text, terms: [
                "welkom": "welcome",
                "conferentie": "conference",
                "implementatie": "deployment",
                "database": "database",
                "latency": "latency",
                "beveiliging": "security",
                "ontwikkelaars": "developers",
                "model": "model",
                "modellen": "models",
                "real-time": "real time"
            ])
        }
    }

    private func replaceTerms(in text: String, terms: [String: String]) -> String {
        terms.reduce(text) { current, entry in
            current.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: entry.key))\\b",
                with: entry.value,
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }
}
