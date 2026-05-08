import Foundation

/// Greedy word-fill line builder. Accumulates phrases into a buffer and emits
/// completed lines when the next word would overflow `targetCharactersPerLine`,
/// when a final phrase arrives, or when no input has arrived for `idleFlushAfter`.
public struct LineBuilder: Sendable {
    public var targetCharactersPerLine: Int
    public private(set) var pendingBuffer: String = ""
    private var lastIngestAt: Date = .distantPast

    public init(targetCharactersPerLine: Int) {
        self.targetCharactersPerLine = max(8, targetCharactersPerLine)
    }

    public mutating func reset() {
        pendingBuffer = ""
        lastIngestAt = .distantPast
    }

    /// Force-flush the buffer and return its contents as a single line (or nil
    /// if the buffer is empty). Does not update `lastIngestAt`.
    @discardableResult
    public mutating func flushBuffer() -> String? {
        guard !pendingBuffer.isEmpty else { return nil }
        let line = pendingBuffer
        pendingBuffer = ""
        return line
    }

    /// Append a phrase. Returns any completed lines that overflow triggered.
    @discardableResult
    public mutating func ingest(_ phrase: String, now: Date) -> [String] {
        lastIngestAt = now
        return appendWords(in: phrase)
    }

    /// Append a final phrase and force-flush the buffer as a final line.
    @discardableResult
    public mutating func ingestFinal(_ phrase: String, now: Date) -> [String] {
        var emitted = ingest(phrase, now: now)
        if !pendingBuffer.isEmpty {
            emitted.append(pendingBuffer)
            pendingBuffer = ""
        }
        return emitted
    }

    /// Periodic tick. If the buffer has been idle for `idleFlushAfter`, flush it.
    @discardableResult
    public mutating func tick(now: Date, idleFlushAfter: TimeInterval) -> [String] {
        guard !pendingBuffer.isEmpty else { return [] }
        guard now.timeIntervalSince(lastIngestAt) >= idleFlushAfter else { return [] }
        let line = pendingBuffer
        pendingBuffer = ""
        return [line]
    }

    private mutating func appendWords(in phrase: String) -> [String] {
        var emitted: [String] = []
        let words = phrase
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        for word in words {
            if pendingBuffer.isEmpty {
                pendingBuffer = word
            } else if pendingBuffer.count + 1 + word.count <= targetCharactersPerLine {
                pendingBuffer += " " + word
            } else {
                emitted.append(pendingBuffer)
                pendingBuffer = word
            }
        }
        return emitted
    }
}

/// Fixed-capacity FIFO of visible lines plus a pending queue that drains when
/// the oldest visible line has been on screen for at least `lineMinHold`.
public struct LineStack: Sendable {
    public var maxLines: Int
    private var visible: [VisibleLine] = []
    private var pending: [String] = []

    public struct VisibleLine: Equatable, Sendable {
        public let text: String
        public let revealedAt: Date
    }

    public init(maxLines: Int) {
        self.maxLines = max(1, maxLines)
    }

    public var visibleLines: [String] {
        visible.map(\.text)
    }

    public var pendingCount: Int {
        pending.count
    }

    public mutating func reset() {
        visible.removeAll()
        pending.removeAll()
    }

    public mutating func push(_ line: String, now: Date) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if visible.count < maxLines {
            visible.append(VisibleLine(text: trimmed, revealedAt: now))
        } else {
            pending.append(trimmed)
        }
    }

    /// Drain as many pending lines as `lineMinHold` permits. Returns true if
    /// the visible set changed during this tick.
    @discardableResult
    public mutating func tick(now: Date, lineMinHold: TimeInterval) -> Bool {
        var changed = false
        while !pending.isEmpty {
            if visible.count < maxLines {
                visible.append(VisibleLine(text: pending.removeFirst(), revealedAt: now))
                changed = true
                continue
            }
            guard let oldest = visible.first else { break }
            if now.timeIntervalSince(oldest.revealedAt) >= lineMinHold {
                visible.removeFirst()
                visible.append(VisibleLine(text: pending.removeFirst(), revealedAt: now))
                changed = true
            } else {
                break
            }
        }
        return changed
    }
}

/// Orchestrates a `LineBuilder` and `LineStack` to produce the visible-line
/// snapshot for `.liveRollUp` mode.
public struct LinePacedRoller: Sendable {
    public var lineBuilder: LineBuilder
    public var lineStack: LineStack
    private var emittedSinceDrain: [String] = []

    public init(targetCharactersPerLine: Int, maxLines: Int) {
        self.lineBuilder = LineBuilder(targetCharactersPerLine: targetCharactersPerLine)
        self.lineStack = LineStack(maxLines: maxLines)
    }

    public var visibleLines: [String] {
        lineStack.visibleLines
    }

    public mutating func reset() {
        lineBuilder.reset()
        lineStack.reset()
        emittedSinceDrain.removeAll()
    }

    public mutating func updateLayout(targetCharactersPerLine: Int, maxLines: Int) {
        lineBuilder.targetCharactersPerLine = max(8, targetCharactersPerLine)
        lineStack.maxLines = max(1, maxLines)
    }

    /// Returns lines that the line builder has emitted since the last call,
    /// then clears the internal accumulator. Use this to record the displayed
    /// transcript history for the operator.
    public mutating func drainEmittedLines() -> [String] {
        let result = emittedSinceDrain
        emittedSinceDrain.removeAll()
        return result
    }

    /// Ingest a phrase from the stability engine. If the incoming phrase would
    /// not fit alongside the current buffer, the buffer is emitted first as a
    /// complete line (phrase-level overflow). Then the phrase is appended
    /// word-by-word to the fresh buffer. Pushes any completed lines onto the
    /// stack but does not advance the visible window — `tick` does that.
    public mutating func ingest(_ phrase: StableCaptionPhrase, now: Date) {
        // Phrase-level overflow: if appending the entire phrase would exceed the
        // target, flush the current buffer before processing the new phrase.
        let separator = lineBuilder.pendingBuffer.isEmpty ? "" : " "
        let combined = lineBuilder.pendingBuffer + separator + phrase.text
        if !lineBuilder.pendingBuffer.isEmpty && combined.count > lineBuilder.targetCharactersPerLine {
            if let flushed = lineBuilder.flushBuffer() {
                lineStack.push(flushed, now: now)
                emittedSinceDrain.append(flushed)
            }
        }
        let emitted: [String]
        if phrase.isFinal {
            emitted = lineBuilder.ingestFinal(phrase.text, now: now)
        } else {
            emitted = lineBuilder.ingest(phrase.text, now: now)
        }
        for line in emitted {
            lineStack.push(line, now: now)
            emittedSinceDrain.append(line)
        }
    }

    /// Drive the roller's clock. Runs idle-flush on the builder, then drains
    /// the line stack's pending queue. Returns true if the visible set changed.
    @discardableResult
    public mutating func tick(
        now: Date,
        lineMinHold: TimeInterval,
        idleFlushAfter: TimeInterval
    ) -> Bool {
        let flushed = lineBuilder.tick(now: now, idleFlushAfter: idleFlushAfter)
        for line in flushed {
            lineStack.push(line, now: now)
            emittedSinceDrain.append(line)
        }
        return lineStack.tick(now: now, lineMinHold: lineMinHold)
    }
}
