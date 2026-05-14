import Foundation
import SwiftUI

enum OperationalStatus: String, Comparable {
    case pass
    case warning
    case fail

    static func < (lhs: OperationalStatus, rhs: OperationalStatus) -> Bool {
        lhs.rank < rhs.rank
    }

    var rank: Int {
        switch self {
        case .pass: 0
        case .warning: 1
        case .fail: 2
        }
    }

    var label: String {
        switch self {
        case .pass: "Ready"
        case .warning: "Check"
        case .fail: "Blocked"
        }
    }

    var systemImage: String {
        switch self {
        case .pass: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pass: .green
        case .warning: .orange
        case .fail: .red
        }
    }
}

struct PreflightCheck: Identifiable {
    let id: String
    let title: String
    let detail: String
    let status: OperationalStatus
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        id: String,
        title: String,
        detail: String,
        status: OperationalStatus,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.actionTitle = actionTitle
        self.action = action
    }
}

struct OutputDisplayInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let frameDescription: String
    let isMain: Bool

    var displayLabel: String {
        isMain ? "\(name) (main)" : name
    }
}

struct AudioTestRecordingResult {
    let url: URL
    let duration: TimeInterval
    let peakLevel: Double
    let clipped: Bool
    let silent: Bool

    var durationText: String {
        duration.formatted(.number.precision(.fractionLength(1))) + "s"
    }

    var peakText: String {
        "\(Int(peakLevel * 100))%"
    }

    var summary: String {
        if clipped {
            return "Recorded, but clipping was detected."
        }
        if silent {
            return "Recorded, but the input looks silent."
        }
        return "Recorded clean test audio."
    }
}
