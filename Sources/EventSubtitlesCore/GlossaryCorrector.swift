import Foundation

public struct GlossaryCorrector: Sendable {
    private let replacements: [(pattern: String, replacement: String)]

    public init(rawGlossary: String) {
        replacements = rawGlossary
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                    return nil
                }

                if let separator = trimmed.range(of: "=>") {
                    let left = trimmed[..<separator.lowerBound]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let right = trimmed[separator.upperBound...]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !left.isEmpty, !right.isEmpty else {
                        return nil
                    }
                    return (String(left), String(right))
                }

                return (trimmed, trimmed)
            }
    }

    public func apply(to text: String) -> String {
        replacements.reduce(text) { current, replacement in
            current.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: replacement.pattern))\\b",
                with: replacement.replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }
}
