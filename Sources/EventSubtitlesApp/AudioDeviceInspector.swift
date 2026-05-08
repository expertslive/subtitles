import CoreAudio
import Foundation

struct AudioInputDeviceInfo: Equatable {
    var id: String
    var deviceID: AudioDeviceID
    var name: String
    var sampleRate: Double

    var displayName: String {
        let rate = sampleRate > 0 ? " \(Int(sampleRate)) Hz" : ""
        return "\(name)\(rate)"
    }
}

enum AudioDeviceInspector {
    static func inputDevices() -> [AudioInputDeviceInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else {
            return []
        }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard hasInputChannels(deviceID),
                  let id = deviceUID(for: deviceID) ?? fallbackDeviceID(for: deviceID) else {
                return nil
            }

            return AudioInputDeviceInfo(
                id: id,
                deviceID: deviceID,
                name: deviceName(for: deviceID) ?? "Unknown input",
                sampleRate: sampleRate(for: deviceID) ?? 0
            )
        }
        .sorted { first, second in
            first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }

    static func defaultInputDevice() -> AudioInputDeviceInfo? {
        guard let deviceID = defaultInputAudioDeviceID(),
              let id = deviceUID(for: deviceID) ?? fallbackDeviceID(for: deviceID) else {
            return nil
        }

        return AudioInputDeviceInfo(
            id: id,
            deviceID: deviceID,
            name: deviceName(for: deviceID) ?? "Unknown input",
            sampleRate: sampleRate(for: deviceID) ?? 0
        )
    }

    static func defaultInputDeviceID() -> String? {
        defaultInputDevice()?.id
    }

    static func inputDevice(id: String?) -> AudioInputDeviceInfo? {
        guard let id else {
            return nil
        }

        return inputDevices().first { $0.id == id }
    }

    private static func defaultInputAudioDeviceID() -> AudioDeviceID? {
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

        return deviceID
    }

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)

        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else {
            return false
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            bufferListPointer.deallocate()
        }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer) == noErr else {
            return false
        }

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        return UnsafeMutableAudioBufferListPointer(audioBufferList)
            .contains { $0.mNumberChannels > 0 }
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedUID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedUID) == noErr,
              let unmanagedUID else {
            return nil
        }

        return unmanagedUID.takeRetainedValue() as String
    }

    private static func fallbackDeviceID(for deviceID: AudioDeviceID) -> String? {
        guard deviceID != 0 else {
            return nil
        }

        return "coreaudio:\(deviceID)"
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
