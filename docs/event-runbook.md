# Event Runbook

## Before The Event

1. Connect the USB audio interface and select it as the macOS default input.
2. Launch `build/EventSubtitles.app`.
3. Confirm the Session panel shows the expected input device and sample rate.
4. Set `Capture` to `Live subtitles (WhisperKit)` for a real event, or `Demo captions` for screen checks.
5. Open the Models workspace, choose a WhisperKit model, and run `Prepare Offline Model` while online.
6. Switch Wi-Fi off and run a short WhisperKit test to confirm the model is cached.
7. Open the Glossary workspace and create or paste the session glossary.
8. Open the Output workspace, show the output window, and move it to the HDMI display.
9. Use `Fill Display` and confirm the downstream video switcher keys the chroma green correctly.

## Recommended Settings

- MacBook Air M5, 16 GB:
  - start with `large-v3-v20240930_626MB`
  - use `large-v3-v20240930_turbo_632MB` if latency is too high
  - use `small` for fast debugging
- Source language:
  - lock to English or Dutch for scheduled talks
  - use Automatic only when the speaker language is unknown
- Captions:
  - 2 lines for lower-third broadcast use
  - 3 lines for accessibility screens
  - bottom position for general audience display

## During The Event

1. Set the session name before pressing Start.
2. Start with the audio engineer speaking into the stage mic.
3. Watch the input meter and transcript preview.
4. Use manual captions for emergency messages or sponsor/talk titles.
5. Press Clear if a bad partial needs to disappear immediately.
6. Keep Live visible while operating captions.
7. Use Logs only when validating that segments are being recorded.

## Workspace Guide

- Live: operate the event and watch the output preview.
- Style: tune typography, colors, line count, safe margins, and preview.
- Glossary: maintain terminology, search terms, and test corrections.
- Logs: inspect session status, expected files, and captured captions.
- Models: prepare WhisperKit models and verify offline readiness.
- Translation: configure translation mode and local translation commands.
- Audio: check input status, audio level, clipping, and recording status.
- Output: show/fill/restore the output window and choose chroma or black background.

## After The Event

Each session is saved under:

```text
~/Documents/EventSubtitles/
```

Important files:

- `input-audio.caf`: raw recorded input
- `source-transcript.txt`: spoken text
- `display-transcript.txt`: displayed text
- `segments.jsonl`: structured segment log
- `source.srt`: spoken-language subtitle export
- `display.srt`: output-language subtitle export

Use `segments.jsonl` for any future cleanup/export tooling because it keeps source text, display text, timing, language, mode, and session metadata together.
