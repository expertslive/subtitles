# Application Update Checks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add notify-only GitHub update checks to the app, surfaced through a custom About window.

**Architecture:** Put the testable update domain in `EventSubtitlesCore`: semantic-version parsing/comparison, update status, update constants, fetch protocol, and `UpdateChecker`. `AppState` owns the observable status and launches/manual-check tasks. The SwiftUI app replaces the standard About panel with a custom About window that reads `AppState` and offers check/copy/open actions without installing anything.

**Tech Stack:** Swift 6, SwiftUI/AppKit on macOS 14, Foundation `URLSession`, existing executable test target `EventSubtitlesCoreUnitTests`.

---

## File Map

- Create `Sources/EventSubtitlesCore/SemanticVersion.swift`
  - Pure value type for `major.minor.patch[-suffix]` parsing and comparison.
- Create `Sources/EventSubtitlesCore/UpdateChecking.swift`
  - `AppUpdateStatus`, `UpdateCheckMode`, `UpdateCheckFailureReason`, `VersionTextFetching`, `URLSessionVersionTextFetcher`, `UpdateChecker`, and URL/install-command constants.
- Modify `Sources/EventSubtitlesCoreUnitTests/main.swift`
  - Add tests for version parsing/comparison and update-check transitions with a fake fetcher.
- Modify `Sources/EventSubtitlesApp/AppState.swift`
  - Add update status state and launch/manual update-check methods.
- Create `Sources/EventSubtitlesApp/AboutWindowController.swift`
  - Own the custom About window lifetime.
- Create `Sources/EventSubtitlesApp/AboutView.swift`
  - SwiftUI About content and update controls.
- Modify `Sources/EventSubtitlesApp/EventSubtitlesApp.swift`
  - Replace `showAboutPanel()` with custom About window opening.
  - Trigger launch-time update check after the main window appears.

## Task 1: Semantic Version Value

**Files:**
- Create: `Sources/EventSubtitlesCore/SemanticVersion.swift`
- Modify: `Sources/EventSubtitlesCoreUnitTests/main.swift`

- [ ] **Step 1: Write failing tests for semantic versions**

Add these functions near the other pure unit tests in `Sources/EventSubtitlesCoreUnitTests/main.swift`:

```swift
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
```

Add them to the `tests` array:

```swift
("semanticVersionParsesStableVersion", testSemanticVersionParsesStableVersion),
("semanticVersionParsesPrereleaseVersion", testSemanticVersionParsesPrereleaseVersion),
("semanticVersionRejectsMalformedVersions", testSemanticVersionRejectsMalformedVersions),
("semanticVersionComparesNumerically", testSemanticVersionComparesNumerically),
("semanticVersionSortsPrereleaseBeforeStable", testSemanticVersionSortsPrereleaseBeforeStable),
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift run EventSubtitlesCoreUnitTests
```

Expected: compile failure mentioning `cannot find 'SemanticVersion' in scope`.

- [ ] **Step 3: Implement `SemanticVersion`**

Create `Sources/EventSubtitlesCore/SemanticVersion.swift`:

```swift
import Foundation

public struct SemanticVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init?(_ rawValue: String) {
        let normalized = Self.normalized(rawValue)
        guard !normalized.isEmpty else { return nil }

        let coreAndSuffix = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard coreAndSuffix.count == 1 || coreAndSuffix.count == 2 else { return nil }

        let coreParts = coreAndSuffix[0].split(separator: ".", omittingEmptySubsequences: false)
        guard coreParts.count == 3,
              let major = Self.parseNumericPart(coreParts[0]),
              let minor = Self.parseNumericPart(coreParts[1]),
              let patch = Self.parseNumericPart(coreParts[2]) else {
            return nil
        }

        let prerelease: String?
        if coreAndSuffix.count == 2 {
            let suffix = String(coreAndSuffix[1])
            guard Self.isValidPrerelease(suffix) else { return nil }
            prerelease = suffix
        } else {
            prerelease = nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public var stringValue: String {
        let core = "\(major).\(minor).\(patch)"
        if let prerelease {
            return "\(core)-\(prerelease)"
        }
        return core
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case let (.some(left), .some(right)):
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseNumericPart(_ value: Substring) -> Int? {
        guard !value.isEmpty, value.allSatisfy(\.isNumber) else { return nil }
        return Int(value)
    }

    private static func isValidPrerelease(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
        }
    }
}
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```bash
swift run EventSubtitlesCoreUnitTests
```

Expected: all existing tests plus the five new semantic-version tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EventSubtitlesCore/SemanticVersion.swift Sources/EventSubtitlesCoreUnitTests/main.swift
git commit -m "feat: add semantic version parsing"
```

## Task 2: Update Checker Core

**Files:**
- Create: `Sources/EventSubtitlesCore/UpdateChecking.swift`
- Modify: `Sources/EventSubtitlesCoreUnitTests/main.swift`

- [ ] **Step 1: Write failing tests for update-check behavior**

Add this fake fetcher and tests in `Sources/EventSubtitlesCoreUnitTests/main.swift`:

```swift
private struct FakeVersionTextFetcher: VersionTextFetching {
    var result: Result<String, UpdateCheckFailureReason>

    func fetchVersionText(from url: URL, timeout: TimeInterval) async -> Result<String, UpdateCheckFailureReason> {
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
    return expectEqual(status, .available(currentVersion: "3.4.0", latestVersion: "3.5.0"), "newer latest version is available")
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
    return expectEqual(status, .available(currentVersion: "3.4.0-rc1", latestVersion: "3.4.0"), "stable release updates matching prerelease")
}

private func testUpdateCheckerManualFailureSurfacesReason() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .failure(.networkUnavailable)))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(status, .failed(currentVersion: "3.4.0", reason: .networkUnavailable), "manual network failure surfaces")
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

private func testUpdateCheckerRejectsMalformedRemoteVersion() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .success("not-a-version")))
    let status = await checker.check(
        currentVersionText: "3.4.0",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(status, .failed(currentVersion: "3.4.0", reason: .invalidRemoteVersion), "malformed remote version fails")
}

private func testUpdateCheckerRejectsMalformedLocalVersion() async -> Bool {
    let checker = UpdateChecker(fetcher: FakeVersionTextFetcher(result: .success("3.4.0")))
    let status = await checker.check(
        currentVersionText: "local-dev",
        mode: .manual,
        latestVersionURL: URL(string: "https://example.com/VERSION")!
    )
    return expectEqual(status, .failed(currentVersion: "local-dev", reason: .invalidLocalVersion), "malformed local version fails")
}
```

Add the async tests to the async part of `main.swift` near other async calls:

```swift
allPassed = await testUpdateCheckerReportsUpToDateForEqualVersion() && allPassed
allPassed = await testUpdateCheckerReportsAvailableForNewerVersion() && allPassed
allPassed = await testUpdateCheckerReportsUpToDateForOlderLatestVersion() && allPassed
allPassed = await testUpdateCheckerReportsAvailableFromPrereleaseToStable() && allPassed
allPassed = await testUpdateCheckerManualFailureSurfacesReason() && allPassed
allPassed = await testUpdateCheckerLaunchFailureReturnsIdle() && allPassed
allPassed = await testUpdateCheckerRejectsMalformedRemoteVersion() && allPassed
allPassed = await testUpdateCheckerRejectsMalformedLocalVersion() && allPassed
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift run EventSubtitlesCoreUnitTests
```

Expected: compile failure mentioning `VersionTextFetching`, `UpdateChecker`, or `AppUpdateStatus` not found.

- [ ] **Step 3: Implement update-check core**

Create `Sources/EventSubtitlesCore/UpdateChecking.swift`:

```swift
import Foundation

public enum UpdateCheckMode: Equatable, Sendable {
    case launch
    case manual

    public var timeout: TimeInterval {
        switch self {
        case .launch:
            return 3
        case .manual:
            return 5
        }
    }
}

public enum UpdateCheckFailureReason: Equatable, Sendable {
    case networkUnavailable
    case noStableReleaseFound
    case httpStatus(Int)
    case invalidRemoteVersion
    case invalidLocalVersion

    public var displayText: String {
        switch self {
        case .networkUnavailable:
            return "Network unavailable or GitHub could not be reached."
        case .noStableReleaseFound:
            return "No stable release was found."
        case .httpStatus(let status):
            return "GitHub returned HTTP \(status)."
        case .invalidRemoteVersion:
            return "Release VERSION was not parseable."
        case .invalidLocalVersion:
            return "Installed app version was not parseable."
        }
    }
}

public enum AppUpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(currentVersion: String, latestVersion: String)
    case failed(currentVersion: String, reason: UpdateCheckFailureReason)
}

public enum AppUpdateConstants {
    public static let latestVersionURL = URL(string: "https://github.com/expertslive/subtitles/releases/latest/download/VERSION")!
    public static let latestReleaseURL = URL(string: "https://github.com/expertslive/subtitles/releases/latest")!
    public static let installCommand = "curl -fsSL https://github.com/expertslive/subtitles/releases/latest/download/install.sh | bash"
}

public protocol VersionTextFetching: Sendable {
    func fetchVersionText(from url: URL, timeout: TimeInterval) async -> Result<String, UpdateCheckFailureReason>
}

public struct URLSessionVersionTextFetcher: VersionTextFetching {
    public init() {}

    public func fetchVersionText(from url: URL, timeout: TimeInterval) async -> Result<String, UpdateCheckFailureReason> {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.networkUnavailable)
            }
            guard http.statusCode != 404 else {
                return .failure(.noStableReleaseFound)
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failure(.httpStatus(http.statusCode))
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(.invalidRemoteVersion)
            }
            return .success(text)
        } catch {
            return .failure(.networkUnavailable)
        }
    }
}

public struct UpdateChecker: Sendable {
    private let fetcher: VersionTextFetching

    public init(fetcher: VersionTextFetching = URLSessionVersionTextFetcher()) {
        self.fetcher = fetcher
    }

    public func check(
        currentVersionText: String,
        mode: UpdateCheckMode,
        latestVersionURL: URL = AppUpdateConstants.latestVersionURL
    ) async -> AppUpdateStatus {
        let normalizedCurrent = Self.normalizedVersionText(currentVersionText)
        guard let current = SemanticVersion(normalizedCurrent) else {
            return .failed(currentVersion: normalizedCurrent.isEmpty ? currentVersionText : normalizedCurrent, reason: .invalidLocalVersion)
        }

        let result = await fetcher.fetchVersionText(from: latestVersionURL, timeout: mode.timeout)
        switch result {
        case .failure(let reason):
            if mode == .launch {
                return .idle
            }
            return .failed(currentVersion: current.stringValue, reason: reason)
        case .success(let text):
            let normalizedLatest = Self.normalizedVersionText(text)
            guard let latest = SemanticVersion(normalizedLatest) else {
                if mode == .launch {
                    return .idle
                }
                return .failed(currentVersion: current.stringValue, reason: .invalidRemoteVersion)
            }
            if latest > current {
                return .available(currentVersion: current.stringValue, latestVersion: latest.stringValue)
            }
            return .upToDate(currentVersion: current.stringValue)
        }
    }

    public static func normalizedVersionText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```bash
swift run EventSubtitlesCoreUnitTests
```

Expected: all tests pass, including the new update-check tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/EventSubtitlesCore/UpdateChecking.swift Sources/EventSubtitlesCoreUnitTests/main.swift
git commit -m "feat: add update check core"
```

## Task 3: AppState Update Integration

**Files:**
- Modify: `Sources/EventSubtitlesApp/AppState.swift`

- [ ] **Step 1: Add update state and checker properties**

In `AppState`, add observable status near other operator-visible state:

```swift
var updateStatus: AppUpdateStatus = .idle
```

Add ignored implementation fields near the other `@ObservationIgnored` properties:

```swift
@ObservationIgnored private let updateChecker = UpdateChecker()
@ObservationIgnored private var updateCheckTask: Task<Void, Never>?
```

- [ ] **Step 2: Add app-version helper and update methods**

Add these methods in `AppState` near other operator action methods:

```swift
func checkForUpdatesOnLaunch() {
    guard updateStatus != .checking else { return }
    runUpdateCheck(mode: .launch)
}

func checkForUpdatesManually() {
    guard updateStatus != .checking else { return }
    runUpdateCheck(mode: .manual)
}

func copyInstallCommandToClipboard() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(AppUpdateConstants.installCommand, forType: .string)
}

func openLatestReleasePage() {
    NSWorkspace.shared.open(AppUpdateConstants.latestReleaseURL)
}

var currentAppVersionText: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.3.0"
}

var currentAppBuildText: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "8"
}

private func runUpdateCheck(mode: UpdateCheckMode) {
    updateCheckTask?.cancel()
    updateStatus = .checking
    let currentVersion = currentAppVersionText
    let checker = updateChecker
    updateCheckTask = Task { [weak self] in
        let status = await checker.check(currentVersionText: currentVersion, mode: mode)
        await MainActor.run {
            guard let self, !Task.isCancelled else { return }
            self.updateStatus = status
            self.updateCheckTask = nil
        }
    }
}
```

- [ ] **Step 3: Stop update task during cleanup**

In existing cleanup/termination paths where `pendingSaveTask` and other tasks are cancelled, add:

```swift
updateCheckTask?.cancel()
updateCheckTask = nil
```

If there is no central cleanup path for this yet, add it to `deinit`:

```swift
deinit {
    updateCheckTask?.cancel()
}
```

- [ ] **Step 4: Build**

Run:

```bash
swift build --product EventSubtitles
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/EventSubtitlesApp/AppState.swift
git commit -m "feat: wire update checks into app state"
```

## Task 4: Custom About Window

**Files:**
- Create: `Sources/EventSubtitlesApp/AboutView.swift`
- Create: `Sources/EventSubtitlesApp/AboutWindowController.swift`

- [ ] **Step 1: Create the About SwiftUI view**

Create `Sources/EventSubtitlesApp/AboutView.swift`:

```swift
import EventSubtitlesCore
import SwiftUI

struct AboutView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            updateSection
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 460, minHeight: 300)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subtitles")
                .font(.title)
                .fontWeight(.semibold)
            Text("Version \(state.currentAppVersionText) · Build \(state.currentAppBuildText)")
                .foregroundStyle(.secondary)
            Text("Offline live subtitles and Dutch/English translation for events. Session logs stay local.")
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Updates")
                .font(.headline)
            Text(updateStatusText)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = updateFailureDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Check for Updates") {
                    state.checkForUpdatesManually()
                }
                .disabled(state.updateStatus == .checking)

                if updateAvailable {
                    Button("Copy Install Command") {
                        state.copyInstallCommandToClipboard()
                    }
                    Button("Open Release Page") {
                        state.openLatestReleasePage()
                    }
                }
            }
        }
    }

    private var updateAvailable: Bool {
        if case .available = state.updateStatus {
            return true
        }
        return false
    }

    private var updateFailureDetail: String? {
        if case .failed(_, let reason) = state.updateStatus {
            return reason.displayText
        }
        return nil
    }

    private var updateStatusText: String {
        switch state.updateStatus {
        case .idle:
            return "Update status unknown."
        case .checking:
            return "Checking for updates..."
        case .upToDate:
            return "You are up to date."
        case .available(_, let latestVersion):
            if state.isRunning || state.isStarting {
                return "Update available: \(latestVersion). Update after the current session."
            }
            return "Update available: \(latestVersion)."
        case .failed:
            return "Could not check for updates."
        }
    }
}
```

- [ ] **Step 2: Create the window controller**

Create `Sources/EventSubtitlesApp/AboutWindowController.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show(appState: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = AboutView()
            .environment(appState)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Subtitles"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
```

- [ ] **Step 3: Build**

Run:

```bash
swift build --product EventSubtitles
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/EventSubtitlesApp/AboutView.swift Sources/EventSubtitlesApp/AboutWindowController.swift
git commit -m "feat: add custom about update view"
```

## Task 5: Wire Menu And Launch Check

**Files:**
- Modify: `Sources/EventSubtitlesApp/EventSubtitlesApp.swift`

- [ ] **Step 1: Replace standard About panel state**

In `EventSubtitlesApp`, add:

```swift
@State private var aboutWindowController = AboutWindowController()
```

Remove the existing `showAboutPanel()` implementation.

- [ ] **Step 2: Wire the About menu button**

Change the existing app-info command to:

```swift
CommandGroup(replacing: .appInfo) {
    Button("About Subtitles") {
        aboutWindowController.show(appState: appState)
    }
}
```

- [ ] **Step 3: Run launch update check after main window appears**

Change the `OperatorView().onAppear` block to:

```swift
.onAppear {
    appDelegate.state = appState
    appState.checkForUpdatesOnLaunch()
}
```

- [ ] **Step 4: Remove unused imports or helpers**

If `AppKit` is no longer needed in `EventSubtitlesApp.swift` after removing `showAboutPanel()`, keep it only if another symbol in the file still needs it. Do not remove `SwiftUI`.

- [ ] **Step 5: Build**

Run:

```bash
swift build --product EventSubtitles
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/EventSubtitlesApp/EventSubtitlesApp.swift
git commit -m "feat: open custom about window"
```

## Task 6: Final Verification

**Files:**
- No required source edits.

- [ ] **Step 1: Run core unit tests**

Run:

```bash
swift run EventSubtitlesCoreUnitTests
```

Expected: all tests pass, including semantic-version and update-check tests.

- [ ] **Step 2: Run smoke tests**

Run:

```bash
swift run EventSubtitlesSmokeTests
```

Expected: `Smoke tests passed`.

- [ ] **Step 3: Build the app bundle**

Run:

```bash
./scripts/build_app_bundle.sh
```

Expected: command prints `build/EventSubtitles.app`.

- [ ] **Step 4: Manual About verification**

Run:

```bash
open build/EventSubtitles.app
```

Expected manual checks:

- **Subtitles → About Subtitles** opens the custom window.
- The About window shows current version/build.
- Before a manual check finishes, idle state reads `Update status unknown.` or checking state reads `Checking for updates...`.
- **Check for Updates** reaches `You are up to date.` or `Update available: <version>.`.
- If update is available, **Copy Install Command** places this exact string on the clipboard:

```bash
curl -fsSL https://github.com/expertslive/subtitles/releases/latest/download/install.sh | bash
```

- If update is available, **Open Release Page** opens `https://github.com/expertslive/subtitles/releases/latest`.

- [ ] **Step 5: Commit any final fixes**

If manual verification required source fixes:

```bash
git add Sources/EventSubtitlesApp Sources/EventSubtitlesCore Sources/EventSubtitlesCoreUnitTests
git commit -m "fix: finalize update check integration"
```

If no fixes were needed, do not create an empty commit.

## Self-Review

- Spec coverage:
  - Launch-time update check: Task 3 and Task 5.
  - Manual About check: Task 4 and Task 5.
  - Version comparison including prerelease local versions: Task 1 and Task 2.
  - Notify-only install command/release page: Task 2, Task 3, and Task 4.
  - Silent launch failures and visible manual failures: Task 2 and Task 4.
  - No live-session interruption and running-session wording: Task 4.
  - No automatic install/download of artifacts: all tasks avoid install execution and only fetch `VERSION`.
- Placeholder scan: no task uses placeholder-only instructions; each implementation step includes code or exact command.
- Type consistency:
  - `SemanticVersion`, `UpdateChecker`, `AppUpdateStatus`, `UpdateCheckMode`, `UpdateCheckFailureReason`, and `VersionTextFetching` are defined before use.
  - `AppState` methods used by `AboutView` are defined before the view task.
