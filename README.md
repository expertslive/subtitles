# EventSubtitles

A native macOS prototype for offline live subtitles and Dutch/English translation at events.

## Documentation

Start with the documentation index in [docs/README.md](docs/README.md).

- [Architecture](docs/architecture.md)
- [Event runbook](docs/event-runbook.md)
- [Original project prompt](initial_prompt.txt)

## Features

- operator screen for controls, glossary, audio level, and transcript history
- second-window subtitle output with chroma green background
- configurable font, size, colors, margins, and two/three-line layout
- local pipeline interfaces for ASR and translation engines
- selectable simulator/audio-only engines so the UI and recording workflow can be tested before WhisperKit/translation models are wired in
- WhisperKit/Core ML live ASR engine path
- timestamped session logging with transcripts, SRTs, JSONL segments, and raw input audio

## Run

```bash
swift run EventSubtitles
```

The app currently uses a simulated transcript engine plus real microphone/input level monitoring. Use a USB-C audio interface for event audio rather than the MacBook headphone jack.

For actual event use, build a macOS app bundle so microphone permissions are tied to the app:

```bash
./scripts/build_app_bundle.sh
open build/EventSubtitles.app
```

To prepare a WhisperKit model from Terminal before going offline:

```bash
swift run PrepareWhisperModel large-v3-v20240930_626MB
```

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
  -> glossary correction
  -> optional local EN/NL or NL/EN translation
  -> subtitle composer
  -> full-screen HDMI/chroma-key output
```

The app includes a `WhisperKit` engine option. Use the Model tab to prepare/download a Core ML model before the event, while online. Once cached locally, the live path can run offline.

For translation, the app has two local paths:

- `Glossary/rules`: deterministic fallback for demos and terminology protection.
- `Local command`: calls an offline translator executable with text on stdin and reads translated text from stdout. The argument template supports `{source}` and `{target}` tokens such as `--from {source} --to {target}`.

Parakeet v3 remains a benchmark candidate for ASR accuracy, but the runtime is currently optimized around Mac-native WhisperKit.
