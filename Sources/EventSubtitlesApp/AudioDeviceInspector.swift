import CoreAudio
import Foundation

struct AudioInputDeviceInfo: Equatable {
    var name: String
    var sampleRate: Double
}

enum AudioDeviceInspector {
    static func defaultInputDevice() -> AudioInputDeviceInfo? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != 0 else {
            return nil
        }

        return AudioInputDeviceInfo(
            name: deviceName(for: deviceID) ?? "Unknown input",
            sampleRate: sampleRate(for: deviceID) ?? 0
        )
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName) == noErr,
              let unmanagedName else {
            return nil
        }

        return unmanagedName.takeRetainedValue() as String
    }

    private static func sampleRate(for deviceID: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate) == noErr else {
            return nil
        }

        return sampleRate
    }
}
