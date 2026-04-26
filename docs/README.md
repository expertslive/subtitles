# Documentation

EventSubtitles is a native macOS app for offline live subtitles and Dutch/English translation at events.

## Guides

- [Architecture](architecture.md): runtime pipeline, model strategy, and event priorities.
- [Event runbook](event-runbook.md): pre-event checklist, recommended settings, live operation, and post-event files.
- [Original project prompt](../initial_prompt.txt): initial product goals and constraints.

## Build And Run

From the repository root:

```bash
swift build
swift run EventSubtitlesSmokeTests
./scripts/build_app_bundle.sh
open build/EventSubtitles.app
```

To prepare a WhisperKit model before going offline:

```bash
swift run PrepareWhisperModel large-v3-v20240930_626MB
```
