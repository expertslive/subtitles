# Event Runbook

## Before The Event

1. Connect the USB audio interface and select it as the macOS default input.
2. Launch `build/EventSubtitles.app`.
3. Confirm the Session panel shows the expected input device and sample rate.
4. Set `Capture` to `Live subtitles` for a real event, or `Demo captions` for screen checks.
5. Open the Models workspace, choose a WhisperKit model, and run `Prepare Offline Model` while online.
6. Switch Wi-Fi off and run a short WhisperKit test to confirm the model is cached.
7. Open the Glossary workspace and add, import, or bulk-paste the session glossary.
8. Open the Output workspace, show the output window, and move it to the HDMI display.
9. Use `Fill Display` and confirm the downstream video switcher keys the chroma green correctly.
10. Leave `Keep Mac awake` enabled unless another venue power plan is managing the machine.

## Recommended Settings

- MacBook Air M5, 16 GB:
  - start with `large-v3-v20240930_626MB`
  - use `large-v3-v20240930_turbo_632MB` if latency is too high
  - use `small` for fast debugging
- Source language:
  - lock to English or Dutch for scheduled talks
  - use Automatic only when the speaker language is unknown
- Captions:
  - Display Flow: `Calm Blocks` for normal conference screens
  - Stability: `Calm` for public output, `Fast Draft` only for testing
  - 2 lines for lower-third broadcast use
  - 3 lines for accessibility screens
  - bottom position for general audience display
  - lower `Line width` to force more wrapping
  - use `Fine position` for final left/right/up/down placement

## During The Event

1. Set the session name before pressing Start.
2. Start with the audio engineer speaking into the stage mic.
3. Confirm the sleep status changes to `Awake on`.
4. Watch the input meter and transcript preview.
5. Use manual captions for emergency messages or sponsor/talk titles.
6. Press Clear if a bad partial needs to disappear immediately.
7. Keep Live visible while operating captions.
8. Use Logs only when validating that segments are being recorded.

## Workspace Guide

- Live: operate the event and watch the output preview.
- Style: tune typography, colors, line count, safe margins, display flow, and preview.
- Glossary: maintain terminology with row editing, alias groups, quality checks, suggestions, search, and test corrections.
- Glossary import/export:
  - Import supports JSON, CSV, and plain text glossary lines.
  - Export supports JSON and CSV.
  - JSON can be `{ "entries": [...] }`, an array of entries, or a string dictionary.
  - CSV uses `input,output` columns.
  - Advanced bulk edit still accepts plain `heard as => show as` lines.
- Logs: inspect session status, expected files, and captured captions.
- Models: prepare WhisperKit models, verify offline readiness, and check app memory/resource guidance.
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

## Storage Planning

For a full event day from 09:00 to 17:45, reserve storage mostly for `input-audio.caf`.

Approximate CAF sizes for 8 hours 45 minutes:

- 48 kHz mono, 16-bit: about 3.0 GB.
- 48 kHz stereo, 16-bit: about 6.0 GB.
- 48 kHz mono, 32-bit float: about 6.0 GB.
- 48 kHz stereo, 32-bit float: about 12.1 GB.

Plan for 20 GB free per stage per full day. This gives room for stereo 32-bit float input, logs, exported files, and operational margin.
