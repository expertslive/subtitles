# Audio Input Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Audio workspace selector that defaults to the macOS system input but can persistently override capture to a specific connected audio interface.

**Architecture:** Put pure selection fallback behavior in `EventSubtitlesCore` so it can be tested without CoreAudio. Extend the app's existing CoreAudio inspector to list input devices and resolve the saved selection into an effective device. Wire that device into `AudioLevelMonitor.start` without changing the macOS global default.

**Tech Stack:** Swift 6, SwiftUI, CoreAudio, AVFoundation, XCTest, SwiftPM.

---

## File Structure

- `Sources/EventSubtitlesCore/AudioInputSelection.swift`: pure selection model and resolver.
- `Tests/EventSubtitlesCoreTests/AudioInputSelectionTests.swift`: red-green tests for default, override, and unavailable override behavior.
- `Package.swift`: add the `EventSubtitlesCoreTests` test target.
- `Sources/EventSubtitlesApp/AudioDeviceInspector.swift`: list CoreAudio input devices with stable identifiers, names, sample rates, and default device resolution.
- `Sources/EventSubtitlesApp/AudioLevelMonitor.swift`: accept an optional selected `AudioDeviceID` and apply it to the engine input before starting.
- `Sources/EventSubtitlesApp/AppSettingsStore.swift`: persist optional selected input device UID.
- `Sources/EventSubtitlesApp/AppState.swift`: publish device list, selected UID, effective status, and selection actions.
- `Sources/EventSubtitlesApp/AudioWorkspace.swift`: replace the passive input row with a picker, refresh button, status row, and default reset action.

### Task 1: Add Tested Selection Resolver

**Files:**
- Create: `Sources/EventSubtitlesCore/AudioInputSelection.swift`
- Create: `Tests/EventSubtitlesCoreTests/AudioInputSelectionTests.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import EventSubtitlesCore
import XCTest

final class AudioInputSelectionTests: XCTestCase {
    func testSystemDefaultModeUsesDefaultDevice() {
        let defaultDevice = AudioInputSelectionDevice(id: "built-in", name: "MacBook Pro Microphone")
        let result = AudioInputSelectionResolver.resolve(
            selectedDeviceID: nil,
            devices: [
                defaultDevice,
                AudioInputSelectionDevice(id: "scarlett", name: "Scarlett 2i2")
            ],
            defaultDeviceID: "built-in"
        )

        XCTAssertEqual(result.effectiveDeviceID, "built-in")
        XCTAssertEqual(result.status, .usingSystemDefault)
    }

    func testAvailableOverrideWinsOverDefaultDevice() {
        let result = AudioInputSelectionResolver.resolve(
            selectedDeviceID: "scarlett",
            devices: [
                AudioInputSelectionDevice(id: "built-in", name: "MacBook Pro Microphone"),
                AudioInputSelectionDevice(id: "scarlett", name: "Scarlett 2i2")
            ],
            defaultDeviceID: "built-in"
        )

        XCTAssertEqual(result.effectiveDeviceID, "scarlett")
        XCTAssertEqual(result.status, .usingOverride)
    }

    func testUnavailableOverrideFallsBackToDefaultDevice() {
        let result = AudioInputSelectionResolver.resolve(
            selectedDeviceID: "scarlett",
            devices: [
                AudioInputSelectionDevice(id: "built-in", name: "MacBook Pro Microphone")
            ],
            defaultDeviceID: "built-in"
        )

        XCTAssertEqual(result.effectiveDeviceID, "built-in")
        XCTAssertEqual(result.status, .overrideUnavailable)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AudioInputSelectionTests`

Expected: FAIL because `EventSubtitlesCoreTests` or `AudioInputSelectionResolver` does not exist yet.

- [ ] **Step 3: Add minimal resolver implementation**

```swift
public struct AudioInputSelectionDevice: Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum AudioInputSelectionStatus: Equatable, Sendable {
    case usingSystemDefault
    case usingOverride
    case overrideUnavailable
    case noInputAvailable
}

public struct AudioInputSelectionResult: Equatable, Sendable {
    public var effectiveDeviceID: String?
    public var status: AudioInputSelectionStatus
}

public enum AudioInputSelectionResolver {
    public static func resolve(
        selectedDeviceID: String?,
        devices: [AudioInputSelectionDevice],
        defaultDeviceID: String?
    ) -> AudioInputSelectionResult {
        guard let selectedDeviceID, !selectedDeviceID.isEmpty else {
            return AudioInputSelectionResult(
                effectiveDeviceID: defaultDeviceID,
                status: defaultDeviceID == nil ? .noInputAvailable : .usingSystemDefault
            )
        }

        if devices.contains(where: { $0.id == selectedDeviceID }) {
            return AudioInputSelectionResult(effectiveDeviceID: selectedDeviceID, status: .usingOverride)
        }

        return AudioInputSelectionResult(
            effectiveDeviceID: defaultDeviceID,
            status: defaultDeviceID == nil ? .noInputAvailable : .overrideUnavailable
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AudioInputSelectionTests`

Expected: PASS.

### Task 2: Discover and Apply Input Devices

**Files:**
- Modify: `Sources/EventSubtitlesApp/AudioDeviceInspector.swift`
- Modify: `Sources/EventSubtitlesApp/AudioLevelMonitor.swift`

- [ ] **Step 1: Extend device discovery**

Update `AudioInputDeviceInfo` to include `id: String`, `deviceID: AudioDeviceID`, `name: String`, and `sampleRate: Double`. Add `inputDevices()`, `defaultInputDeviceID()`, and `inputDevice(id:)`. The identifier must use CoreAudio `kAudioDevicePropertyDeviceUID` so it survives app restarts better than numeric `AudioDeviceID`.

- [ ] **Step 2: Apply selected input to the engine**

Add `inputDeviceID: AudioDeviceID? = nil` to `AudioLevelMonitor.start`. Before reading `engine.inputNode.outputFormat(forBus: 0)`, set the HAL input device on the input node audio unit with `kAudioOutputUnitProperty_CurrentDevice`. Throw `AudioLevelMonitorError.recordingUnavailable` with a readable message if CoreAudio rejects the selected device.

- [ ] **Step 3: Build**

Run: `swift build`

Expected: PASS.

### Task 3: Persist and Wire App State

**Files:**
- Modify: `Sources/EventSubtitlesApp/AppSettingsStore.swift`
- Modify: `Sources/EventSubtitlesApp/AppState.swift`

- [ ] **Step 1: Add saved selected input UID**

Add `selectedAudioInputDeviceID: String?` to `AppSettings`. Save and load it without breaking older settings files.

- [ ] **Step 2: Publish audio input state**

Add published `audioInputDevices: [AudioInputDeviceInfo]`, `selectedAudioInputDeviceID: String?`, `effectiveAudioInputDeviceID: String?`, and a selection status string. Update `refreshAudioInputDevice()` so it rescans devices and resolves the effective device through `AudioInputSelectionResolver`.

- [ ] **Step 3: Use effective device at session start**

In `AppState.start()`, pass `AudioDeviceInspector.inputDevice(id: effectiveAudioInputDeviceID)?.deviceID` into `audioMonitor.start`.

- [ ] **Step 4: Build**

Run: `swift build`

Expected: PASS.

### Task 4: Add Audio Workspace Picker

**Files:**
- Modify: `Sources/EventSubtitlesApp/AudioWorkspace.swift`

- [ ] **Step 1: Replace passive input row**

Add a SwiftUI `Picker("Audio interface", selection:)` with `System default` tagged as `nil` and each discovered device tagged by UID. Keep the refresh button. Add the selected-device status row and a `Use system default` button.

- [ ] **Step 2: Verify UI compiles**

Run: `swift build`

Expected: PASS.

### Task 5: Final Verification

**Files:**
- Verify all touched files.

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter AudioInputSelectionTests`

Expected: PASS.

- [ ] **Step 2: Run existing smoke test**

Run: `swift run EventSubtitlesSmokeTests`

Expected: PASS.

- [ ] **Step 3: Review diff**

Run: `git diff --stat` and `git diff --check`

Expected: no whitespace errors; diff limited to planned files.
