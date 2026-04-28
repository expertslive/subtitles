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

testComposerKeepsOnlyConfiguredNumberOfLines()
testComposerNormalizesWhitespace()
testGlossaryCorrectorAppliesCaseInsensitiveCorrections()
testSRTFormatterProducesExpectedTimestamp()
testSRTFormatterCanExportSourceAndDisplayTracks()
testCaptionStabilityHidesUnstableSuffix()
testCaptionStabilityFlushesIdleTail()
testCaptionStabilityContinuesAfterIdleFlush()
testCaptionSchedulerRespectsMinimumHold()

print("Smoke tests passed")
