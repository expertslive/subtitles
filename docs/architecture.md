# Architecture

## Runtime Pipeline

1. Capture audio from the selected app audio interface, or from the current macOS system default input.
2. Convert the input once to 16 kHz mono Float32 and fan it out to the meter, CAF recorder, and speech recognizer.
3. Keep raw partial transcript chunks in an operator-only draft buffer.
4. Stabilize partial transcript chunks before public display.
5. Apply glossary corrections for technical terms and names.
6. Optionally translate stable chunks between English and Dutch.
7. Schedule readable two- or three-line caption cues.
8. Render stable scheduled cues on the external HDMI display.

## Operator UI

The main window uses a persistent operator strip on the left and workspace buttons on the right.

The operator strip stays visible across all workspaces and contains session naming, capture mode, source language, Start/Stop, input level, session status, keep-awake control, manual captions, and quick output-window actions.

The right side is split into task-focused workspaces:

- Live: output preview, current caption, and a full-height history column for event operation.
- Style: visual tuning with live preview, smaller font sizes, line-width control, and fine X/Y position nudging.
- Glossary: full-width term editor, search, inline add/edit/delete, alias groups, quality checks, test phrase, session suggestions, advanced bulk edit, and JSON/CSV import/export.
- Logs: current session status, expected files, and captured caption history.
- Models: WhisperKit model selection, preparation, offline readiness status, prepare guidance, and resource checks.
- Translation: translation mode, engine settings, and test input/output.
- Audio: audio interface selection, input status, level, clipping, power, and recording status.
- Output: output-window actions, background presets, signal status, and preview.

The workspace layout is responsive: setup-heavy views use columns when there is enough horizontal space and stack when the window is narrower. Workspace buttons have subtle surfaces and borders so operators can read them as clickable controls without turning the app into a heavy toolbar.

Global live controls live in the macOS toolbar: session name, capture mode, source language, processing mode, audio meter, Start/Stop, panic blank, and output-window actions. This keeps the event-critical controls reachable without duplicating them in every workspace.

## First Engine Target

The first real ASR integration should use WhisperKit because it is already designed for Apple Silicon/Core ML. Translation should remain a separate module so subtitles-only mode is low latency and translation mode can buffer slightly more for readability.

The capture picker uses task-focused labels:

- Demo captions: generated sample captions for UI and output tests.
- Live subtitles: local WhisperKit/Core ML transcription for live captions.
- Record audio only: session audio capture without live caption generation.

WhisperKit can take a few seconds on the first start while the model loads and prewarms. After Stop, the app keeps the loaded model in memory so a later Start can resume faster.

The Models workspace explains what `Prepare Offline Model` does, shows current app memory usage, and provides a shortcut to Activity Monitor for CPU/GPU inspection. Direct GPU utilization is not read inside the app yet; Activity Monitor remains the trusted macOS source for that.

## Audio Input Selection

The Audio workspace owns the app-level input selector. Operators can leave it on `System default` or choose a specific USB interface. `System default` is passed through to Core Audio as no explicit override, so changing the macOS default input still works as expected.

When a previously selected interface is missing, the app reports that status and falls back to the system default instead of failing the session start. The selected input is shared by one capture pipeline that feeds the audio meter, CAF recording, and WhisperKit path.

The capture pipeline owns the only live `AVAudioEngine` in the app. It restarts on Core Audio configuration changes and preserves the open CAF writer during the restart so short device changes do not silently discard the rest of the session recording.

## Power Management

The app prevents idle sleep only while a session is running and `Keep Mac awake` is enabled. Start creates macOS IOKit assertions for user-idle system sleep and display sleep. Stop releases those assertions.

This is safer than holding the machine awake whenever the app is merely open: setup and glossary editing should not silently override normal power behavior, but active subtitling should keep both the Mac and HDMI output awake.

## App Bundle

The bundle display name is `Subtitles`; the executable and SwiftPM product remain `EventSubtitles`.

The app icon is generated during bundling from `Assets/AppIconSource.jpg`. The source image is a landscape JPEG, so the icon generator center-crops it to square and emits a valid `.icns` file with a 1024px representation.

The default About panel is replaced with a shorter app-specific About panel describing the local/offline subtitle workflow.

The app also exposes a Settings scene for setup-oriented Style, Audio, Models, and Translation controls. That keeps longer preparation tasks available without crowding the live operator workspace.

## Recording Storage

Session audio is recorded as `input-audio.caf` after conversion to 16 kHz mono Float32, the same stream that feeds WhisperKit. This keeps the recording aligned with the ASR path and makes storage predictable.

For an event day from 09:00 to 17:45, duration is 8 hours 45 minutes, or 31,500 seconds. Approximate CAF storage:

- 16 kHz mono, 32-bit float: about 2.0 GB.

The practical planning number is 5 GB per stage per full day, with extra free disk space reserved for safety and future higher-quality recording modes. Transcript, SRT, JSONL, and glossary files are tiny compared with the audio file.

## Event Priorities

- readable captions over minimum possible latency
- stable line wrapping with no sudden full-screen rewrites
- operator-controlled source/target language
- session glossary for IT terminology
- fully offline operation
- predictable sustained performance on a fanless MacBook Air

## Calm Public Captions

Raw ASR partials are useful for the operator but should not drive the public output directly. Streaming ASR can revise words as more context arrives, which makes the audience output feel restless if every partial update redraws the sentence.

The display architecture now includes a draft buffer, stability gate, and caption scheduler. The public HDMI output consumes scheduled stable caption cues, while the operator Live workspace still shows raw draft text for troubleshooting. Caption display refreshes are demand-driven: new speech, scheduler deadlines, idle-tail flushes, and auto-clear timers request the next tick instead of relying on a constant fixed-rate UI loop.

Calm Blocks also has an idle-tail flush. If WhisperKit keeps the last words as an unstable partial and does not emit a final segment quickly, the app publishes the remaining tail after the configured maximum latency. This prevents the last spoken sentence from waiting until the speaker starts a new sentence.

Implemented display modes:

- Calm Blocks: default conference mode, showing stable blocks after a short delay.
- Live Roll-up (TV-style): line-paced rolling captions where each logical line holds long enough to read before scrolling.
- Fast Draft: immediate raw draft output for testing, not recommended for public screens.

The output menu and toolbar include a panic blank for live recovery. Panic blank clears the public caption state and blanks the HDMI output; unblanking does not restore stale text.

Implementation details for future refinements are kept in the local untracked calm-caption display spec.

## Glossary Management

The glossary remains stored as simple `input => output` text so session logs, import/export, and deterministic post-correction stay transparent. The operator UI now treats that text as structured rows:

- Heard as: what WhisperKit or the operator expects to hear.
- Show as: the spelling that should appear publicly.
- Alias groups: multiple heard forms mapped to one preferred output.
- Quality checks: duplicate pairs, empty sides, and conflicting mappings.
- Session suggestions: frequent recent transcript terms that are not already in the glossary.

Advanced bulk edit is still available for pasting prepared terminology before an event.
