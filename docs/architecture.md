# Architecture

## Runtime Pipeline

1. Capture audio from the selected macOS input device.
2. Feed audio frames into a local speech recognizer.
3. Stabilize partial transcript chunks before showing them.
4. Apply glossary corrections for technical terms and names.
5. Optionally translate stable chunks between English and Dutch.
6. Compose readable two- or three-line captions.
7. Render the output window on the external HDMI display.

## Operator UI

The main window uses a persistent operator strip on the left and workspace buttons on the right.

The operator strip stays visible across all workspaces and contains session naming, capture mode, source language, Start/Stop, input level, session status, keep-awake control, manual captions, and quick output-window actions.

The right side is split into task-focused workspaces:

- Live: output preview, current caption, and a full-height history column for event operation.
- Style: visual tuning with live preview, smaller font sizes, line-width control, and fine X/Y position nudging.
- Glossary: full-width glossary editor, term table, search, test phrase, and JSON/CSV import/export.
- Logs: current session status, expected files, and captured caption history.
- Models: WhisperKit model selection, preparation, offline readiness status, prepare guidance, and resource checks.
- Translation: translation mode, engine settings, and test input/output.
- Audio: input status, level, clipping, and recording status.
- Output: output-window actions, background presets, signal status, and preview.

The workspace layout is responsive: setup-heavy views use columns when there is enough horizontal space and stack when the window is narrower. Workspace buttons have subtle surfaces and borders so operators can read them as clickable controls without turning the app into a heavy toolbar.

## First Engine Target

The first real ASR integration should use WhisperKit because it is already designed for Apple Silicon/Core ML. Translation should remain a separate module so subtitles-only mode is low latency and translation mode can buffer slightly more for readability.

The capture picker uses task-focused labels:

- Demo captions: generated sample captions for UI and output tests.
- Live subtitles: local WhisperKit/Core ML transcription for live captions.
- Record audio only: session audio capture without live caption generation.

WhisperKit can take a few seconds on the first start while the model loads and prewarms. After Stop, the app keeps the loaded model in memory so a later Start can resume faster.

The Models workspace explains what `Prepare Offline Model` does, shows current app memory usage, and provides a shortcut to Activity Monitor for CPU/GPU inspection. Direct GPU utilization is not read inside the app yet; Activity Monitor remains the trusted macOS source for that.

## Power Management

The app prevents idle sleep only while a session is running and `Keep Mac awake` is enabled. Start creates macOS IOKit assertions for user-idle system sleep and display sleep. Stop releases those assertions.

This is safer than holding the machine awake whenever the app is merely open: setup and glossary editing should not silently override normal power behavior, but active subtitling should keep both the Mac and HDMI output awake.

## App Bundle

The bundle display name is `Subtitles`; the executable and SwiftPM product remain `EventSubtitles`.

The app icon is generated during bundling from `Assets/AppIconSource.jpg`. The source image is a landscape JPEG, so the icon generator center-crops it to square and emits a valid `.icns` file with a 1024px representation.

The default About panel is replaced with a shorter app-specific About panel describing the local/offline subtitle workflow.

## Recording Storage

Session audio is recorded as `input-audio.caf` using the current input format from AVAudioEngine.

For an event day from 09:00 to 17:45, duration is 8 hours 45 minutes, or 31,500 seconds. Approximate CAF storage:

- 48 kHz mono, 16-bit: about 3.0 GB.
- 48 kHz stereo, 16-bit: about 6.0 GB.
- 48 kHz mono, 32-bit float: about 6.0 GB.
- 48 kHz stereo, 32-bit float: about 12.1 GB.

The realistic planning number is about 12 GB per stage per full day, with 20 GB per stage per day reserved for safety. Transcript, SRT, JSONL, and glossary files are tiny compared with the audio file.

## Event Priorities

- readable captions over minimum possible latency
- stable line wrapping with no sudden full-screen rewrites
- operator-controlled source/target language
- session glossary for IT terminology
- fully offline operation
- predictable sustained performance on a fanless MacBook Air
