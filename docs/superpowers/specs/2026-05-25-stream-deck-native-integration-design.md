# Native Stream Deck Integration Design

## Purpose

Add an installable Elgato Stream Deck plugin for `Subtitles` that provides foreground-independent control of the live-event functions and compact live operational status. The integration is intended for a dedicated event Mac where deliberate operator actions and clear failure states matter more than broad remote configuration.

## Scope

Version one includes these command actions:

- Start session.
- Stop session.
- Panic blank.
- Unblank output.
- Clear captions.
- Fill the selected external display.
- Restore the output window after a fill operation.

Version one also exposes status sufficient to operate with confidence:

- Application online/offline state.
- Session state and elapsed time.
- Output blank/live state.
- Output display state.
- Caption activity state.
- Audio health state.
- Current app error indication.
- Displayed segment count.

Version one does not:

- Send caption or transcript text to Stream Deck.
- Configure language, capture mode, display flow, typography, glossary, audio device, or model settings.
- Launch `Subtitles` from a key press.
- Control the physical Stream Deck without Elgato Stream Deck software.
- Authenticate individual local plugin clients.

## User Workflow

Setup on an event Mac is:

1. Install `Subtitles.app`.
2. Install the packaged `Subtitles.streamDeckPlugin` in Elgato Stream Deck software.
3. Accept or select the plugin's auto-installed recommended Stream Deck profile.
4. Launch `Subtitles`.

While the app is not running, plugin keys visibly report `APP OFFLINE` and command key presses make no change. Once the app is running, the plugin reconnects automatically and renders its current status.

The plugin must work while another macOS application is focused or the `Subtitles` window is behind other windows.

## Architecture

`Subtitles` owns a small local status/control server. It starts when the app starts and remains available independent of whether a subtitle session is active. The server binds only to `127.0.0.1` using an operating-system-selected available port and speaks a versioned JSON protocol over WebSocket at `/streamdeck/v1`.

After successfully binding, the app atomically writes a discovery record to `~/Library/Application Support/EventSubtitles/streamdeck-control.json` containing the loopback host, selected port, protocol version, application process identifier, and generation timestamp. The plugin reads this record before each connection attempt and treats it as stale if connection fails. The app removes its discovery record on orderly shutdown when it still owns the recorded process identifier. This avoids assuming an unregistered fixed port is available on an event Mac.

An installable Stream Deck plugin is a separate packaged component executed by Stream Deck software. The plugin connects to the loopback server, sends typed command messages on key presses, receives status snapshots and updates, and updates button titles, imagery, and states. It automatically reconnects after application launch, restart, or a temporary connection loss.

The application remains authoritative for every state transition. The plugin is a client and display surface only; it does not infer that a requested action succeeded before the app reports the resulting status.

### WebSocket Implementation

The app-side server will use SwiftNIO with `NIOHTTP1` and `NIOWebSocket` for loopback HTTP upgrade handling, WebSocket framing, and connection lifecycle. Implementing RFC 6455 framing directly on `NWListener` is not part of this work. `URLSessionWebSocketTask` is not suitable because it supplies a client rather than a server.

### App-Side Components

- `StreamDeckControlServer`: owns SwiftNIO loopback listener lifecycle, discovery-record writing/removal, WebSocket clients, JSON decoding/encoding, status broadcast, and rejection of unsupported messages.
- `StreamDeckCommand`: typed command enumeration covering only v1 actions.
- `StreamDeckStatusSnapshot`: codable, versioned projection of event-relevant `AppState` values.
- `AppState` command dispatch integration: executes accepted commands on the main actor and triggers fresh status publication.

### Plugin-Side Components

- Stream Deck plugin manifest with purpose-built command/status actions, a predefined auto-installed profile, and macOS support metadata.
- TypeScript/Node.js plugin process using `@elgato/streamdeck` v2 or later, manifest `SDKVersion: 3`, the Stream Deck bundled Node.js 20 runtime, and Stream Deck software 7.1 or later.
- Local app connection/reconnection service.
- Status-to-key rendering logic.
- Static assets and a recommended bundled profile layout.

## Stream Deck Surface

The bundled profile provides dedicated keys rather than one configurable generic command key.

| Key | Press Action | Visible Status |
| --- | --- | --- |
| Start | `startSession` | Stopped, Starting, or Live |
| Stop | `stopSession` | Whether a session can be stopped |
| Panic Blank | `panicBlank` | Output Blanked when engaged |
| Unblank | `unblankOutput` | Output Live when engaged |
| Clear Captions | `clearCaptions` | Captions Active, Idle, or Clear |
| Fill Display | `fillExternalDisplay` | Hidden, Window, or Filled |
| Restore Window | `restoreOutputWindow` | Hidden, Window, or Filled |
| Health | None in v1 | Ready, Audio warning, or App error |
| Session | None in v1 | Session state, elapsed time, and segment count |
| Caption Activity | None in v1 | Active, Idle, or Clear |

The profile may place the status-only actions alongside command keys according to available Stream Deck key count, but all listed commands and status information must be available in the distributed first-version profile.

## Protocol

The app and plugin use versioned JSON messages over a loopback-only WebSocket connection.

Initial connection handshake:

```json
{ "type": "hello", "protocolVersion": 1, "pluginVersion": "1.0.0" }
```

Command request and result:

```json
{ "type": "command", "id": "unique-message-id", "command": "panicBlank" }
{ "type": "commandResult", "id": "unique-message-id", "accepted": true }
{ "type": "commandResult", "id": "unique-message-id", "accepted": false, "reason": "invalidState" }
```

For a syntactically valid command, v1 rejection reasons are `invalidState`, `noExternalDisplay`, and `internalError`. Malformed messages and unsupported protocol versions are closed without an application-state change and recorded in diagnostics.

Status update:

```json
{
  "type": "status",
  "protocolVersion": 1,
  "status": {
    "sessionState": "running",
    "elapsedText": "00:12:45",
    "displayState": "filled",
    "outputState": "live",
    "captionState": "active",
    "audioState": "healthy",
    "errorSummary": null,
    "displayedSegmentCount": 42
  }
}
```

### Commands

Supported v1 commands are:

```text
startSession
stopSession
panicBlank
unblankOutput
clearCaptions
fillExternalDisplay
restoreOutputWindow
```

### Status Values

Status is restricted to compact operational information:

```text
sessionState: stopped | starting | running | error
displayState: hidden | window | filled
outputState: live | blanked
captionState: clear | active | idle
audioState: unknown | healthy | silent | warning
elapsedText: formatted session duration
errorSummary: string or null, always present
displayedSegmentCount: number of displayed events recorded in the current session
```

`APP OFFLINE` is plugin-derived state while no connection to the app is active, rather than a value emitted by the app.

No caption text, transcript content, glossary content, or recorded media metadata is sent over the control protocol in version one.

`sessionState` reflects session lifecycle only. It is `error` when a session start attempt fails without a running session; if an audio, translation, or logging error occurs while the session remains running, `sessionState` remains `running` and `errorSummary` carries the warning. `errorSummary` is always included as either `null` or a single-line operator-safe summary capped at 120 characters.

## Command Semantics

All commands are executed by the app on its main actor, using the existing state-owning methods wherever applicable.

| Command | Required Behavior |
| --- | --- |
| `startSession` | Invoke existing `AppState.start()` only while stopped. Return `accepted: false` with `invalidState` while starting or running. |
| `stopSession` | Invoke existing `AppState.stop()` while starting or running. Return `accepted: false` with `invalidState` while stopped. |
| `panicBlank` | Immediately blank output and clear current/pending captions. Repeated execution remains safe. |
| `unblankOutput` | Explicitly mark output live. Never restore text cleared by panic blank. Repeated execution remains safe. |
| `clearCaptions` | Clear current and pending captions without changing output blank/live state. |
| `fillExternalDisplay` | Fill only a connected non-main display. Return `accepted: false` with `noExternalDisplay` rather than filling the Mac's main screen when no external display is available. |
| `restoreOutputWindow` | Invoke existing `AppState.restoreOutputWindow()` to return a filled output to its windowed mode. |

Safety-critical output controls are explicit operations, not toggles. This avoids a key press producing the inverse of the operator's intent when a key display is stale or recovery occurs during a connection transition.

## Status Publication

The app sends a complete status snapshot after protocol handshake and after processing any valid command. It also sends updated snapshots when relevant application state changes:

- Session begins starting, starts, stops, or fails.
- Session elapsed time changes, no more than once per second.
- Output changes between blanked and live.
- Output window becomes hidden, windowed, or filled.
- Public captions become active, idle, or clear.
- Audio health changes category.
- An error appears or is cleared.
- Displayed segment count changes.

Caption state is based on existing caption activity tracking:

- `clear`: no public caption is currently displayed.
- `active`: non-empty `publicCaptionText` changed within the previous 2 seconds.
- `idle`: non-empty `publicCaptionText` is still visible at least 2 seconds after its last change.

Audio status uses derived operator-relevant health rather than raw meter data, with these deterministic v1 rules:

- `warning`: the selected audio input is unavailable, no audio device is available, or the current error is an audio capture/input restart failure.
- `unknown`: the session is stopped, the capture engine is `Demo captions`, or a real capture session has run for less than 10 seconds without yet hearing input.
- `healthy`: a running non-demo session has audio level greater than `0.05` now or had such a sample within the previous 10 seconds.
- `silent`: a running non-demo session has passed the initial 10-second grace interval, has an available input and no audio failure, but has not had audio level greater than `0.05` during the previous 10 seconds.

The existing `sessionSegmentCount` is published as `displayedSegmentCount`: it is reset when a session log starts and incremented when finalized displayed events are recorded. It is not a lifetime total and not a count of currently visible lines.

## Failure And Security Behavior

If the app is not running, not reachable, or the WebSocket disconnects, the plugin:

- Displays `APP OFFLINE` state immediately.
- Does not attempt to execute commands as local shortcuts or queue stale commands.
- Attempts reconnection automatically in the background after reading the current discovery record, waiting 1 second after the first failure, 2 seconds after the second, then 5 seconds between subsequent attempts. A successful connection resets the delay.

If Stream Deck software or the plugin is closed, disconnected, or crashes, `Subtitles` continues its existing caption and output operation without interruption.

The app:

- Accepts connections only through `127.0.0.1`, not LAN interfaces.
- Rejects malformed protocol messages, unsupported protocol versions, and unknown commands without changing app state.
- Records enough diagnostic information to troubleshoot rejected messages and connection status without logging transcript content or `publicCaptionText`.

Version one intentionally uses no pairing token. This enables zero-configuration installation on an event Mac, at the cost that another local process on the same logged-in Mac could attempt to send loopback commands. The integration assumes an event machine without untrusted locally running software. Stronger local authentication may be added later without broadening the v1 functional scope.

The existing application bundle is not sandboxed. Version one preserves that packaging model. Enabling App Sandbox later requires revisiting the server entitlement (`com.apple.security.network.server`) and the discovery-record sharing mechanism; hardened runtime alone does not impose App Sandbox network entitlements.

## Packaging And Documentation

The repository will distribute:

- The existing packaged macOS application bundle, extended with its local Stream Deck service.
- An installable `.streamDeckPlugin` plugin package.
- A predefined recommended Stream Deck profile included in the plugin manifest with `AutoInstall: true`.
- Operator documentation for installation, selecting the profile, verifying online status, and testing event-critical keys before show operation.

The Stream Deck plugin requires Elgato Stream Deck software to be installed and running. It is not a native USB/HID driver for the hardware itself.

The plugin targets Stream Deck software 7.1 or later, uses manifest `SDKVersion: 3`, uses the bundled Node.js 20 runtime, and uses `@elgato/streamdeck` v2 or later. The profile packaging relies on the official manifest `Profiles` entry and `AutoInstall` behavior.

## Testing And Verification

### App-Side Automated Tests

- Encode/decode valid protocol messages.
- Reject invalid JSON, unknown commands, and unsupported protocol versions.
- Project `AppState` into each status enum/value combination.
- Verify start/stop guards.
- Verify `panicBlank` clears captions and remains blank on repeated calls.
- Verify `unblankOutput` never restores cleared captions.
- Verify `clearCaptions` does not alter blank/live output state.
- Verify fill display rejects with `noExternalDisplay` rather than using the main screen.
- Verify restore output delegates to windowed output behavior.
- Verify caption-state and audio-state thresholds with fixed timestamps.
- Verify discovery records are atomically published and stale records are not trusted after failed connection.

### Plugin Automated Tests

- Render disconnected state as `APP OFFLINE`.
- Render each session, output, display, caption, audio, and error status.
- Send correct v1 command message for each command key.
- Reconnect and refresh status after the app becomes reachable.
- Drop pending/stale actions across disconnects.
- Apply the specified reconnect backoff sequence.

### Manual Event Verification

- Plugin installation and bundled profile installation on a clean event Mac setup.
- App launch after Stream Deck is already running.
- Stream Deck launch after the app is already running.
- App restart and plugin automatic reconnection.
- Stream Deck software restart during a live session.
- Background control while another app is frontmost.
- Start, stop, clear, fill-display, restore-window, panic-blank, and unblank flows.
- Fill-display rejection when no external monitor is attached.
- Panic blank during visible live captions and validation that unblank does not restore stale content.
- Offline key behavior when `Subtitles` is not running.

## Implementation Constraints

- Preserve the existing `AppState` ownership of live operations; the integration must not introduce duplicate session or output state.
- Keep remote-control scope limited to approved live-event commands.
- Avoid transmitting audience-visible text in version one.
- Keep the local service independent of active transcription so status and recovery remain available while stopped.
- Use official Stream Deck plugin packaging and SDK-supported action/state rendering.

## Future Extensions

Possible later versions, outside this scope:

- Pairing tokens or stronger local authorization.
- Additional status presentation for hardware with more keys or encoders.
- Explicit show-output-window action.
- Setup controls such as test card or capture mode selection.
- Marketplace distribution workflows.
