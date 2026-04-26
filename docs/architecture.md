# Architecture

## Runtime Pipeline

1. Capture audio from the selected macOS input device.
2. Feed audio frames into a local speech recognizer.
3. Stabilize partial transcript chunks before showing them.
4. Apply glossary corrections for technical terms and names.
5. Optionally translate stable chunks between English and Dutch.
6. Compose readable two- or three-line captions.
7. Render the output window on the external HDMI display.

## First Engine Target

The first real ASR integration should use WhisperKit because it is already designed for Apple Silicon/Core ML. Translation should remain a separate module so subtitles-only mode is low latency and translation mode can buffer slightly more for readability.

## Event Priorities

- readable captions over minimum possible latency
- stable line wrapping with no sudden full-screen rewrites
- operator-controlled source/target language
- session glossary for IT terminology
- fully offline operation
- predictable sustained performance on a fanless MacBook Air
