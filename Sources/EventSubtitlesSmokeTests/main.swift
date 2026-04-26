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

testComposerKeepsOnlyConfiguredNumberOfLines()
testComposerNormalizesWhitespace()
testGlossaryCorrectorAppliesCaseInsensitiveCorrections()
testSRTFormatterProducesExpectedTimestamp()
testSRTFormatterCanExportSourceAndDisplayTracks()

print("Smoke tests passed")
