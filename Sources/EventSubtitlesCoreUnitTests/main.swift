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

private func testSemanticVersionParsesStableVersion() -> Bool {
    guard let version = SemanticVersion("3.4.0") else {
        fputs("FAIL: stable semantic version should parse\n", stderr)
        return false
    }
    return expectEqual(version.major, 3, "semantic major") &&
        expectEqual(version.minor, 4, "semantic minor") &&
        expectEqual(version.patch, 0, "semantic patch") &&
        expectEqual(version.prerelease, nil, "semantic prerelease")
}

private func testSemanticVersionParsesPrereleaseVersion() -> Bool {
    guard let version = SemanticVersion("3.4.0-rc1") else {
        fputs("FAIL: prerelease semantic version should parse\n", stderr)
        return false
    }
    return expectEqual(version.major, 3, "prerelease semantic major") &&
        expectEqual(version.minor, 4, "prerelease semantic minor") &&
        expectEqual(version.patch, 0, "prerelease semantic patch") &&
        expectEqual(version.prerelease, "rc1", "semantic prerelease suffix")
}

private func testSemanticVersionRejectsMalformedVersions() -> Bool {
    let values = ["", "3", "3.4", "3.4.x", "v3.4.0", "3.4.0-", "3.4.0+build", "3.4.0 rc1"]
    return values.allSatisfy { value in
        if SemanticVersion(value) == nil {
            return true
        }
        fputs("FAIL: malformed semantic version should be rejected: \(value)\n", stderr)
        return false
    }
}

private func testSemanticVersionRejectsMalformedPrereleaseIdentifiers() -> Bool {
    let values = ["3.4.0-alpha..1", "3.4.0-.alpha", "3.4.0-alpha."]
    return values.allSatisfy { value in
        if SemanticVersion(value) == nil {
            return true
        }
        fputs("FAIL: malformed semantic prerelease should be rejected: \(value)\n", stderr)
        return false
    }
}

private func testSemanticVersionComparesNumerically() -> Bool {
    guard let low = SemanticVersion("3.9.0"),
          let high = SemanticVersion("3.10.0"),
          let patch = SemanticVersion("3.10.1") else {
        fputs("FAIL: comparison semantic versions should parse\n", stderr)
        return false
    }
    return expectEqual(high > low, true, "minor comparison should be numeric") &&
        expectEqual(patch > high, true, "patch comparison should be numeric")
}

private func testSemanticVersionSortsPrereleaseBeforeStable() -> Bool {
    guard let prerelease = SemanticVersion("3.4.0-rc1"),
          let stable = SemanticVersion("3.4.0") else {
        fputs("FAIL: prerelease comparison semantic versions should parse\n", stderr)
        return false
    }
    return expectEqual(prerelease < stable, true, "prerelease sorts before stable") &&
        expectEqual(stable > prerelease, true, "stable sorts after prerelease")
}

private func testRollingAudioBufferRetainsOnlyConfiguredWindow() -> Bool {
    var buffer = RollingAudioSampleBuffer(maximumRetainedSamples: 5, sampleRate: 10)

    buffer.append([1, 2, 3])
    buffer.append([4, 5, 6, 7])

    return expectEqual(buffer.samples, [3, 4, 5, 6, 7], "rolling buffer should keep newest samples") &&
        expectEqual(buffer.droppedSampleCount, 2, "rolling buffer should track dropped sample count") &&
        expectEqual(buffer.totalSampleCount, 7, "rolling buffer should track total ingested samples") &&
        expectEqual(buffer.streamOffsetSeconds, 0.2, "rolling buffer offset should reflect dropped samples")
}

private func testRollingAudioBufferResetClearsSamplesAndOffset() -> Bool {
    var buffer = RollingAudioSampleBuffer(maximumRetainedSamples: 3, sampleRate: 10)

    buffer.append([1, 2, 3, 4, 5])
    buffer.reset()

    return expectEqual(buffer.samples, [], "rolling buffer reset should clear samples") &&
        expectEqual(buffer.droppedSampleCount, 0, "rolling buffer reset should clear dropped count") &&
        expectEqual(buffer.totalSampleCount, 0, "rolling buffer reset should clear total count") &&
        expectEqual(buffer.streamOffsetSeconds, 0, "rolling buffer reset should clear offset")
}

private func testCaptionRowLayoutReservesBottomAlignedRowsForRollup() -> Bool {
    expectEqual(
        CaptionRowLayout.rows(for: ["First line"], maxLines: 2, reserveEmptyRows: true),
        ["", "First line"],
        "roll-up output should reserve empty top row so a single line stays in the bottom slot"
    ) && expectEqual(
        CaptionRowLayout.rows(for: ["First line", "Second line"], maxLines: 2, reserveEmptyRows: true),
        ["First line", "Second line"],
        "roll-up output should use both reserved rows when two lines are visible"
    )
}

private func testCaptionRowLayoutDoesNotReserveRowsForBlockCaptions() -> Bool {
    expectEqual(
        CaptionRowLayout.rows(for: ["Only line"], maxLines: 2, reserveEmptyRows: false),
        ["Only line"],
        "non-roll-up captions should not render placeholder rows"
    )
}

private func testLinePacedRollerOnlyDrainsVisibleLinesForHistory() -> Bool {
    let start = Date(timeIntervalSince1970: 1_000)
    var roller = LinePacedRoller(targetCharactersPerLine: 10, maxLines: 1)

    roller.ingest(
        StableCaptionPhrase(text: "one two three four five", committedAt: start, isFinal: true),
        now: start
    )

    let firstDrain = roller.drainRevealedLines()
    let visibleAfterIngest = roller.visibleLines
    _ = roller.tick(now: start.addingTimeInterval(0.5), lineMinHold: 1.0, idleFlushAfter: 1.0)
    let earlyDrain = roller.drainRevealedLines()
    _ = roller.tick(now: start.addingTimeInterval(1.1), lineMinHold: 1.0, idleFlushAfter: 1.0)
    let secondDrain = roller.drainRevealedLines()

    return expectEqual(firstDrain, ["one two"], "history should initially drain only the line that became visible") &&
        expectEqual(visibleAfterIngest, ["one two"], "only the first line should be visible while remaining lines are pending") &&
        expectEqual(earlyDrain, [], "history should not record pending lines before they are visible") &&
        expectEqual(secondDrain, ["three four"], "history should record pending lines when they roll onto the green screen")
}

private func testLinePacedRollerReportsPendingOutputUntilQueuedLinesReveal() -> Bool {
    let start = Date(timeIntervalSince1970: 1_000)
    var roller = LinePacedRoller(targetCharactersPerLine: 10, maxLines: 1)

    roller.ingest(
        StableCaptionPhrase(text: "one two three four", committedAt: start, isFinal: true),
        now: start
    )

    let pendingAfterIngest = roller.hasPendingOutput
    _ = roller.tick(now: start.addingTimeInterval(1.1), lineMinHold: 1.0, idleFlushAfter: 1.0)
    let pendingAfterQueuedLineReveals = roller.hasPendingOutput

    return expectEqual(pendingAfterIngest, true, "roller should report queued lines that still need to reach the output") &&
        expectEqual(pendingAfterQueuedLineReveals, false, "roller should stop reporting pending output after queued lines reveal")
}

private func testSemanticVersionComparesPrereleaseIdentifiersBySemVerRules() -> Bool {
    let orderedValues = [
        "3.4.0-alpha",
        "3.4.0-alpha.1",
        "3.4.0-alpha.beta",
        "3.4.0-beta",
        "3.4.0-beta.2",
        "3.4.0-beta.11",
        "3.4.0-rc.1",
        "3.4.0"
    ]
    let versions = orderedValues.compactMap(SemanticVersion.init)
    guard versions.count == orderedValues.count else {
        fputs("FAIL: semantic prerelease ordering versions should parse\n", stderr)
        return false
    }

    return versions.indices.dropLast().allSatisfy { index in
        let result = versions[index] < versions[index + 1]
        if !result {
            fputs("FAIL: expected \(orderedValues[index]) to sort before \(orderedValues[index + 1])\n", stderr)
        }
        return result
    }
}

private func testSemanticVersionComparesNumericPrereleaseBeforeNonNumeric() -> Bool {
    guard let numeric = SemanticVersion("3.4.0-1"),
          let nonNumeric = SemanticVersion("3.4.0-alpha") else {
        fputs("FAIL: numeric and non-numeric prerelease versions should parse\n", stderr)
        return false
    }

    return expectEqual(numeric < nonNumeric, true, "numeric prerelease identifier sorts before non-numeric")
}

private struct FakeVersionTextFetcher: VersionTextFetching {
    var result: Result<String, UpdateCheckFailureReason>

    func fetchVersionText(from url: URL, timeout: TimeInterval) async throws -> Result<String, UpdateCheckFailureReason> {
        result
    }
}

private func testUpdateCheckerReportsUpToDateForEqualVersion() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .success("3.4.0\n")))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(status, .upToDate(currentVersion: "3.4.0"), "equal version is up to date")
}

private func testUpdateCheckerReportsAvailableForNewerVersion() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .success("3.5.0")))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(
        status,
        .available(currentVersion: "3.4.0", latestVersion: "3.5.0"),
        "newer latest version is available"
    )
}

private func testUpdateCheckerReportsUpToDateForOlderLatestVersion() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .success("3.3.0")))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(status, .upToDate(currentVersion: "3.4.0"), "older latest version is not an update")
}

private func testUpdateCheckerReportsAvailableFromPrereleaseToStable() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .success("3.4.0")))
    let status = await checker.check(
        currentVersionText: "3.4.0-rc1",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(
        status,
        .available(currentVersion: "3.4.0-rc1", latestVersion: "3.4.0"),
        "stable release updates matching prerelease"
    )
}

private func testUpdateCheckerManualFailureSurfacesReason() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .failure(.networkUnavailable)))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(
        status,
        .failed(currentVersion: "3.4.0", reason: .networkUnavailable),
        "manual network failure surfaces"
    )
}

private func testUpdateCheckerManualHTTPStatusFailureSurfacesReason() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .failure(.httpStatus(503))))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(
        status,
        .failed(currentVersion: "3.4.0", reason: .httpStatus(503)),
        "manual HTTP status failure surfaces"
    )
}

private func testUpdateCheckerManualNoStableReleaseFailureSurfacesReason() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .failure(.noStableReleaseFound)))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(
        status,
        .failed(currentVersion: "3.4.0", reason: .noStableReleaseFound),
        "manual no-stable-release failure surfaces"
    )
}

private func testUpdateCheckerLaunchFailureReturnsIdle() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .failure(.networkUnavailable)))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .launch,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(status, .idle, "launch network failure returns idle")
}

private func testUpdateCheckerLaunchHTTPStatusFailureReturnsIdle() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .failure(.httpStatus(503))))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .launch,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(status, .idle, "launch HTTP status failure returns idle")
}

private func testUpdateCheckerLaunchNoStableReleaseFailureReturnsIdle() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .failure(.noStableReleaseFound)))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .launch,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(status, .idle, "launch no-stable-release failure returns idle")
}

private func testUpdateCheckerRejectsMalformedRemoteVersion() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .success("not-a-version")))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(
        status,
        .failed(currentVersion: "3.4.0", reason: .invalidRemoteVersion),
        "malformed remote version fails"
    )
}

private func testUpdateCheckerRejectsMalformedLocalVersion() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .success("3.4.0")))
    let status = await checker.check(
        currentVersionText: "local-dev",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(
        status,
        .failed(currentVersion: "local-dev", reason: .invalidLocalVersion),
        "malformed local version fails"
    )
}

private func testUpdateCheckerLaunchMalformedLocalVersionReturnsIdle() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .success("3.4.0")))
    let status = await checker.check(
        currentVersionText: "local-dev",
        mode: .launch,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(status, .idle, "launch malformed local version returns idle")
}

private func testURLSessionVersionTextFetcherPreservesCancellation() -> Bool {
    do {
        _ = try URLSessionVersionTextFetcher.updateCheckFailureReason(
            for: URLError(.cancelled),
            taskIsCancelled: false
        )
        fputs("FAIL: URLSession cancellation should throw cancellation\n", stderr)
        return false
    } catch is CancellationError {
        return true
    } catch {
        fputs("FAIL: URLSession cancellation threw unexpected error: \(error)\n", stderr)
        return false
    }
}

private func testURLSessionVersionTextFetcherMapsNetworkErrors() -> Bool {
    do {
        let reason = try URLSessionVersionTextFetcher.updateCheckFailureReason(
            for: URLError(.notConnectedToInternet),
            taskIsCancelled: false
        )
        return expectEqual(reason, .networkUnavailable, "URLSession network errors map to networkUnavailable")
    } catch {
        fputs("FAIL: URLSession network error should not throw: \(error)\n", stderr)
        return false
    }
}

private func readSource(_ relativePath: String) -> String? {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(relativePath)
    return try? String(contentsOf: sourceURL, encoding: .utf8)
}

private func testAppStateUpdateChecksDoNotRestartInFlightChecks() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppState.swift"),
          let runStart = source.range(of: "private func runUpdateCheck(mode: UpdateCheckMode)"),
          let selectOutput = source.range(of: "func selectOutputDisplay", range: runStart.upperBound..<source.endIndex)
    else {
        fputs("FAIL: AppState update-check lifecycle markers should exist\n", stderr)
        return false
    }

    let runUpdateCheck = source[runStart.lowerBound..<selectOutput.lowerBound]
    return expectEqual(
        runUpdateCheck.contains("guard updateStatus != .checking, updateCheckTask == nil else") &&
            runUpdateCheck.contains("return") &&
            !runUpdateCheck.contains("updateCheckTask?.cancel()"),
        true,
        "manual update checks should no-op instead of canceling and restarting an in-flight check"
    )
}

private func testAppStateLaunchUpdateCheckAttemptsOncePerProcess() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppState.swift"),
          let launchStart = source.range(of: "func checkForUpdatesOnLaunch()"),
          let manualStart = source.range(of: "func checkForUpdatesManually()", range: launchStart.upperBound..<source.endIndex)
    else {
        fputs("FAIL: AppState launch update-check markers should exist\n", stderr)
        return false
    }

    let launchCheck = source[launchStart.lowerBound..<manualStart.lowerBound]
    return expectEqual(
        source.contains("@ObservationIgnored private var hasAttemptedLaunchUpdateCheck = false") &&
            launchCheck.contains("guard !hasAttemptedLaunchUpdateCheck, updateStatus == .idle, updateCheckTask == nil else") &&
            launchCheck.contains("hasAttemptedLaunchUpdateCheck = true") &&
            launchCheck.contains("runUpdateCheck(mode: .launch)"),
        true,
        "launch update checks should be attempted at most once per app process"
    )
}

private func testAppStateUpdateVersionFallbacksAreNeutral() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppState.swift"),
          let versionStart = source.range(of: "var currentAppVersionText: String"),
          let runStart = source.range(of: "private func runUpdateCheck", range: versionStart.upperBound..<source.endIndex)
    else {
        fputs("FAIL: AppState version fallback markers should exist\n", stderr)
        return false
    }

    let versionAccessors = source[versionStart.lowerBound..<runStart.lowerBound]
    return expectEqual(
        versionAccessors.contains(#"bundleInfoString(for: "CFBundleShortVersionString") ?? "unknown-local""#) &&
            versionAccessors.contains(#"bundleInfoString(for: "CFBundleVersion") ?? "local""#) &&
            versionAccessors.contains("trimmingCharacters(in: .whitespacesAndNewlines)") &&
            !source.contains(#"?? "3.3.0""#) &&
            !source.contains(#"?? "8""#),
        true,
        "AppState should use bundle version values first and neutral local fallbacks instead of stale release constants"
    )
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

private func testAppStateCanceledStartDoesNotRecordFailure() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppState.swift"),
          let captureStart = source.range(of: "try await self.capturePipeline.start"),
          let failureHandler = source.range(
            of: "self.handleCaptureStartFailure(error)",
            range: captureStart.upperBound..<source.endIndex
          )
    else {
        fputs("FAIL: AppState capture-start failure markers should exist\n", stderr)
        return false
    }

    let failurePath = source[captureStart.upperBound..<failureHandler.lowerBound]
    return expectEqual(
        failurePath.contains("guard self.isStarting else { return }"),
        true,
        "canceled capture startup should not be recorded as a session-start failure"
    )
}

private func testAppStateScopesCaptureCompletionToStartupAttempt() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppState.swift"),
          let startTask = source.range(of: "Task { @MainActor [weak self] in"),
          let captureStart = source.range(of: "try await self.capturePipeline.start"),
          let runningSet = source.range(
            of: "self.isRunning = true",
            range: captureStart.upperBound..<source.endIndex
          ),
          let catchStart = source.range(
            of: "} catch {",
            range: captureStart.upperBound..<source.endIndex
          ),
          let failureHandler = source.range(
            of: "self.handleCaptureStartFailure(error)",
            range: catchStart.upperBound..<source.endIndex
          ),
          let stopStart = source.range(of: "func stop() async"),
          let stopCapture = source.range(
            of: "capturePipeline.stop()",
            range: stopStart.upperBound..<source.endIndex
          )
    else {
        fputs("FAIL: AppState startup-attempt lifecycle markers should exist\n", stderr)
        return false
    }

    let beforeCaptureStart = source[startTask.upperBound..<captureStart.lowerBound]
    let successPath = source[captureStart.upperBound..<runningSet.lowerBound]
    let failurePath = source[catchStart.upperBound..<failureHandler.lowerBound]
    let stopPath = source[stopStart.upperBound..<stopCapture.lowerBound]
    return expectEqual(
        source.contains("@ObservationIgnored private var activeCaptureStartAttempt: UUID?") &&
            source.contains("let startAttemptID = UUID()") &&
            source.contains("activeCaptureStartAttempt = startAttemptID") &&
            source.contains("let captureOperationGeneration = capturePipeline.reserveControlOperation()") &&
            source.contains("operationGeneration: captureOperationGeneration") &&
            beforeCaptureStart.contains("self.activeCaptureStartAttempt == startAttemptID") &&
            successPath.contains("self.activeCaptureStartAttempt == startAttemptID") &&
            failurePath.contains("self.activeCaptureStartAttempt == startAttemptID") &&
            stopPath.contains("activeCaptureStartAttempt = nil"),
        true,
        "capture start completions should be accepted only for the active startup attempt"
    )
}

private func testAudioCapturePipelineSerializesControlOperations() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AudioCapturePipeline.swift"),
          let publicStart = source.range(of: "func start("),
          let privateStart = source.range(of: "private func start"),
          let stop = source.range(of: "func stop()"),
          let restart = source.range(of: "func restart("),
          restart.lowerBound > stop.lowerBound
    else {
        fputs("FAIL: audio capture control-operation markers should exist\n", stderr)
        return false
    }

    let startPath = source[publicStart.lowerBound..<privateStart.lowerBound]
    let stopPath = source[stop.lowerBound..<restart.lowerBound]
    let restartPath = source[restart.lowerBound..<source.endIndex]
    let cancellationGuards = source.components(
        separatedBy: "guard controlGeneration == operationGeneration else { throw CancellationError() }"
    ).count - 1
    return expectEqual(
        source.contains("private let controlLock = NSLock()") &&
            source.contains("private var controlGeneration: UInt64 = 0") &&
            source.contains("private func beginControlOperation() -> UInt64") &&
            source.contains("func reserveControlOperation() -> UInt64") &&
            source.contains("operationGeneration: UInt64,") &&
            startPath.contains("let operationGeneration = beginControlOperation()") &&
            startPath.contains("controlLock.withLock") &&
            startPath.contains("controlGeneration == operationGeneration") &&
            stopPath.contains("controlLock.withLock") &&
            stopPath.contains("controlGeneration &+= 1") &&
            restartPath.contains("let operationGeneration = beginControlOperation()") &&
            restartPath.contains("controlLock.withLock") &&
            restartPath.contains("controlGeneration == operationGeneration") &&
            cancellationGuards >= 2,
        true,
        "audio capture control operations should serialize mutation and throw cancellation when superseded"
    )
}

private func testAppStateScopesConfigurationRestartToRunningSession() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppState.swift"),
          let stopStart = source.range(of: "func stop() async"),
          let failureHandler = source.range(of: "private func handleCaptureStartFailure"),
          let restartStart = source.range(of: "private func handleAudioConfigurationChange(for runningSessionID: UUID)"),
          let selectedInput = source.range(
            of: "private func selectedAudioInputDeviceForCapture()",
            range: restartStart.upperBound..<source.endIndex
          )
    else {
        fputs("FAIL: AppState running-session restart markers should exist\n", stderr)
        return false
    }

    let stopPath = source[stopStart.lowerBound..<failureHandler.lowerBound]
    let restartPath = source[restartStart.lowerBound..<selectedInput.lowerBound]
    let sessionChecks = restartPath.components(separatedBy: "self.runningCaptureSessionID == runningSessionID").count - 1
    let stopInvalidationPrecedesAwait = stopPath.range(of: "capturePipeline.stop()")!.lowerBound <
        stopPath.range(of: "await whisperKitTranscriber.stop()")!.lowerBound
    return expectEqual(
        source.contains("@ObservationIgnored private var runningCaptureSessionID: UUID?") &&
            source.contains("self.runningCaptureSessionID = startAttemptID") &&
            stopPath.contains("runningCaptureSessionID = nil") &&
            stopInvalidationPrecedesAwait &&
            source.contains("self?.handleAudioConfigurationChange(for: startAttemptID)") &&
            restartPath.contains("guard isRunning, self.runningCaptureSessionID == runningSessionID else { return }") &&
            restartPath.contains("let restartOperationGeneration = capturePipeline.reserveControlOperation()") &&
            restartPath.contains("operationGeneration: restartOperationGeneration") &&
            restartPath.contains("try await self.capturePipeline.restart(") &&
            restartPath.contains("catch is CancellationError {") &&
            sessionChecks >= 4,
        true,
        "configuration restarts should ignore supersession and publish only for their originating running session"
    )
}

private func testAppStateScopesAudioCallbacksToRunningSession() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppState.swift"),
          let captureStart = source.range(of: "try await self.capturePipeline.start"),
          let captureComplete = source.range(
            of: "self.isRunning = true",
            range: captureStart.upperBound..<source.endIndex
          ),
          let publishStart = source.range(of: "private func publishAudioLevel("),
          let systemMemoryStart = source.range(
            of: "var systemMemoryText:",
            range: publishStart.upperBound..<source.endIndex
          )
    else {
        fputs("FAIL: AppState audio callback markers should exist\n", stderr)
        return false
    }

    let callbacks = source[captureStart.lowerBound..<captureComplete.lowerBound]
    let publish = source[publishStart.lowerBound..<systemMemoryStart.lowerBound]
    return expectEqual(
        callbacks.contains("self?.publishAudioLevel(Double(max(sample.rms, sample.peak)), for: startAttemptID)") &&
            callbacks.contains("self.runningCaptureSessionID == startAttemptID") &&
            callbacks.contains("self.whisperKitTranscriber.ingest(samples)") &&
            publish.contains("for runningSessionID: UUID") &&
            publish.contains("guard isRunning, self.runningCaptureSessionID == runningSessionID else { return }"),
        true,
        "audio level and sample delivery should be scoped to the current running capture session"
    )
}

private func testAudioCapturePipelineBindsInstalledCallbacksToGeneration() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AudioCapturePipeline.swift") else {
        fputs("FAIL: audio capture pipeline source should be readable\n", stderr)
        return false
    }

    return expectEqual(
        source.contains("private var activeDeliveryGeneration: UInt64?") &&
            source.contains("operationGeneration: UInt64,") &&
            source.contains("self?.handleBuffer(") &&
            source.contains("operationGeneration: operationGeneration") &&
            source.contains("onLevel: onLevel") &&
            source.contains("onSamples: onSamples") &&
            source.contains("activeDeliveryGeneration == operationGeneration") &&
            source.contains("private func installConfigChangeObserver(_ onConfigurationChange: @escaping @Sendable () -> Void)") &&
            source.contains("private func installDefaultInputDeviceListener(_ onConfigurationChange: @escaping @Sendable () -> Void)") &&
            source.contains("onConfigurationChange()") &&
            !source.contains("self?.onConfigurationDidChange?()"),
        true,
        "tap and configuration delivery should use handlers captured for the installing generation"
    )
}

private func testAudioCapturePipelineCleansUpPartialStartResources() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AudioCapturePipeline.swift"),
          let startLocked = source.range(of: "private func startLocked"),
          let stopLocked = source.range(of: "private func stopLocked"),
          let restart = source.range(of: "func restart(", range: stopLocked.upperBound..<source.endIndex),
          let cleanup = source.range(of: "private func cleanupCaptureResourcesLocked")
    else {
        fputs("FAIL: audio capture partial-start cleanup markers should exist\n", stderr)
        return false
    }

    let startPath = source[startLocked.lowerBound..<stopLocked.lowerBound]
    let stopPath = source[stopLocked.lowerBound..<restart.lowerBound]
    let cleanupPath = source[cleanup.lowerBound..<source.endIndex]
    return expectEqual(
        source.contains("private var captureResourcesInstalled = false") &&
            startPath.contains("do {") &&
            startPath.contains("captureResourcesInstalled = true") &&
            startPath.contains("catch {") &&
            startPath.contains("cleanupCaptureResourcesLocked(keepRecordingFile: preserveExistingRecording)") &&
            stopPath.contains("cleanupCaptureResourcesLocked(keepRecordingFile: keepRecordingFile)") &&
            cleanupPath.contains("engine.inputNode.removeTap(onBus: 0)") &&
            cleanupPath.contains("engine.stop()") &&
            cleanupPath.contains("converter = nil") &&
            cleanupPath.contains("recordingFile = nil") &&
            cleanupPath.contains("NotificationCenter.default.removeObserver(configChangeObserver)") &&
            cleanupPath.contains("removeDefaultInputDeviceListener()") &&
            cleanupPath.contains("levelHandler = nil") &&
            cleanupPath.contains("samplesHandler = nil") &&
            cleanupPath.contains("onConfigurationDidChange = nil") &&
            cleanupPath.contains("activeDeliveryGeneration = nil") &&
            cleanupPath.contains("captureResourcesInstalled = false"),
        true,
        "partial start failures and non-running stops should clean installed capture resources"
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

private func testAppStatePublishesStreamDeckStatusForLiveStateChanges() -> Bool {
    guard let source = readSource("Sources/EventSubtitlesApp/AppState.swift") else {
        fputs("FAIL: AppState source should be readable\n", stderr)
        return false
    }

    let publishedProperties = [
        "var isRunning = false { didSet { publishStreamDeckStatus() } }",
        "var isStarting = false { didSet { publishStreamDeckStatus() } }",
        "var audioLevel = 0.0 { didSet { publishStreamDeckStatus() } }",
        "var isSelectedAudioInputAvailable = false { didSet { publishStreamDeckStatus() } }",
        "var hasAudioCaptureFailure = false { didSet { publishStreamDeckStatus() } }",
        "var didFailToStartSession = false { didSet { publishStreamDeckStatus() } }",
        "var errorMessage: String? { didSet { publishStreamDeckStatus() } }",
        "var outputBlanked = false { didSet { publishStreamDeckStatus() } }",
        "var sessionSegmentCount = 0 { didSet { publishStreamDeckStatus() } }",
        #"var sessionElapsedText = "00:00:00" { didSet { publishStreamDeckStatus() } }"#,
        "var outputWindowVisible = false { didSet { publishStreamDeckStatus() } }",
        "var outputWindowFilled = false { didSet { publishStreamDeckStatus() } }",
        "var sessionStartedAt: Date? { didSet { publishStreamDeckStatus() } }",
        "var lastCaptionActivityAt: Date? { didSet { publishStreamDeckStatus() } }"
    ]

    return expectEqual(
        publishedProperties.allSatisfy { source.contains($0) } &&
            source.contains("publicCaptionText = \"\"") &&
            source.contains("publicCaptionText = display") &&
            source.contains("sessionElapsedText = String(format:"),
        true,
        "AppState should broadcast Stream Deck status when live status-driving state changes"
    )
}

private func testWhisperKitTranscriberUsesBoundedStreamingBuffer() -> Bool {
    guard let transcriber = readSource("Sources/EventSubtitlesApp/WhisperKitTranscriber.swift"),
          let processor = readSource("Sources/EventSubtitlesApp/StreamFedAudioProcessor.swift")
    else {
        fputs("FAIL: Whisper streaming sources should be readable\n", stderr)
        return false
    }

    return expectEqual(
        processor.contains("RollingAudioSampleBuffer") &&
            processor.contains("maximumRetainedSeconds") &&
            transcriber.contains("private let maximumRetainedAudioSeconds") &&
            transcriber.contains("maximumRetainedAudioSeconds: TimeInterval = 30") &&
            transcriber.contains("TranscribeTask(") &&
            transcriber.contains("streamOffsetSeconds") &&
            !transcriber.contains("AudioStreamTranscriber("),
        true,
        "WhisperKit transcriber should use a bounded buffer and owned streaming loop instead of AudioStreamTranscriber"
    )
}

private func testWhisperKitTranscriberDoesNotReplayUnconfirmedProgress() -> Bool {
    guard let transcriber = readSource("Sources/EventSubtitlesApp/WhisperKitTranscriber.swift") else {
        fputs("FAIL: WhisperKit transcriber source should be readable\n", stderr)
        return false
    }

    return expectEqual(
        transcriber.contains("private let requiredSegmentsForConfirmation = 0") &&
            transcriber.contains("let transcription = try await transcribeTask.run(audioArray: snapshot.samples, decodeOptions: options) { progress in") &&
            !transcriber.contains("self?.handleProgress") &&
            !transcriber.contains("private func handleProgress") &&
            !transcriber.contains("lastPartialText = \"\"\n        let absoluteSegments"),
        true,
        "WhisperKit transcriber should confirm completed segments and avoid replaying decoder progress into public captions"
    )
}

private func testWhisperKitTranscriberUsesDeterministicLiveDecodeOptions() -> Bool {
    guard let transcriber = readSource("Sources/EventSubtitlesApp/WhisperKitTranscriber.swift") else {
        fputs("FAIL: WhisperKit transcriber source should be readable\n", stderr)
        return false
    }

    return expectEqual(
        transcriber.contains("temperature: 0.0") &&
            transcriber.contains("temperatureIncrementOnFallback: 0.0") &&
            transcriber.contains("temperatureFallbackCount: 0") &&
            transcriber.contains("wordTimestamps: false"),
        true,
        "live Whisper decoding should stay deterministic and avoid expensive word-timestamp alignment"
    )
}

private func testWhisperKitTranscriberCapsRealtimeDecodeBacklog() -> Bool {
    guard let transcriber = readSource("Sources/EventSubtitlesApp/WhisperKitTranscriber.swift") else {
        fputs("FAIL: WhisperKit transcriber source should be readable\n", stderr)
        return false
    }

    return expectEqual(
        transcriber.contains("private let maximumLiveDecodeWindowSeconds: Float = 12") &&
            transcriber.contains("private let minimumDecodeAudioSeconds: Float = 2") &&
            transcriber.contains("let recentWindowStart = max(0, snapshotDurationSeconds - maximumLiveDecodeWindowSeconds)") &&
            transcriber.contains("let clipTimestamp = max(confirmedClipTimestamp, recentWindowStart)"),
        true,
        "live Whisper decoding should cap stale backlog instead of dumping old captions after a long decode gap"
    )
}

private func testRollupOutputReservesRowsAndDisablesTextAnimation() -> Bool {
    guard let outputView = readSource("Sources/EventSubtitlesApp/SubtitleOutputView.swift"),
          let appState = readSource("Sources/EventSubtitlesApp/AppState.swift"),
          let style = readSource("Sources/EventSubtitlesApp/StyleWorkspace.swift")
    else {
        fputs("FAIL: roll-up output sources should be readable\n", stderr)
        return false
    }

    return expectEqual(
        outputView.contains("CaptionRowLayout.rows(") &&
            outputView.contains("reserveEmptyRows: state.captionDisplayMode == .liveRollUp") &&
            outputView.contains("state.captionDisplayMode != .liveRollUp") &&
            outputView.contains("line.isEmpty ? \" \" : line") &&
            appState.contains("var captionLineMinHold = 1.2") &&
            appState.contains("settings.captionLineMinHold ?? 1.2") &&
            style.contains("range: 0.7...3.0"),
        true,
        "roll-up output should reserve rows, avoid smooth text animation, and use a faster default line hold"
    )
}

private func testRollupAutoClearWaitsForPendingOutput() -> Bool {
    guard let appState = readSource("Sources/EventSubtitlesApp/AppState.swift"),
          let clearStart = appState.range(of: "private func checkAutoClearIfNeeded(now: Date)"),
          let flushStart = appState.range(of: "private func flushIdleCaptionTailIfNeeded", range: clearStart.upperBound..<appState.endIndex)
    else {
        fputs("FAIL: AppState auto-clear markers should exist\n", stderr)
        return false
    }

    let autoClear = appState[clearStart.lowerBound..<flushStart.lowerBound]
    return expectEqual(
        autoClear.contains("captionDisplayMode == .liveRollUp") &&
            autoClear.contains("linePacedRoller.hasPendingOutput") &&
            autoClear.contains("return"),
        true,
        "roll-up auto-clear should not reset queued lines before they reach the green output"
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
    ("semanticVersionParsesStableVersion", testSemanticVersionParsesStableVersion),
    ("semanticVersionParsesPrereleaseVersion", testSemanticVersionParsesPrereleaseVersion),
    ("semanticVersionRejectsMalformedVersions", testSemanticVersionRejectsMalformedVersions),
    ("semanticVersionRejectsMalformedPrereleaseIdentifiers", testSemanticVersionRejectsMalformedPrereleaseIdentifiers),
    ("semanticVersionComparesNumerically", testSemanticVersionComparesNumerically),
    ("semanticVersionSortsPrereleaseBeforeStable", testSemanticVersionSortsPrereleaseBeforeStable),
    ("rollingAudioBufferRetainsOnlyConfiguredWindow", testRollingAudioBufferRetainsOnlyConfiguredWindow),
    ("rollingAudioBufferResetClearsSamplesAndOffset", testRollingAudioBufferResetClearsSamplesAndOffset),
    ("captionRowLayoutReservesBottomAlignedRowsForRollup", testCaptionRowLayoutReservesBottomAlignedRowsForRollup),
    ("captionRowLayoutDoesNotReserveRowsForBlockCaptions", testCaptionRowLayoutDoesNotReserveRowsForBlockCaptions),
    ("linePacedRollerOnlyDrainsVisibleLinesForHistory", testLinePacedRollerOnlyDrainsVisibleLinesForHistory),
    ("linePacedRollerReportsPendingOutputUntilQueuedLinesReveal", testLinePacedRollerReportsPendingOutputUntilQueuedLinesReveal),
    ("semanticVersionComparesPrereleaseIdentifiersBySemVerRules", testSemanticVersionComparesPrereleaseIdentifiersBySemVerRules),
    ("semanticVersionComparesNumericPrereleaseBeforeNonNumeric", testSemanticVersionComparesNumericPrereleaseBeforeNonNumeric),
    ("urlSessionVersionTextFetcherPreservesCancellation", testURLSessionVersionTextFetcherPreservesCancellation),
    ("urlSessionVersionTextFetcherMapsNetworkErrors", testURLSessionVersionTextFetcherMapsNetworkErrors),
    ("appStateUpdateChecksDoNotRestartInFlightChecks", testAppStateUpdateChecksDoNotRestartInFlightChecks),
    ("appStateLaunchUpdateCheckAttemptsOncePerProcess", testAppStateLaunchUpdateCheckAttemptsOncePerProcess),
    ("appStateUpdateVersionFallbacksAreNeutral", testAppStateUpdateVersionFallbacksAreNeutral),
    ("appStateStartOnlyRunsSessionAfterCaptureSucceeds", testAppStateStartOnlyRunsSessionAfterCaptureSucceeds),
    ("appStateCanceledStartDoesNotRecordFailure", testAppStateCanceledStartDoesNotRecordFailure),
    ("appStateScopesCaptureCompletionToStartupAttempt", testAppStateScopesCaptureCompletionToStartupAttempt),
    ("audioCapturePipelineSerializesControlOperations", testAudioCapturePipelineSerializesControlOperations),
    ("appStateScopesConfigurationRestartToRunningSession", testAppStateScopesConfigurationRestartToRunningSession),
    ("appStateScopesAudioCallbacksToRunningSession", testAppStateScopesAudioCallbacksToRunningSession),
    ("audioCapturePipelineBindsInstalledCallbacksToGeneration", testAudioCapturePipelineBindsInstalledCallbacksToGeneration),
    ("audioCapturePipelineCleansUpPartialStartResources", testAudioCapturePipelineCleansUpPartialStartResources),
    ("appDelegateTerminatesAfterAwaitedSessionStop", testAppDelegateTerminatesAfterAwaitedSessionStop),
    ("streamDeckAdapterUsesExplicitOutputCommands", testStreamDeckAdapterUsesExplicitOutputCommands),
    ("streamDeckFillRejectsUnavailableExternalDisplay", testStreamDeckFillRejectsUnavailableExternalDisplay),
    ("streamDeckStatusUsesTypedStateFacts", testStreamDeckStatusUsesTypedStateFacts),
    ("streamDeckFailureFactsTrackCaptureLifecycle", testStreamDeckFailureFactsTrackCaptureLifecycle),
    ("appStatePublishesStreamDeckStatusForLiveStateChanges", testAppStatePublishesStreamDeckStatusForLiveStateChanges),
    ("whisperKitTranscriberUsesBoundedStreamingBuffer", testWhisperKitTranscriberUsesBoundedStreamingBuffer),
    ("whisperKitTranscriberDoesNotReplayUnconfirmedProgress", testWhisperKitTranscriberDoesNotReplayUnconfirmedProgress),
    ("whisperKitTranscriberUsesDeterministicLiveDecodeOptions", testWhisperKitTranscriberUsesDeterministicLiveDecodeOptions),
    ("whisperKitTranscriberCapsRealtimeDecodeBacklog", testWhisperKitTranscriberCapsRealtimeDecodeBacklog),
    ("rollupOutputReservesRowsAndDisablesTextAnimation", testRollupOutputReservesRowsAndDisablesTextAnimation),
    ("rollupAutoClearWaitsForPendingOutput", testRollupAutoClearWaitsForPendingOutput)
]

var failed = 0
for (name, test) in tests {
    if test() {
        print("PASS: \(name)")
    } else {
        failed += 1
    }
}

let asyncTests: [(String, () async -> Bool)] = [
    ("updateCheckerReportsUpToDateForEqualVersion", testUpdateCheckerReportsUpToDateForEqualVersion),
    ("updateCheckerReportsAvailableForNewerVersion", testUpdateCheckerReportsAvailableForNewerVersion),
    ("updateCheckerReportsUpToDateForOlderLatestVersion", testUpdateCheckerReportsUpToDateForOlderLatestVersion),
    ("updateCheckerReportsAvailableFromPrereleaseToStable", testUpdateCheckerReportsAvailableFromPrereleaseToStable),
    ("updateCheckerManualFailureSurfacesReason", testUpdateCheckerManualFailureSurfacesReason),
    ("updateCheckerManualHTTPStatusFailureSurfacesReason", testUpdateCheckerManualHTTPStatusFailureSurfacesReason),
    ("updateCheckerManualNoStableReleaseFailureSurfacesReason", testUpdateCheckerManualNoStableReleaseFailureSurfacesReason),
    ("updateCheckerLaunchFailureReturnsIdle", testUpdateCheckerLaunchFailureReturnsIdle),
    ("updateCheckerLaunchHTTPStatusFailureReturnsIdle", testUpdateCheckerLaunchHTTPStatusFailureReturnsIdle),
    ("updateCheckerLaunchNoStableReleaseFailureReturnsIdle", testUpdateCheckerLaunchNoStableReleaseFailureReturnsIdle),
    ("updateCheckerRejectsMalformedRemoteVersion", testUpdateCheckerRejectsMalformedRemoteVersion),
    ("updateCheckerRejectsMalformedLocalVersion", testUpdateCheckerRejectsMalformedLocalVersion),
    ("updateCheckerLaunchMalformedLocalVersionReturnsIdle", testUpdateCheckerLaunchMalformedLocalVersionReturnsIdle)
]

for (name, test) in asyncTests {
    if await test() {
        print("PASS: \(name)")
    } else {
        failed += 1
    }
}

if failed > 0 {
    exit(1)
}
