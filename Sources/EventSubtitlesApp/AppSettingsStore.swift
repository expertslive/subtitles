import AppKit
import EventSubtitlesCore
import SwiftUI

struct AppSettings: Codable {
    var mode: ProcessingMode
    var sourceLanguage: SourceLanguage
    var transcriptionEngine: String
    var translationEngine: String
    var sessionName: String
    var whisperModelName: String
    var translationCommandPath: String
    var translationCommandArguments: String
    var glossaryText: String
    var fontName: String
    var fontSize: Double
    var maxLines: Int
    var targetCharactersPerLine: Int
    var safeMargin: Double
    var lineSpacing: Double
    var foregroundColor: CodableColor
    var backgroundColor: CodableColor
    var shadowEnabled: Bool
    var shadowRadius: Double
    var captionPosition: String
    var captionOffsetX: Double?
    var captionOffsetY: Double?
    var keepMacAwakeDuringSession: Bool?
    var captionDisplayMode: CaptionDisplayMode?
    var captionStabilityLevel: CaptionStabilityLevel?
    var captionCommitDelay: Double?
    var captionUnstableWordCount: Int?
    var captionMinimumHold: Double?
    var captionMaximumLatency: Double?
}

struct CodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Double(nsColor.redComponent)
        green = Double(nsColor.greenComponent)
        blue = Double(nsColor.blueComponent)
        alpha = Double(nsColor.alphaComponent)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

final class AppSettingsStore {
    private let key = "eventSubtitles.settings.v1"
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> AppSettings? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? decoder.decode(AppSettings.self, from: data)
    }

    func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
