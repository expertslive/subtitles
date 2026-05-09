import Foundation

public enum CaptionTickScheduler {
    /// Returns the earliest non-nil date in `deadlines`, or `fallback` if all are nil.
    /// Used by AppState to decide when to schedule the next caption pipeline tick
    /// instead of polling on a wall clock.
    public static func nearestDeadline(from deadlines: [Date?], fallback: Date) -> Date {
        let nonNil = deadlines.compactMap { $0 }
        return nonNil.min() ?? fallback
    }
}
