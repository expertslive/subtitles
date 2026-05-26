import EventSubtitlesCore
import Foundation

@discardableResult
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) -> Bool {
    guard actual == expected else {
        fputs("FAIL: \(message). Expected \(expected), got \(actual)\n", stderr)
        return false
    }
    return true
}

func testSystemDefaultModeUsesDefaultDevice() -> Bool {
    let defaultDevice = AudioInputSelectionDevice(id: "built-in", name: "MacBook Pro Microphone")
    let result = AudioInputSelectionResolver.resolve(
        selectedDeviceID: nil,
        devices: [
            defaultDevice,
            AudioInputSelectionDevice(id: "scarlett", name: "Scarlett 2i2")
        ],
        defaultDeviceID: "built-in"
    )

    return expectEqual(result.effectiveDeviceID, "built-in", "system default effective device") &&
        expectEqual(result.status, .usingSystemDefault, "system default status")
}

func testAvailableOverrideWinsOverDefaultDevice() -> Bool {
    let result = AudioInputSelectionResolver.resolve(
        selectedDeviceID: "scarlett",
        devices: [
            AudioInputSelectionDevice(id: "built-in", name: "MacBook Pro Microphone"),
            AudioInputSelectionDevice(id: "scarlett", name: "Scarlett 2i2")
        ],
        defaultDeviceID: "built-in"
    )

    return expectEqual(result.effectiveDeviceID, "scarlett", "override effective device") &&
        expectEqual(result.status, .usingOverride, "override status")
}

func testUnavailableOverrideFallsBackToDefaultDevice() -> Bool {
    let result = AudioInputSelectionResolver.resolve(
        selectedDeviceID: "scarlett",
        devices: [
            AudioInputSelectionDevice(id: "built-in", name: "MacBook Pro Microphone")
        ],
        defaultDeviceID: "built-in"
    )

    return expectEqual(result.effectiveDeviceID, "built-in", "unavailable override fallback device") &&
        expectEqual(result.status, .overrideUnavailable, "unavailable override status")
}

func testPromptBuilderIncludesSessionAndGlossaryTerms() -> Bool {
    let prompt = SpeechPromptBuilder.promptText(
        sessionName: "Wortell Summit",
        glossary: """
        kubernetes => Kubernetes
        oauth => OAuth
        # comment
        """
    )
    return expectEqual(
        prompt,
        "Event: Wortell Summit. Vocabulary: kubernetes, oauth.",
        "prompt builder should include session and ignore comments"
    )
}

func testPromptBuilderDropsEmptyParts() -> Bool {
    return expectEqual(
        SpeechPromptBuilder.promptText(sessionName: "", glossary: ""),
        "",
        "empty inputs produce empty prompt"
    ) && expectEqual(
        SpeechPromptBuilder.promptText(sessionName: "  ", glossary: "kubernetes => Kubernetes"),
        "Vocabulary: kubernetes.",
        "blank session name is omitted"
    )
}

func testPromptBuilderTruncatesAtCharacterLimit() -> Bool {
    let bigGlossary = (1...500).map { "term\($0) => Term\($0)" }.joined(separator: "\n")
    let prompt = SpeechPromptBuilder.promptText(sessionName: "Show", glossary: bigGlossary, maxCharacters: 100)
    return expectEqual(prompt.count, 100, "prompt should be truncated to maxCharacters")
}

func testSRTAppendingMatchesFullFormat() -> Bool {
    let segments = [
        CaptionSegmentRecord(
            index: 1, createdAt: Date(timeIntervalSince1970: 0),
            startSeconds: 0, endSeconds: 1.5,
            sourceText: "First", displayText: "First",
            mode: .subtitlesOnly, sourceLanguage: .english
        ),
        CaptionSegmentRecord(
            index: 2, createdAt: Date(timeIntervalSince1970: 2),
            startSeconds: 2.0, endSeconds: 3.5,
            sourceText: "Second", displayText: "Second",
            mode: .subtitlesOnly, sourceLanguage: .english
        )
    ]

    let appended = segments
        .map { SRTFormatter.cue(for: $0, useDisplayText: true) }
        .joined()
    let regenerated = SRTFormatter.formatDisplay(segments)

    let normalize: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    return expectEqual(
        normalize(appended),
        normalize(regenerated),
        "appending per-cue strings should produce the same SRT body as full regeneration"
    )
}

private func testCaptionTickSchedulerComputesNearestDeadline() -> Bool {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let soonest = now.addingTimeInterval(0.8)
    let deadlines: [Date?] = [
        soonest,                        // queued cue due in 0.8s
        now.addingTimeInterval(1.5),    // line-min-hold expiry in 1.5s
        nil,                            // idle-flush not pending
        now.addingTimeInterval(5.0)     // auto-clear in 5s
    ]
    let nearest = CaptionTickScheduler.nearestDeadline(from: deadlines, fallback: now.addingTimeInterval(60))
    return expectEqual(nearest, soonest, "nearest deadline picks smallest non-nil")
}

private func testCaptionTickSchedulerUsesFallbackWhenAllNil() -> Bool {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let fallback = now.addingTimeInterval(60)
    let nearest = CaptionTickScheduler.nearestDeadline(from: [nil, nil, nil], fallback: fallback)
    return expectEqual(nearest, fallback, "all-nil deadlines fall back to provided default")
}

private func testCaptionLineFitterPicksNewestThatFit() -> Bool {
    let candidates = ["A", "B", "C", "D", "E"]
    // Each line takes 1 visual line; budget is 2.
    let picked = CaptionLineFitter.pickVisibleLogicalLines(
        candidates: candidates,
        maxVisualLines: 2,
        measureVisualLineCount: { _ in 1 }
    )
    return expectEqual(picked, ["D", "E"], "picks newest two when each is one visual line")
}

private func testCaptionLineFitterIncludesOversizedSingleLine() -> Bool {
    let picked = CaptionLineFitter.pickVisibleLogicalLines(
        candidates: ["short", "huge wraps to four"],
        maxVisualLines: 2,
        measureVisualLineCount: { $0 == "huge wraps to four" ? 4 : 1 }
    )
    return expectEqual(picked, ["huge wraps to four"], "oversized newest line included alone")
}

private func readSource(_ relativePath: String) -> String? {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(relativePath)
    return try? String(contentsOf: sourceURL, encoding: .utf8)
}

private func testAppStateStartOnlyRunsSessionAfterCaptureSucceeds() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppState.swift") else {
        fputs("FAIL: AppState source should be readable\n", stderr)
        return false
    }

    guard let captureStart = source.range(of: "try await self.capturePipeline.start"),
          let runningSet = source.range(of: "self.isRunning = true"),
          let transcriptionStart = source.range(of: "self.startTranscriptionEngine()")
    else {
        fputs("FAIL: AppState start lifecycle markers should exist\n", stderr)
        return false
    }

    return expectEqual(
        captureStart.lowerBound < runningSet.lowerBound && runningSet.lowerBound < transcriptionStart.lowerBound,
        true,
        "AppState should mark running and start transcription only after capture succeeds"
    ) && expectEqual(
        source.contains("self.handleCaptureStartFailure(error)"),
        true,
        "capture start failure should roll back session side effects"
    )
}

private func testAppDelegateTerminatesAfterAwaitedSessionStop() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppDelegate.swift") else {
        fputs("FAIL: AppDelegate source should be readable\n", stderr)
        return false
    }

    return expectEqual(
        source.contains(".terminateLater") &&
            source.contains("await state.stop()") &&
            source.contains("sender.reply(toApplicationShouldTerminate: true)"),
        true,
        "confirmed quit should await session stop before replying to terminate"
    )
}

private func testStreamDeckAdapterUsesExplicitOutputCommands() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppState+StreamDeck.swift") else {
        fputs("FAIL: Stream Deck AppState adapter source should be readable\n", stderr)
        return false
    }

    return expectEqual(
        source.contains("case .panicBlank:") &&
            source.contains("panicBlank()") &&
            source.contains("case .unblankOutput:") &&
            source.contains("unblankOutput()") &&
            source.contains("case .clearCaptions:") &&
            source.contains("clearCaptions()"),
        true,
        "Stream Deck adapter should route safe output commands through explicit operations"
    ) && expectEqual(
        source.contains("toggleOutputBlank()"),
        false,
        "Stream Deck adapter should never toggle output blanking"
    )
}

private func testStreamDeckFillRejectsUnavailableExternalDisplay() -> Bool {
    guard let controller = readSource("Sources/EventSubtitlesApp/OutputWindowController.swift"),
          let appState = readSource("Sources/EventSubtitlesApp/AppState.swift"),
          let adapter = readSource("Sources/EventSubtitlesApp/AppState+StreamDeck.swift")
    else {
        fputs("FAIL: output-fill sources should be readable\n", stderr)
        return false
    }

    return expectEqual(
        controller.contains("func fillExternalDisplay() -> Bool") &&
            !controller.contains("preferredOutputScreen() ?? NSScreen.main") &&
            controller.contains("selected != NSScreen.main") &&
            controller.contains("return NSScreen.screens.first { $0 != NSScreen.main }"),
        true,
        "filled output should require a non-main external display"
    ) && expectEqual(
        appState.contains("func fillExternalDisplay() -> Bool") &&
            adapter.contains("guard fillExternalDisplay() else") &&
            adapter.contains("reason: .noExternalDisplay"),
        true,
        "Stream Deck fill command should reject when external fill cannot be performed"
    )
}

private func testStreamDeckStatusUsesTypedStateFacts() -> Bool {
    guard let adapter = readSource("Sources/EventSubtitlesApp/AppState+StreamDeck.swift") else {
        fputs("FAIL: Stream Deck AppState adapter source should be readable\n", stderr)
        return false
    }

    return expectEqual(
        adapter.contains("StreamDeckStatusPolicy.audioState(") &&
            adapter.contains("isSelectedInputAvailable: isSelectedAudioInputAvailable") &&
            adapter.contains("hasAudioFailure: hasAudioCaptureFailure") &&
            adapter.contains("didFailToStartSession") &&
            adapter.contains("StreamDeckStatusPolicy.captionState("),
        true,
        "status projection should pass typed AppState facts to Stream Deck policy"
    ) && expectEqual(
        adapter.contains("errorMessage.contains") ||
            adapter.contains("errorMessage.localizedCaseInsensitiveContains") ||
            adapter.contains("errorMessage.range"),
        false,
        "Stream Deck status should not classify state by searching error text"
    )
}

private func testStreamDeckFailureFactsTrackCaptureLifecycle() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppState.swift") else {
        fputs("FAIL: AppState source should be readable\n", stderr)
        return false
    }

    return expectEqual(
        source.contains("var didFailToStartSession = false") &&
            source.contains("var hasAudioCaptureFailure = false") &&
            source.contains("var isSelectedAudioInputAvailable = false") &&
            source.contains("didFailToStartSession = false") &&
            source.contains("hasAudioCaptureFailure = false"),
        true,
        "AppState should own typed Stream Deck status facts and clear failures on start"
    ) && expectEqual(
        source.contains("didFailToStartSession = true") &&
            source.contains("hasAudioCaptureFailure = true") &&
            source.contains("self.hasAudioCaptureFailure = false") &&
            source.contains("self.hasAudioCaptureFailure = true"),
        true,
        "capture start and restart paths should maintain typed failure facts"
    )
}

let tests = [
    ("systemDefaultModeUsesDefaultDevice", testSystemDefaultModeUsesDefaultDevice),
    ("availableOverrideWinsOverDefaultDevice", testAvailableOverrideWinsOverDefaultDevice),
    ("unavailableOverrideFallsBackToDefaultDevice", testUnavailableOverrideFallsBackToDefaultDevice),
    ("promptBuilderIncludesSessionAndGlossaryTerms", testPromptBuilderIncludesSessionAndGlossaryTerms),
    ("promptBuilderDropsEmptyParts", testPromptBuilderDropsEmptyParts),
    ("promptBuilderTruncatesAtCharacterLimit", testPromptBuilderTruncatesAtCharacterLimit),
    ("srtAppendingMatchesFullFormat", testSRTAppendingMatchesFullFormat),
    ("captionTickSchedulerComputesNearestDeadline", testCaptionTickSchedulerComputesNearestDeadline),
    ("captionTickSchedulerUsesFallbackWhenAllNil", testCaptionTickSchedulerUsesFallbackWhenAllNil),
    ("captionLineFitterPicksNewestThatFit", testCaptionLineFitterPicksNewestThatFit),
    ("captionLineFitterIncludesOversizedSingleLine", testCaptionLineFitterIncludesOversizedSingleLine),
    ("appStateStartOnlyRunsSessionAfterCaptureSucceeds", testAppStateStartOnlyRunsSessionAfterCaptureSucceeds),
    ("appDelegateTerminatesAfterAwaitedSessionStop", testAppDelegateTerminatesAfterAwaitedSessionStop),
    ("streamDeckAdapterUsesExplicitOutputCommands", testStreamDeckAdapterUsesExplicitOutputCommands),
    ("streamDeckFillRejectsUnavailableExternalDisplay", testStreamDeckFillRejectsUnavailableExternalDisplay),
    ("streamDeckStatusUsesTypedStateFacts", testStreamDeckStatusUsesTypedStateFacts),
    ("streamDeckFailureFactsTrackCaptureLifecycle", testStreamDeckFailureFactsTrackCaptureLifecycle)
]

var failed = 0
for (name, test) in tests {
    if test() {
        print("PASS: \(name)")
    } else {
        failed += 1
    }
}

if failed > 0 {
    exit(1)
}
