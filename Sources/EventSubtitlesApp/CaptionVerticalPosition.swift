import Foundation

enum CaptionVerticalPosition: String, CaseIterable, Identifiable {
    case top
    case middle
    case bottom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top:
            "Top"
        case .middle:
            "Middle"
        case .bottom:
            "Bottom"
        }
    }
}
