import EventSubtitlesCore
import Foundation

final class SessionRecorder {
    private struct Metadata: Codable {
        var startedAt: Date
        var endedAt: Date?
        var mode: ProcessingMode
        var sourceLanguage: SourceLanguage
        var sessionName: String
        var engineName: String
        var whisperModelName: String
        var translationEngineName: String
        var captionStyle: CaptionStyleMetadata
        var segmentCount: Int
        var glossary: String
        var audioFileName: String
    }

    struct CaptionStyleMetadata: Codable {
        var fontName: String
        var fontSize: Double
        var maxLines: Int
        var targetCharactersPerLine: Int
        var safeMargin: Double
        var lineSpacing: Double
        var captionPosition: String
    }

    private let fileManager = FileManager.default
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private var directoryURL: URL?
    private var startedAt: Date?
    private var metadata: Metadata?
    private var segments: [CaptionSegmentRecord] = []
    private var lastEndSeconds: TimeInterval = 0

    var currentDirectoryURL: URL? {
        directoryURL
    }

    var segmentCount: Int {
        segments.count
    }

    var audioRecordingURL: URL? {
        directoryURL?.appendingPathComponent("input-audio.caf")
    }

    func start(
        sessionName: String,
        engineName: String,
        whisperModelName: String,
        translationEngineName: String,
        captionStyle: CaptionStyleMetadata,
        mode: ProcessingMode,
        sourceLanguage: SourceLanguage,
        glossary: String
    ) throws -> URL {
        let now = Date()
        let rootURL = try rootDirectoryURL()
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let nameSlug = slug(forFreeText: sessionName)
        let suffix = nameSlug.isEmpty ? slug(for: mode) : "\(nameSlug)_\(slug(for: mode))"
        let sessionDirectory = rootURL.appendingPathComponent(
            "\(directoryTimestamp(for: now))_\(suffix)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        directoryURL = sessionDirectory
        startedAt = now
        segments = []
        lastEndSeconds = 0
        metadata = Metadata(
            startedAt: now,
            endedAt: nil,
            mode: mode,
            sourceLanguage: sourceLanguage,
            sessionName: sessionName,
            engineName: engineName,
            whisperModelName: whisperModelName,
            translationEngineName: translationEngineName,
            captionStyle: captionStyle,
            segmentCount: 0,
            glossary: glossary,
            audioFileName: "input-audio.caf"
        )

        try writeMetadata()
        try glossary.write(
            to: sessionDirectory.appendingPathComponent("glossary.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "".write(to: sessionDirectory.appendingPathComponent("source-transcript.txt"), atomically: true, encoding: .utf8)
        try "".write(to: sessionDirectory.appendingPathComponent("display-transcript.txt"), atomically: true, encoding: .utf8)
        try "".write(to: sessionDirectory.appendingPathComponent("segments.jsonl"), atomically: true, encoding: .utf8)
        try "".write(to: sessionDirectory.appendingPathComponent("draft.srt"), atomically: true, encoding: .utf8)
        try "".write(to: sessionDirectory.appendingPathComponent("source.srt"), atomically: true, encoding: .utf8)
        try "".write(to: sessionDirectory.appendingPathComponent("display.srt"), atomically: true, encoding: .utf8)

        return sessionDirectory
    }

    func stop() throws {
        guard metadata != nil else {
            return
        }

        metadata?.endedAt = Date()
        metadata?.segmentCount = segments.count
        try writeMetadata()
    }

    func record(
        event: TranscriptEvent,
        mode: ProcessingMode,
        sourceLanguage: SourceLanguage
    ) throws {
        guard let directoryURL, let startedAt else {
            return
        }

        let segment = makeSegment(
            event: event,
            mode: mode,
            sourceLanguage: sourceLanguage,
            startedAt: startedAt
        )
        segments.append(segment)
        metadata?.segmentCount = segments.count
        try writeMetadata()

        try append(line(for: segment, text: segment.sourceText), to: directoryURL.appendingPathComponent("source-transcript.txt"))
        try append(line(for: segment, text: segment.displayText), to: directoryURL.appendingPathComponent("display-transcript.txt"))
        try appendJSONLine(segment, to: directoryURL.appendingPathComponent("segments.jsonl"))
        try SRTFormatter.formatDisplay(segments).write(
            to: directoryURL.appendingPathComponent("draft.srt"),
            atomically: true,
            encoding: .utf8
        )
        try SRTFormatter.formatSource(segments).write(
            to: directoryURL.appendingPathComponent("source.srt"),
            atomically: true,
            encoding: .utf8
        )
        try SRTFormatter.formatDisplay(segments).write(
            to: directoryURL.appendingPathComponent("display.srt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func makeSegment(
        event: TranscriptEvent,
        mode: ProcessingMode,
        sourceLanguage: SourceLanguage,
        startedAt: Date
    ) -> CaptionSegmentRecord {
        let startSeconds: TimeInterval
        let endSeconds: TimeInterval

        if let eventStartedAt = event.startedAt, let eventEndedAt = event.endedAt {
            startSeconds = max(lastEndSeconds, eventStartedAt.timeIntervalSince(startedAt))
            endSeconds = max(startSeconds + 0.4, eventEndedAt.timeIntervalSince(startedAt))
        } else {
            let elapsed = max(0.1, event.createdAt.timeIntervalSince(startedAt))
            let estimatedDuration = max(1.8, min(7.0, Double(event.displayText.count) / 18.0))
            let naturalStart = max(0, elapsed - estimatedDuration)
            startSeconds = max(lastEndSeconds, naturalStart)
            endSeconds = max(elapsed, startSeconds + 1.2)
        }
        lastEndSeconds = endSeconds

        return CaptionSegmentRecord(
            index: segments.count + 1,
            createdAt: event.createdAt,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            sourceText: event.sourceText,
            displayText: event.displayText,
            mode: mode,
            sourceLanguage: sourceLanguage
        )
    }

    private func writeMetadata() throws {
        guard let directoryURL, let metadata else {
            return
        }

        let data = try jsonEncoder.encode(metadata)
        try data.write(to: directoryURL.appendingPathComponent("metadata.json"), options: .atomic)
    }

    private func appendJSONLine(_ segment: CaptionSegmentRecord, to url: URL) throws {
        let data = try jsonEncoder.encode(segment)
        guard var line = String(data: data, encoding: .utf8) else {
            return
        }
        line.append("\n")
        try append(line, to: url)
    }

    private func append(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)

        if !fileManager.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
            return
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        handle.write(data)
    }

    private func line(for segment: CaptionSegmentRecord, text: String) -> String {
        "[\(SRTFormatter.timestamp(segment.startSeconds))] \(text)\n"
    }

    private func rootDirectoryURL() throws -> URL {
        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documents.appendingPathComponent("EventSubtitles", isDirectory: true)
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("EventSubtitles", isDirectory: true)
    }

    private func directoryTimestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    private func slug(for mode: ProcessingMode) -> String {
        switch mode {
        case .subtitlesOnly:
            "subtitles-only"
        case .englishToDutch:
            "english-to-dutch"
        case .dutchToEnglish:
            "dutch-to-english"
        }
    }

    private func slug(forFreeText text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
