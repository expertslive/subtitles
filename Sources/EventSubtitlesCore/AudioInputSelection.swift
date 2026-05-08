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

    public init(effectiveDeviceID: String?, status: AudioInputSelectionStatus) {
        self.effectiveDeviceID = effectiveDeviceID
        self.status = status
    }
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
            return AudioInputSelectionResult(
                effectiveDeviceID: selectedDeviceID,
                status: .usingOverride
            )
        }

        return AudioInputSelectionResult(
            effectiveDeviceID: defaultDeviceID,
            status: defaultDeviceID == nil ? .noInputAvailable : .overrideUnavailable
        )
    }
}
