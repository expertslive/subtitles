import Darwin
import EventSubtitlesCore
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

private func testComposerKeepsOnlyConfiguredNumberOfLines() {
    let composer = CaptionComposer(maxLines: 2, targetCharactersPerLine: 20)
    let layout = composer.compose("This is a longer sentence that should wrap over several caption lines for readability.")

    expect(layout.lines.count == 2, "composer should keep only two lines")
    expect(layout.lines.allSatisfy { !$0.isEmpty }, "composer should not emit empty lines")
}

private func testComposerNormalizesWhitespace() {
    let composer = CaptionComposer(maxLines: 3, targetCharactersPerLine: 40)
    let layout = composer.compose("  Kubernetes\n\n   deployments    need predictable latency. ")

    expect(
        layout.text == "Kubernetes deployments need\npredictable latency.",
        "composer should normalize whitespace"
    )
}

private func testGlossaryCorrectorAppliesCaseInsensitiveCorrections() {
    let glossary = GlossaryCorrector(rawGlossary: """
    kubernetes => Kubernetes
    oauth => OAuth
    """)

    let corrected = glossary.apply(to: "Today we discuss kubernetes and OAUTH.")

    expect(corrected == "Today we discuss Kubernetes and OAuth.", "glossary should correct case-insensitively")
}

private func testSRTFormatterProducesExpectedTimestamp() {
    expect(SRTFormatter.timestamp(3_723.456) == "01:02:03,456", "SRT timestamp should use HH:MM:SS,mmm")
}

private func testSRTFormatterCanExportSourceAndDisplayTracks() {
    let segment = CaptionSegmentRecord(
        index: 1,
        createdAt: Date(timeIntervalSince1970: 0),
        startSeconds: 0,
        endSeconds: 2.5,
        sourceText: "Welcome developers.",
        displayText: "Welkom ontwikkelaars.",
        mode: .englishToDutch,
        sourceLanguage: .english
    )

    expect(SRTFormatter.formatSource([segment]).contains("Welcome developers."), "source SRT should use source text")
    expect(SRTFormatter.formatDisplay([segment]).contains("Welkom ontwikkelaars."), "display SRT should use display text")
}

private func testCaptionStabilityHidesUnstableSuffix() {
    var engine = CaptionStabilityEngine()
    let configuration = CaptionDisplayConfiguration(
        mode: .calmBlocks,
        stability: .calm,
        commitDelay: 1.0,
        unstableWordCount: 2,
        minimumHold: 1.2,
        maximumLatency: 3.0
    )
    let first = TranscriptSnapshot(
        text: "Hoe snel komt dit op het scherm",
        createdAt: Date(timeIntervalSince1970: 1),
        isFinal: false
    )
    let second = TranscriptSnapshot(
        text: "Hoe snel komt dit op het scherm vandaag",
        createdAt: Date(timeIntervalSince1970: 2),
        isFinal: false
    )

    expect(engine.ingest(first, configuration: configuration).isEmpty, "first partial should not publish immediately")
    let stable = engine.ingest(second, configuration: configuration)
    expect(stable.map(\.text) == ["Hoe snel komt dit op het"], "stability should hide the unstable suffix")
}

private func testCaptionStabilityFlushesIdleTail() {
    var engine = CaptionStabilityEngine()
    let configuration = CaptionDisplayConfiguration(
        mode: .calmBlocks,
        stability: .calm,
        commitDelay: 1.0,
        unstableWordCount: 2,
        minimumHold: 1.2,
        maximumLatency: 3.0
    )
    let snapshot = TranscriptSnapshot(
        text: "Dit moet na stilte alsnog verschijnen",
        createdAt: Date(timeIntervalSince1970: 1),
        isFinal: false
    )

    expect(engine.ingest(snapshot, configuration: configuration).isEmpty, "first partial should wait")
    let flushed = engine.flushPending(committedAt: Date(timeIntervalSince1970: 4))
    expect(
        flushed.map(\.text) == ["Dit moet na stilte alsnog verschijnen"],
        "idle flush should publish the last spoken sentence"
    )
}

private func testCaptionStabilityContinuesAfterIdleFlush() {
    var engine = CaptionStabilityEngine()
    let configuration = CaptionDisplayConfiguration(
        mode: .calmBlocks,
        stability: .balanced,
        commitDelay: 0.8,
        unstableWordCount: 1,
        minimumHold: 1.0,
        maximumLatency: 2.5
    )

    _ = engine.ingest(
        TranscriptSnapshot(text: "Eerste zin blijft niet hangen", createdAt: Date(timeIntervalSince1970: 1), isFinal: false),
        configuration: configuration
    )
    _ = engine.flushPending(committedAt: Date(timeIntervalSince1970: 4))
    expect(
        engine.ingest(
            TranscriptSnapshot(text: "Nieuwe zin begint rustig", createdAt: Date(timeIntervalSince1970: 5), isFinal: false),
            configuration: configuration
        ).isEmpty,
        "new partial after idle flush should start a fresh stability window"
    )
    let stable = engine.ingest(
        TranscriptSnapshot(text: "Nieuwe zin begint rustig verder", createdAt: Date(timeIntervalSince1970: 6), isFinal: false),
        configuration: configuration
    )
    expect(
        stable.map(\.text) == ["Nieuwe zin begint rustig"],
        "stability should continue publishing after an idle flush"
    )
}

private func testCaptionSchedulerRespectsMinimumHold() {
    var scheduler = CaptionDisplayScheduler()
    let configuration = CaptionDisplayConfiguration(
        mode: .calmBlocks,
        stability: .balanced,
        commitDelay: 0.5,
        unstableWordCount: 2,
        minimumHold: 2.0,
        maximumLatency: 3.0
    )
    let start = Date(timeIntervalSince1970: 10)

    scheduler.enqueue(sourceText: "First caption", displayText: "First caption", now: start)
    expect(
        scheduler.nextCueIfDue(now: start.addingTimeInterval(0.6), configuration: configuration) != nil,
        "scheduler should publish first cue after commit delay"
    )

    scheduler.enqueue(sourceText: "Second caption", displayText: "Second caption", now: start.addingTimeInterval(0.7))
    expect(
        scheduler.nextCueIfDue(now: start.addingTimeInterval(1.4), configuration: configuration) == nil,
        "scheduler should hold current cue for the minimum duration"
    )
    expect(
        scheduler.nextCueIfDue(now: start.addingTimeInterval(2.8), configuration: configuration) != nil,
        "scheduler should publish pending cue after the hold window"
    )
}

private func testStabilityEngineResetClearsCommittedPrefix() {
    var engine = CaptionStabilityEngine()
    let configuration = CaptionDisplayConfiguration(
        mode: .calmBlocks,
        stability: .balanced,
        commitDelay: 0.5,
        unstableWordCount: 2,
        minimumHold: 1.0,
        maximumLatency: 3.0
    )

    _ = engine.ingest(
        TranscriptSnapshot(text: "embarrassing first half", createdAt: Date(timeIntervalSince1970: 1), isFinal: false),
        configuration: configuration
    )
    _ = engine.ingest(
        TranscriptSnapshot(text: "embarrassing first half follow up", createdAt: Date(timeIntervalSince1970: 2), isFinal: false),
        configuration: configuration
    )

    engine.reset()

    let next = engine.ingest(
        TranscriptSnapshot(text: "embarrassing first half follow up", createdAt: Date(timeIntervalSince1970: 3), isFinal: false),
        configuration: configuration
    )
    expect(next.isEmpty, "after reset, the previously committed prefix must not re-publish on the next partial")
}

private func testStabilityCommitsHighConfidenceWordsImmediately() {
    var engine = CaptionStabilityEngine()
    let configuration = CaptionDisplayConfiguration(
        mode: .calmBlocks,
        stability: .calm,
        commitDelay: 1.0,
        unstableWordCount: 2,
        minimumHold: 1.2,
        maximumLatency: 3.0
    )

    let words: [RecognizedWord] = [
        RecognizedWord(text: "Welcome", probability: 0.95),
        RecognizedWord(text: "to", probability: 0.92),
        RecognizedWord(text: "the", probability: 0.90),
        RecognizedWord(text: "stage", probability: 0.85),
        RecognizedWord(text: "everyone", probability: 0.40),
        RecognizedWord(text: "today", probability: 0.30)
    ]
    let snapshot = TranscriptSnapshot(
        text: "Welcome to the stage everyone today",
        createdAt: Date(timeIntervalSince1970: 1),
        isFinal: false,
        words: words
    )

    let phrases = engine.ingest(snapshot, configuration: configuration)
    expect(
        phrases.map(\.text) == ["Welcome to the stage"],
        "first 4 high-confidence words should commit on first snapshot; trailing low-confidence words held"
    )
}

private func testStabilityHoldsLowConfidenceWordsUntilAgreement() {
    var engine = CaptionStabilityEngine()
    let configuration = CaptionDisplayConfiguration(
        mode: .calmBlocks,
        stability: .calm,
        commitDelay: 1.0,
        unstableWordCount: 2,
        minimumHold: 1.2,
        maximumLatency: 3.0
    )

    let firstWords: [RecognizedWord] = [
        RecognizedWord(text: "Maybe", probability: 0.45),
        RecognizedWord(text: "Cubernetes", probability: 0.40)
    ]
    let firstPhrases = engine.ingest(
        TranscriptSnapshot(text: "Maybe Cubernetes", createdAt: Date(timeIntervalSince1970: 1), isFinal: false, words: firstWords),
        configuration: configuration
    )
    expect(firstPhrases.isEmpty, "low-confidence partial should not commit")

    let secondWords: [RecognizedWord] = [
        RecognizedWord(text: "Maybe", probability: 0.50),
        RecognizedWord(text: "Kubernetes", probability: 0.55),
        RecognizedWord(text: "deploys", probability: 0.45)
    ]
    let secondPhrases = engine.ingest(
        TranscriptSnapshot(text: "Maybe Kubernetes deploys", createdAt: Date(timeIntervalSince1970: 2), isFinal: false, words: secondWords),
        configuration: configuration
    )
    expect(
        secondPhrases.map(\.text) == ["Maybe"],
        "only words that agree across snapshots commit when confidence is low"
    )
}

private func testStabilityFallsBackToPrefixOnlyWhenWordsMissing() {
    var engine = CaptionStabilityEngine()
    let configuration = CaptionDisplayConfiguration(
        mode: .calmBlocks,
        stability: .calm,
        commitDelay: 1.0,
        unstableWordCount: 2,
        minimumHold: 1.2,
        maximumLatency: 3.0
    )

    expect(
        engine.ingest(
            TranscriptSnapshot(text: "manual caption text", createdAt: Date(timeIntervalSince1970: 1), isFinal: false),
            configuration: configuration
        ).isEmpty,
        "first snapshot without words holds for prefix agreement"
    )
    let phrases = engine.ingest(
        TranscriptSnapshot(text: "manual caption text continued", createdAt: Date(timeIntervalSince1970: 2), isFinal: false),
        configuration: configuration
    )
    expect(
        phrases.map(\.text) == ["manual caption"],
        "without words, behavior matches the prior prefix-only stability rule"
    )
}

private func testLineBuilderEmitsCompletedLineWhenBufferFull() {
    var builder = LineBuilder(targetCharactersPerLine: 20)
    let now = Date(timeIntervalSince1970: 1)

    let emitted1 = builder.ingest("Welcome to the stage", now: now)
    expect(emitted1.isEmpty, "first phrase fits and should not emit")

    let emitted2 = builder.ingest("everyone today", now: now.addingTimeInterval(0.5))
    expect(
        emitted2 == ["Welcome to the stage"],
        "next word would overflow → emit completed line at the word boundary"
    )

    expect(builder.pendingBuffer == "everyone today", "remaining words form the new buffer")
}

private func testLineBuilderFlushesOnFinalSegment() {
    var builder = LineBuilder(targetCharactersPerLine: 50)
    let now = Date(timeIntervalSince1970: 1)
    _ = builder.ingest("Half a sentence", now: now)
    let emitted = builder.ingestFinal("done.", now: now.addingTimeInterval(0.2))
    expect(
        emitted == ["Half a sentence done."],
        "final segment must flush the buffer even if not full"
    )
    expect(builder.pendingBuffer.isEmpty, "buffer is empty after final flush")
}

private func testLineBuilderIdleFlushAfterTimeout() {
    var builder = LineBuilder(targetCharactersPerLine: 50)
    let start = Date(timeIntervalSince1970: 1)
    _ = builder.ingest("Trailing words", now: start)

    let earlyTick = builder.tick(now: start.addingTimeInterval(1.0), idleFlushAfter: 1.5)
    expect(earlyTick.isEmpty, "tick before idle threshold does not flush")

    let lateTick = builder.tick(now: start.addingTimeInterval(1.6), idleFlushAfter: 1.5)
    expect(lateTick == ["Trailing words"], "tick after idle threshold flushes the buffer")
    expect(builder.pendingBuffer.isEmpty, "buffer cleared after idle flush")
}

private func testLineStackHoldsBeforeScrolling() {
    var stack = LineStack(maxLines: 2)
    let t0 = Date(timeIntervalSince1970: 100)

    stack.push("First", now: t0)
    expect(stack.visibleLines == ["First"], "stack fills below capacity immediately")

    stack.push("Second", now: t0.addingTimeInterval(0.1))
    expect(stack.visibleLines == ["First", "Second"], "second line fills the stack")

    stack.push("Third", now: t0.addingTimeInterval(0.5))
    _ = stack.tick(now: t0.addingTimeInterval(0.6), lineMinHold: 2.0)
    expect(
        stack.visibleLines == ["First", "Second"],
        "stack is full and oldest line not yet held long enough → 'Third' stays queued"
    )

    _ = stack.tick(now: t0.addingTimeInterval(2.2), lineMinHold: 2.0)
    expect(
        stack.visibleLines == ["Second", "Third"],
        "after lineMinHold elapses, oldest scrolls off and queued line enters"
    )
}

private func testLineStackRespectsMaxLines() {
    var stack = LineStack(maxLines: 2)
    let t0 = Date(timeIntervalSince1970: 100)
    stack.push("A", now: t0)
    stack.push("B", now: t0.addingTimeInterval(0.1))
    expect(stack.visibleLines == ["A", "B"], "stack at capacity")
    expect(stack.pendingCount == 0, "no queue while filling")
}

private func testLinePacedRollerIntegration() {
    var roller = LinePacedRoller(targetCharactersPerLine: 24, maxLines: 2)
    let t0 = Date(timeIntervalSince1970: 1000)

    // Phrase 1: short, doesn't fill the line
    roller.ingest(StableCaptionPhrase(text: "Hello to everyone", committedAt: t0, isFinal: false), now: t0)
    _ = roller.tick(now: t0.addingTimeInterval(0.1), lineMinHold: 2.0, idleFlushAfter: 1.5)
    expect(roller.visibleLines.isEmpty, "phrase pending in builder, no line emitted yet")

    // Phrase 2: pushes us past 24 chars → emits "Hello to everyone"
    roller.ingest(StableCaptionPhrase(text: "and welcome to the stage", committedAt: t0.addingTimeInterval(0.5), isFinal: false), now: t0.addingTimeInterval(0.5))
    _ = roller.tick(now: t0.addingTimeInterval(0.6), lineMinHold: 2.0, idleFlushAfter: 1.5)
    expect(
        roller.visibleLines == ["Hello to everyone"],
        "first overflowed line appears immediately while stack has room"
    )

    // Idle flush emits the trailing buffer
    _ = roller.tick(now: t0.addingTimeInterval(2.5), lineMinHold: 2.0, idleFlushAfter: 1.5)
    expect(
        roller.visibleLines == ["Hello to everyone", "and welcome to the stage"],
        "idle flush emits second line and stack fills"
    )
}

testComposerKeepsOnlyConfiguredNumberOfLines()
testComposerNormalizesWhitespace()
testGlossaryCorrectorAppliesCaseInsensitiveCorrections()
testSRTFormatterProducesExpectedTimestamp()
testSRTFormatterCanExportSourceAndDisplayTracks()
testCaptionStabilityHidesUnstableSuffix()
testCaptionStabilityFlushesIdleTail()
testCaptionStabilityContinuesAfterIdleFlush()
testCaptionSchedulerRespectsMinimumHold()
testStabilityEngineResetClearsCommittedPrefix()
testStabilityCommitsHighConfidenceWordsImmediately()
testStabilityHoldsLowConfidenceWordsUntilAgreement()
testStabilityFallsBackToPrefixOnlyWhenWordsMissing()
testLineBuilderEmitsCompletedLineWhenBufferFull()
testLineBuilderFlushesOnFinalSegment()
testLineBuilderIdleFlushAfterTimeout()
testLineStackHoldsBeforeScrolling()
testLineStackRespectsMaxLines()
testLinePacedRollerIntegration()

print("Smoke tests passed")
