# EventSubtitles

A native macOS app, displayed as `Subtitles`, for offline live subtitles and Dutch/English translation at events.

## Documentation

Start with the documentation index in [docs/README.md](docs/README.md).

- [Architecture](docs/architecture.md)
- [Event runbook](docs/event-runbook.md)
- [Lessons learned](docs/lessons-learned.md)
- [Release process](docs/release-process.md)
- [Original project prompt](initial_prompt.txt)

## Features

- operator screen for controls, glossary, audio level, and transcript history
- persistent operator strip with full workspaces for Live, Style, Glossary, Logs, Models, Translation, Audio, and Output
- second-window subtitle output with chroma green background
- configurable font, size, colors, margins, and two/three-line layout
- fine-position controls for nudging captions left/right/up/down
- calm public-caption display modes with draft/stable separation
- automatic sleep prevention while a subtitle session is running
- local pipeline interfaces for ASR and translation engines
- task-focused capture modes for demo captions, live WhisperKit subtitles, and audio-only recording
- WhisperKit/Core ML live ASR engine path
- glossary term editor with add/edit/delete rows, alias groups, validation, suggestions, and JSON/CSV import/export
- timestamped session logging with transcripts, SRTs, JSONL segments, and raw input audio
- custom macOS app icon bundled into `build/EventSubtitles.app`

## Run

```bash
swift run EventSubtitles
```

The app starts in a safe operator UI with a persistent left strip and workspaces on the right. Use the `Capture` picker to choose between demo captions, live local subtitles, or audio-only recording. Use a USB-C audio interface for event audio rather than the MacBook headphone jack. By default, pressing Start keeps the Mac and output display awake until Stop.

For actual event use, build a macOS app bundle so microphone permissions are tied to the app:

```bash
./scripts/build_app_bundle.sh
open build/EventSubtitles.app
```

To prepare a WhisperKit model from Terminal before going offline:

```bash
swift run PrepareWhisperModel large-v3-v20240930_626MB
```

## Download

GitHub releases include a zipped macOS app bundle:

```text
EventSubtitles-v0.2.2-macos-arm64.zip
```

Unzip it and launch `EventSubtitles.app`. The app is ad-hoc signed for local testing, so macOS may require opening it from Finder with Control-click > Open the first time.

Starting a session creates a timestamped folder under:

```text
~/Documents/EventSubtitles/YYYY-MM-DD_HH-mm-ss_<session-name>_<mode>/
```

Each session folder contains:

- `metadata.json`
- `glossary.txt`
- `source-transcript.txt`
- `display-transcript.txt`
- `segments.jsonl`
- `draft.srt`
- `source.srt`
- `display.srt`
- `input-audio.caf`

`source-transcript.txt` is the spoken-word transcript. `display-transcript.txt` is what was shown on screen after glossary correction and optional translation. `source.srt` and `display.srt` are regenerated after every final segment with approximate timings. `draft.srt` mirrors the display SRT for quick review.

## Test

```bash
swift run EventSubtitlesSmokeTests
```

## Model Plan

The intended production path is:

```text
USB audio interface
  -> local ASR engine, initially WhisperKit/Core ML
  -> draft buffer and stability gate
  -> glossary correction
  -> optional local EN/NL or NL/EN translation
  -> calm caption scheduler and subtitle composer
  -> full-screen HDMI/chroma-key output
```

The app includes a `Live subtitles` capture option backed by WhisperKit. Use the Models workspace to prepare/download a Core ML model before the event, while online. Once cached locally, the live path can run offline. The Models workspace also shows offline readiness, app memory usage, and a shortcut to Activity Monitor for CPU/GPU checks.

For translation, the app has two local paths:

- `Glossary/rules`: deterministic fallback for demos and terminology protection.
- `Local command`: calls an offline translator executable with text on stdin and reads translated text from stdout. The argument template supports `{source}` and `{target}` tokens such as `--from {source} --to {target}`.

The runtime is optimized around Mac-native WhisperKit on Apple Silicon.
