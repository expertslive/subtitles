import Foundation

public struct CaptionLineFitter: Sendable {
    /// Picks the newest logical lines whose combined visual line count fits in
    /// `maxVisualLines`. Older lines are dropped from the top. A single logical
    /// line longer than the budget is included anyway (better than nothing).
    /// `measureVisualLineCount` is injected so this stays Foundation-only.
    public static func pickVisibleLogicalLines(
        candidates: [String],
        maxVisualLines: Int,
        measureVisualLineCount: (String) -> Int
    ) -> [String] {
        guard !candidates.isEmpty, maxVisualLines > 0 else { return [] }
        var totalVisualLines = 0
        var picked: [String] = []
        for line in candidates.reversed() {
            let count = measureVisualLineCount(line)
            if !picked.isEmpty && totalVisualLines + count > maxVisualLines { break }
            picked.append(line)
            totalVisualLines += count
            if totalVisualLines >= maxVisualLines { break }
        }
        return picked.reversed()
    }
}
