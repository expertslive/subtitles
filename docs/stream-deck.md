# Stream Deck Integration

The Stream Deck integration is a native Elgato plugin that talks to the macOS app over a local loopback WebSocket. The app stays authoritative: Stream Deck keys display app status and send commands, but the plugin never assumes a command succeeded until the app publishes a new status.

## Requirements

- Stream Deck app 7.1 or later.
- macOS 12 or later.
- The `Subtitles` app running from this branch/build.
- Node dependencies installed in `StreamDeck/com.eventsubtitles.subtitles.sdPlugin` when building the plugin locally.

## Build The Plugin

From the repository root:

```bash
cd StreamDeck/com.eventsubtitles.subtitles.sdPlugin
npm install
npm test
npm run build
npm run pack
```

The packaged plugin is written to:

```text
build/com.eventsubtitles.subtitles.streamDeckPlugin
```

Double-click that `.streamDeckPlugin` file to install it in the Stream Deck app.

## Configure Keys

This v1 package does not include a generated `.streamDeckProfile`. The local Elgato tooling validates profile references but does not generate a real profile file, and the repo does not contain a GUI-exported profile. Add the plugin actions manually in Stream Deck software.

Recommended first-page layout:

- Start Session
- Stop Session
- Panic Blank
- Unblank Output
- Clear Captions
- Fill External Display
- Restore Output Window
- Health
- Session Status
- Caption Activity

The plugin manifest exposes all actions under the `Event Subtitles` category.

## Runtime Behavior

When the app starts, it opens a loopback-only control server and writes discovery information to:

```text
~/Library/Application Support/EventSubtitles/streamdeck-control.json
```

The plugin reads that file, connects to `127.0.0.1`, sends a protocol hello, and updates visible keys whenever the app broadcasts status.

Status keys show:

- `Health`: audio/app health only, no transcript text.
- `Session Status`: stopped, starting, running with elapsed time, or error.
- `Caption Activity`: clear, active, or idle plus displayed segment count.

Command keys are disabled when the latest app status says the command is not currently useful. Pressing a disabled key shows a Stream Deck alert and does not send a command.

## Safety Notes

`Panic Blank` and `Unblank Output` are separate actions by design. They are not a toggle, so a stale key state cannot accidentally unblank public output.

No caption transcript text is sent to the plugin in v1. Diagnostic logging should continue to avoid transcript content.

## Troubleshooting

- `APP OFFLINE`: launch the `Subtitles` app, or wait for the plugin reconnect backoff to pick up a restarted app.
- Keys do not update: restart the Stream Deck app or remove/re-add one plugin action to force the plugin process to reload.
- Plugin does not install: rebuild with `npm run build` and `npm run pack`, then install the generated `.streamDeckPlugin`.
- App is sandboxed in a future distribution: the app will need the network server entitlement for the loopback listener.
