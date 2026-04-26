# Workspace Tabs

This note captures the implemented workspace direction for the operator app tabs, plus follow-up ideas for richer glossary, log, model, translation, audio, and output tooling.

## Core Direction

Treat tabs as workspace contexts, not as small option panels.

The app has two main mental modes:

- Run the event.
- Prepare, maintain, and review the event.

The left side should remain a compact operator strip that is always visible. The right side should change based on the active workspace tab.

## Implementation Status

The first layout pass is implemented in `OperatorView`.

Implemented:

- Persistent left operator strip.
- Right-side workspace selector.
- Live workspace with output preview, current caption, and history.
- Style workspace with grouped typography, layout, color, shadow, presets, and preview.
- Glossary workspace with editor, search, term table, and test phrase.
- Logs workspace with current session status, expected files, and captured captions.
- Models workspace with model preparation and offline readiness.
- Translation workspace with translation settings and test source/display preview.
- Audio workspace with input, level, clipping, and recording status.
- Output workspace with output-window actions, background presets, signal status, and preview.
- Responsive workspace layout for narrower windows.

Still future work:

- Structured glossary storage.
- Import/export for glossary data.
- Browsing previous session folders.
- Regenerating SRT files from the Logs workspace.
- Audio input selection from inside the app.
- Display selection and output test cards.

## Always-Visible Operator Strip

The left strip should stay available across tabs and contain only the controls the operator may need at any time:

- Session name.
- Start and Stop.
- Audio input status.
- Compact audio level meter.
- Engine status.
- Recording/logging status.
- Manual caption input.
- Critical output window controls.

This strip must remain visible and usable even when the main workspace is focused on setup or review.

## Proposed Workspace Tabs

- Live.
- Style.
- Glossary.
- Logs.
- Models.
- Translation.
- Audio.
- Output.

Only Live and Style should show the output preview by default. Other workspaces should use the available space for tables, editors, search, tests, and maintenance tools.

## Live

Purpose: operate during the actual event.

This workspace should keep the output preview prominent and reduce distractions.

Useful areas:

- Large output preview.
- Current caption.
- Caption history.
- Confidence, latency, and engine status.
- Quick correction of the last caption.
- Manual caption input.
- Event-safe controls only.

The preview belongs here as the main visual reference for the operator.

## Style

Purpose: tune the visual output before or during an event.

This workspace should also keep the preview visible, because styling changes need immediate visual feedback.

Useful areas:

- Large preview.
- Typography controls.
- Layout controls.
- Color controls.
- Shadow controls.
- Chroma/background controls.
- Style presets.
- Test phrases for short, long, and technical captions.

Possible presets:

- Chroma lower third.
- Full black subtitles.
- High contrast.
- Large venue.

Style should be a full setup workspace, not just a vertical stack of sliders.

## Glossary

Purpose: build and maintain a technical vocabulary for the event.

The output preview should not be shown by default here. This workspace needs room for glossary tooling.

Useful areas:

- Glossary table.
- Search and filtering.
- Add/edit/delete terms.
- Import and export CSV or JSON.
- Test phrase input.
- Correction preview showing before/after text.
- Term enable/disable.
- Session or event-specific glossary presets.
- Suggestions mined from previous logs.

Possible glossary fields:

- Term.
- Aliases.
- Language.
- Preferred spelling.
- Replacement.
- Type.
- Notes.
- Enabled.

Useful term types:

- Product.
- Acronym.
- Person.
- Company.
- Technical term.

Examples:

- Kubernetes.
- kubectl.
- Azure OpenAI.
- CI/CD.
- PostgreSQL.
- GitHub.

Important behavior:

- Case locking, such as always using `GitHub`.
- Alias matching, such as correcting likely ASR mistakes to `kubectl`.
- Technical terms may need to remain untranslated.

## Logs

Purpose: browse sessions and produce useful post-event files.

The output preview should not be shown by default here.

Useful areas:

- Session list grouped by date and time.
- Current session status.
- Search within transcripts.
- Open session folder.
- Segment viewer with timestamps.
- Source transcript viewer.
- Display transcript viewer.
- Audio file status.
- Export and regenerate actions.

Expected session files:

- `metadata.json`.
- `source-transcript.txt`.
- `display-transcript.txt`.
- `segments.jsonl`.
- `draft.srt`.
- `source.srt`.
- `display.srt`.
- `input-audio.caf`.

Logs should be more than a folder pointer. They should help create deliverables after the event, especially SRT and transcript files.

## Models

Purpose: prepare and validate offline speech recognition models.

The output preview should not be shown by default here.

Useful areas:

- Locally available models.
- Selected model.
- Prepare/download status.
- Disk usage.
- Offline readiness check.
- Model health check.
- Test transcription with sample audio.
- Benchmark results.
- Recommended model for the current Mac.

Useful readiness states:

- Ready offline.
- Needs download.
- Preparing.
- Failed.
- Unknown.

This workspace should answer: "Can we safely run the event offline with this machine?"

## Translation

Purpose: configure and test translation behavior.

The output preview should not be shown by default here.

Useful areas:

- Translation mode.
- Translation engine selection.
- Direction rules.
- Local command configuration.
- Test input and output panes.
- Latency test.
- Glossary/rules integration.
- Failure behavior.

Modes:

- Subtitles only.
- English to Dutch.
- Dutch to English.
- Bidirectional.

Important behavior:

- Use source captions if translation fails.
- Keep latency visible.
- Let technical terminology be preserved where needed.
- Support fixed source language and automatic detection.

## Audio

Purpose: setup and validate the stage audio feed.

This should probably become its own workspace because audio quality is critical for live transcription.

Useful areas:

- Input device selection.
- Sample rate and channel status.
- Large level meter.
- Clipping indicator.
- Noise floor indicator.
- Permission status.
- Record test.
- Playback last test recording.
- Stage feed health check.

During live operation, only a compact meter stays in the operator strip. Deeper diagnostics belong here.

## Output

Purpose: setup the external display and key/fill output.

Useful areas:

- Display selection.
- Output window controls.
- Fullscreen/fill display.
- Restore window.
- Chroma green and black presets.
- Safe area and overscan test grid.
- Lower-third positioning.
- Test card.

This workspace should make it easy to verify the HDMI/projector/capture setup before the event starts.

## Layout Recommendation

Use a persistent left operator strip and a right workspace area.

The workspace selector can be:

- A top toolbar with tabs.
- A compact left navigation inside the workspace area.
- A segmented control if the tab count stays small.

Because the number of workspaces is likely to grow, a sidebar-style navigation may scale better than a native tab bar.

## Running State

While the app is running:

- Live must always be one click away.
- Risky setup controls should be disabled or clearly marked.
- Logs and Glossary should remain viewable.
- Style may remain editable if changes are applied live and safely.
- Model switching should be disabled.
- Audio device switching should require an explicit stop or confirmation.

The operator should never lose access to Start/Stop, audio status, or output status while working in another tab.

## Implementation Notes

Possible SwiftUI direction:

- Replace the small `TabView` in the lower-left inspector with a workspace selection state.
- Keep `sessionControls` compact and always visible.
- Move `outputControls` into a dedicated Output workspace, keeping only essential output actions in the operator strip.
- Build separate workspace views:
  - `LiveWorkspaceView`.
  - `StyleWorkspaceView`.
  - `GlossaryWorkspaceView`.
  - `LogsWorkspaceView`.
  - `ModelsWorkspaceView`.
  - `TranslationWorkspaceView`.
  - `AudioWorkspaceView`.
  - `OutputWorkspaceView`.

The first implementation can be layout-only, moving the existing controls into the new workspaces before adding richer functionality.
