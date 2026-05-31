# Application Update Checks Design

## Purpose

Let `Subtitles` tell an operator when a newer GitHub Release is available without making the app responsible for replacing itself. The app should stay quiet during live operation, avoid background installation risk, and reuse the existing release/install pipeline as the only way to change files on disk.

## Scope

In scope:

- A launch-time update check against the public GitHub Release `VERSION` asset.
- A manual **Check for Updates** action in a custom **About Subtitles** window.
- Version comparison between the installed bundle version and the latest release version.
- A notify-only update state that can show the install command and release page link.
- Tests for version comparison and update-check state transitions using a mocked network client.

Out of scope:

- Automatic app installation.
- Replacing the running app bundle from inside the app.
- Downloading app zip or Stream Deck plugin artifacts in the app.
- Updating Elgato Stream Deck itself.
- Checking prerelease versions.
- Mandatory update enforcement.

## User Workflow

### Automatic check

1. The app launches.
2. After the main window is ready, the app checks the latest stable release version once.
3. The check uses a short timeout and does not block the UI.
4. If no update is available, nothing interrupts the operator.
5. If an update is available, the result is stored and shown the next time the operator opens **About Subtitles**.
6. If the network check fails, the launch-time failure is silent unless the operator later opens About and manually checks.

### Manual check

1. The operator chooses **Subtitles → About Subtitles**.
2. The app opens a custom About window.
3. The operator can press **Check for Updates**.
4. The About window shows one of:
   - `You are up to date.`
   - `Update available: <latest version>.`
   - `Could not check for updates.`
5. If an update is available, the About window offers:
   - **Copy Install Command**
   - **Open Release Page**

### Installation handoff

When an update is available, the app does not run the installer. It gives the operator this command:

```bash
curl -fsSL https://github.com/expertslive/subtitles/releases/latest/download/install.sh | bash
```

The command continues to be owned by the multi-Mac install pipeline. The operator runs it from Terminal when ready.

## Architecture

### Release endpoint

The app checks:

```text
https://github.com/expertslive/subtitles/releases/latest/download/VERSION
```

The response is expected to be a single semantic version string such as `3.4.0`. The `/latest/` URL intentionally resolves only stable GitHub Releases, not prereleases.

The release page link shown in the UI is:

```text
https://github.com/expertslive/subtitles/releases/latest
```

### Components

- `UpdateChecker`
  - Fetches the latest version text.
  - Applies a short request timeout.
  - Parses and validates the version string.
  - Compares it with the installed version.

- `AppUpdateStatus`
  - Represents UI state:
    - `idle`
    - `checking`
    - `upToDate(currentVersion)`
    - `available(currentVersion, latestVersion)`
    - `failed(currentVersion, message)`

- `SemanticVersion`
  - Parses `major.minor.patch`.
  - Compares versions numerically, not lexically.
  - Rejects malformed values instead of guessing.

- `AboutWindowController` or SwiftUI About scene wrapper
  - Owns the custom About window lifetime.
  - Opens from the existing **About Subtitles** menu command.
  - Shows app version, short product description, update status, and update actions.

### State ownership

`AppState` owns update status so the launch check and About window observe the same result. Closing the About window does not clear the update result. Dismissal is session-local: the next app launch checks again and can show the update again.

The launch check runs once per app process. Manual **Check for Updates** can run again at any time.

## UI Design

The standard macOS About panel is replaced with a custom **About Subtitles** window because the standard panel is not suited for dynamic controls.

The window shows:

- App name: `Subtitles`
- Current version from `CFBundleShortVersionString`
- Build/version detail from `CFBundleVersion`
- Short description:
  `Offline live subtitles and Dutch/English translation for events. Session logs stay local.`
- Update section:
  - status text
  - **Check for Updates**
  - **Copy Install Command** when an update is available
  - **Open Release Page** when an update is available

If `state.isRunning || state.isStarting`, an available update is worded as:

```text
Update available: <latest version>. Update after the current session.
```

The app does not show a live-operator banner or modal alert for updates.

## Error Handling

- Launch-time network errors are quiet.
- Manual check errors are shown in About as `Could not check for updates.` with a short detail.
- Malformed `VERSION` content is treated as a failed check.
- If the installed bundle version cannot be read, the About window still opens and update checking reports a failed local-version state.
- The app does not retry automatically after failure. The operator can press **Check for Updates** again.

## Security And Safety

- The app only downloads a small text `VERSION` file.
- The app does not execute downloaded scripts.
- The app does not ask for `sudo`.
- The app does not modify `/Applications`.
- The install command is copied to the clipboard only after the operator presses **Copy Install Command**.
- Updates are never presented as urgent while a session is starting or running.

## Testing And Verification

Automated tests:

- `SemanticVersion` parses valid `major.minor.patch` values.
- `SemanticVersion` rejects malformed values.
- Numeric comparison handles cases such as `3.10.0 > 3.9.0`.
- `UpdateChecker` reports `upToDate` when current equals latest.
- `UpdateChecker` reports `available` when latest is greater than current.
- `UpdateChecker` reports `upToDate` when latest is older than current.
- `UpdateChecker` reports `failed` on network errors and malformed remote version text.

Manual verification:

- Launch app with network available and current version matching latest: About says up to date.
- Launch app with mocked or test release newer than current: About says update available.
- Open About and press **Check for Updates**: status refreshes.
- Press **Copy Install Command**: clipboard contains the install command.
- Press **Open Release Page**: browser opens the latest release page.
- Start a session while update is available: About says to update after the current session.
- Disable network and press **Check for Updates**: About shows a non-crashing failure state.

## Implementation Constraints

- Do not introduce Sparkle or another updater framework in this design.
- Do not parse GitHub JSON in the app; use the existing `VERSION` asset.
- Keep network code behind a small protocol so tests can inject a fake fetcher.
- Keep update state separate from transcription/session logic except for the read-only session-running wording.
- Do not add live-session UI interruptions for update availability.

## Future Extensions

- Add an **Open Terminal With Install Command** flow.
- Add a signed/notarized updater once Developer ID signing exists.
- Add a configurable update channel for prereleases.
- Add a preference for disabling automatic launch checks.
