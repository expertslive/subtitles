# Audio Input Selector Design

## Goal

The app currently follows the macOS default input device. This is unreliable for event setups where the MacBook is closed and the internal microphone cannot be used, or where macOS reports the wrong default. Add an app-level audio interface selector in the existing Audio workspace so the operator can keep the default behavior or explicitly choose a connected input interface.

## User Experience

The Audio workspace keeps its current layout. In the `Input` section, replace the passive current-input row with:

- an `Audio interface` picker
- a refresh button to rescan connected input devices
- a short status row showing the effective device and sample rate
- a `Use system default` action

The picker includes `System default` as the first option. This is the default app setting. When the operator selects a concrete input device, that selection overrides the system default and is saved in app settings.

## Device Behavior

On launch, the app loads the saved input selection:

- If no override is saved, the effective input is the current macOS system default.
- If an override is saved and the device is connected, that device is effective.
- If an override is saved but unavailable, the UI shows that the saved device is unavailable and the app falls back to the system default until the operator chooses another input.

Refresh rescans the current CoreAudio input devices and updates the effective status. It does not change the macOS global default input.

## Runtime Capture

When a subtitle or audio-only session starts, the audio level monitor uses the selected effective input device. The app must not mutate system-wide audio settings. The selected device should affect app capture and session audio recording only.

The implementation should extend the existing `AudioDeviceInspector` into a small CoreAudio device discovery layer, persist the selected device identifier in `AppSettings`, and pass the effective device into `AudioLevelMonitor.start`.

## Error Handling

If no input device is available, keep the existing unavailable-audio error behavior.

If the selected override disappears before or during a session, the initial implementation only needs to handle this on refresh and session start. Mid-session hot-unplug handling can rely on the existing audio engine failure path and should surface an operator-facing error.

## Testing

Add focused tests around pure selection logic:

- default mode uses the system default device
- available saved override wins over the system default
- unavailable saved override falls back to the system default and reports unavailable status

Build or run the existing smoke test after implementation to verify the Swift package still compiles.
