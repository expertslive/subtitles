# Event Runbook

## Before The Event

1. Connect the USB audio interface.
2. Launch `build/EventSubtitles.app`.
3. Open the Audio workspace and select the interface, or leave it on `System default` if macOS is already set correctly.
4. Confirm the Session panel shows the expected input device and sample rate.
5. Set `Capture` to `Live subtitles` for a real event, or `Demo captions` for screen checks.
6. Open the Models workspace, choose a WhisperKit model, and run `Prepare Offline Model` while online.
7. Switch Wi-Fi off and run a short WhisperKit test to confirm the model is cached.
8. Open the Glossary workspace and add, import, or bulk-paste the session glossary.
9. Open the Output workspace, show the output window, and move it to the HDMI display.
10. Use `Fill Display` and confirm the downstream video switcher keys the chroma green correctly.
11. Leave `Keep Mac awake` enabled unless another venue power plan is managing the machine.
12. Use the Settings window for deeper setup work if you need to adjust Style, Audio, Models, or Translation without changing the active workspace.

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
  - Display Flow: `Live Roll-up (TV-style)` for fast speakers or broadcast-style lower thirds
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
6. Use Panic blank if the public output must disappear immediately.
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
- Audio: select the input interface, check fallback/default status, audio level, clipping, power, and recording status.
- Output: show/fill/restore the output window and choose chroma or black background.
- Settings window: alternate setup surface for Style, Audio, Models, and Translation.

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

The current CAF records the 16 kHz mono Float32 ASR feed. Approximate size for 8 hours 45 minutes:

- 16 kHz mono, 32-bit float: about 2.0 GB.

Plan for 5 GB free per stage per full day for the current recorder, and keep more free space available if a future full-quality recording mode is added.
