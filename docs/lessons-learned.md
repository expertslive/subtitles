# Lessons Learned

## Product And Operator UX

- The app should present itself as `Subtitles` to operators. `EventSubtitles` can remain the repo/product name.
- Capture options should be task-oriented, not implementation-oriented:
  - Demo captions.
  - Live subtitles.
  - Record audio only.
- The operator needs persistent controls while moving between workspaces. Start/Stop, audio status, recording status, manual captions, and output-window controls must stay visible.
- Workspace tabs should look subtly clickable. A small surface and border is enough.
- Live operation benefits from a full-height history column next to the output preview. Operators need to scan recent captions continuously.
- Style controls need fine positioning, not only top/middle/bottom presets. Venue screens, key/fill systems, and projectors often need manual X/Y nudging.
- Line count is not the same as forced wrapping. The composer only uses two lines if the text needs two lines. To force earlier wrapping, lower the line width.
- Font size needs to go below 34 for some output setups. The current range starts at 18.
- About text should be short. Long About panels are not useful for operators.
- Active subtitling should prevent idle sleep, but the app should not keep the Mac awake just because it is open.

## WhisperKit

- WhisperKit works well as the primary ASR path on Apple Silicon.
- First Start can take a few seconds because the model needs loading and prewarming.
- Keeping the loaded model in memory after Stop makes subsequent Starts faster.
- The Models workspace remains the right place for prepare/download, offline readiness checks, first-start expectations, and resource guidance.
- Direct GPU load is not exposed in-app yet. Activity Monitor is the honest fallback for CPU/GPU pressure.

## Audio And Recording

- The app records `input-audio.caf` using the current AVAudioEngine input format.
- CAF storage dominates session size. Transcript, SRT, JSONL, and glossary files are tiny.
- For 09:00 to 17:45, reserve about 20 GB per stage per day.
- A realistic full-day stereo 48 kHz 32-bit float recording is about 12.1 GB.
- Future Audio/Logs UI should show sample rate, channel count, recording format, MB/hour, and remaining recording time.

## SwiftUI And macOS Implementation

- Do not run AVAudioEngine tap callbacks from `@MainActor` isolated types. Swift actor isolation checks can crash on the realtime audio queue.
- Keep audio tap work minimal. UI updates should hop back to the main actor.
- The app bundle should be used for event testing because microphone permission attaches to the bundle identity.
- `CFBundleName` and `CFBundleDisplayName` control the visible app/window/menu identity; the executable can remain `EventSubtitles`.
- macOS icon generation is most reliable when the build script emits `.icns` directly. `iconutil` was unreliable in this environment.
- The supplied icon source is a 1360x752 JPEG. It must be center-cropped to square and scaled into ICNS representations.
- Use IOKit power assertions while a session is running to prevent idle display/system sleep, then release them on Stop.

## Glossary

- A raw text glossary is fast to edit, but import/export is needed for real event prep.
- Import supports JSON, CSV, and plain text.
- Export supports JSON and CSV.
- JSON should support multiple shapes because different users/tools will produce different formats:
  - `{ "entries": [...] }`
  - `[ { "input": "...", "output": "..." } ]`
  - `{ "wrong": "Correct" }`
- Future work should move from text-only storage to structured glossary entries with aliases, type, language, notes, and enabled state.

## Release And Distribution

- GitHub releases are the easiest download path for non-developers.
- The app is currently ad-hoc signed for local testing, so first launch may require Control-click > Open.
- Release assets should include a zipped `.app` bundle and SHA-256.
- Keep release notes short and practical: download, highlights, validation commands, first-launch note.

## Current Follow-Ups

- Add Audio/Logs storage estimator.
- Add previous-session browser in Logs.
- Add SRT regeneration and cleanup tooling in Logs.
- Add in-app audio input selection instead of relying only on macOS default input.
- Add display selection and test cards in Output.
- Add structured glossary storage and richer glossary editing.
