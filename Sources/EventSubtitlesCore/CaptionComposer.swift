import Foundation

public struct CaptionComposer: Sendable {
    public var maxLines: Int
    public var targetCharactersPerLine: Int

    public init(maxLines: Int = 2, targetCharactersPerLine: Int = 42) {
        self.maxLines = max(1, maxLines)
        self.targetCharactersPerLine = max(12, targetCharactersPerLine)
    }

    public func compose(_ text: String) -> CaptionLayout {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return CaptionLayout(lines: [])
        }

        let wrapped = wrap(normalized)
        return CaptionLayout(lines: Array(wrapped.suffix(maxLines)))
    }

    private func wrap(_ text: String) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        var lines: [String] = []
        var current = ""

        for word in words {
            if word.count > targetCharactersPerLine {
                if !current.isEmpty {
                    lines.append(current)
                    current = ""
                }
                lines.append(contentsOf: splitLongWord(word))
                continue
            }

            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= targetCharactersPerLine {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }

        if !current.isEmpty {
            lines.append(current)
        }

        return rebalance(lines)
    }

    private func splitLongWord(_ word: String) -> [String] {
        var chunks: [String] = []
        var remaining = word

        while !remaining.isEmpty {
            let end = remaining.index(
                remaining.startIndex,
                offsetBy: min(targetCharactersPerLine, remaining.count)
            )
            chunks.append(String(remaining[..<end]))
            remaining = String(remaining[end...])
        }

        return chunks
    }

    private func rebalance(_ lines: [String]) -> [String] {
        guard lines.count == 2 else {
            return lines
        }

        let firstWords = lines[0].split(separator: " ").map(String.init)
        let secondWords = lines[1].split(separator: " ").map(String.init)
        guard firstWords.count > 1 else {
            return lines
        }

        let imbalance = lines[0].count - lines[1].count
        guard imbalance > 14 else {
            return lines
        }

        let moved = firstWords.suffix(1)
        let newFirst = firstWords.dropLast().joined(separator: " ")
        let newSecond = (moved + secondWords).joined(separator: " ")

        guard newSecond.count <= targetCharactersPerLine else {
            return lines
        }

        return [newFirst, newSecond]
    }
}
