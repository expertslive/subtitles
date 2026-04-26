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

The main window uses a persistent operator strip on the left and workspace tabs on the right.

The operator strip stays visible across all workspaces and contains session naming, capture mode, source language, Start/Stop, input level, session status, manual captions, and quick output-window actions.

The right side is split into task-focused workspaces:

- Live: output preview, current caption, and history for event operation.
- Style: visual tuning with live preview.
- Glossary: full-width glossary editor, term table, search, and test phrase.
- Logs: current session status, expected files, and captured caption history.
- Models: WhisperKit model selection, preparation, and offline readiness status.
- Translation: translation mode, engine settings, and test input/output.
- Audio: input status, level, clipping, and recording status.
- Output: output-window actions, background presets, signal status, and preview.

The workspace layout is responsive: setup-heavy views use columns when there is enough horizontal space and stack when the window is narrower.

## First Engine Target

The first real ASR integration should use WhisperKit because it is already designed for Apple Silicon/Core ML. Translation should remain a separate module so subtitles-only mode is low latency and translation mode can buffer slightly more for readability.

The capture picker uses task-focused labels:

- Demo captions: generated sample captions for UI and output tests.
- Live subtitles (WhisperKit): local Core ML transcription for live captions.
- Record audio only: session audio capture without live caption generation.

## Event Priorities

- readable captions over minimum possible latency
- stable line wrapping with no sudden full-screen rewrites
- operator-controlled source/target language
- session glossary for IT terminology
- fully offline operation
- predictable sustained performance on a fanless MacBook Air
