import AppKit
import Darwin
import EventSubtitlesCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var mode: ProcessingMode = .subtitlesOnly {
        didSet {
            if mode != .subtitlesOnly {
                sourceLanguage = mode.sourceLanguage
            }
        }
    }
    @Published var sourceLanguage: SourceLanguage = .automatic

    @Published var isRunning = false
    @Published var audioLevel = 0.0
    @Published var audioInputDescription = "Input unknown"
    @Published var engineStatus = "Simulator idle"
    @Published var errorMessage: String?
    @Published var sessionName = "Main stage"
    @Published var transcriptionEngine: TranscriptionEngineChoice = .simulator
    @Published var whisperModelName = "large-v3-v20240930_626MB"
    @Published var modelStatus = "Not prepared"
    @Published var isPreparingModel = false
    @Published var translationEngine: TranslationEngineChoice = .ruleBased
    @Published var translationCommandPath = ""
    @Published var translationCommandArguments = "--from {source} --to {target}"

    @Published var currentEvent: TranscriptEvent?
    @Published var captionLayout = CaptionLayout(lines: ["Ready"])
    @Published var history: [TranscriptEvent] = []

    @Published var fontName = "Helvetica Neue"
    @Published var fontSize = 68.0 {
        didSet { recomputeCaption() }
    }
    @Published var maxLines = 2 {
        didSet { recomputeCaption() }
    }
    @Published var targetCharactersPerLine = 42 {
        didSet { recomputeCaption() }
    }
    @Published var safeMargin = 78.0
    @Published var lineSpacing = 8.0
    @Published var foregroundColor = Color.white
    @Published var backgroundColor = Color(red: 0.0, green: 0.82, blue: 0.0)
    @Published var shadowEnabled = true
    @Published var shadowRadius = 7.0
    @Published var captionPosition: CaptionVerticalPosition = .bottom
    @Published var captionOffsetX = 0.0
    @Published var captionOffsetY = 0.0

    @Published var glossaryText = """
    kubernetes => Kubernetes
    postgres => PostgreSQL
    postgresql => PostgreSQL
    oauth => OAuth
    openai => OpenAI
    apple silicon => Apple Silicon
    macbook air => MacBook Air
    """

    @Published var manualCaption = ""
    @Published var sessionLogStatus = "No active session"
    @Published var sessionDirectoryPath: String?
    @Published var sessionSegmentCount = 0
    @Published var sessionElapsedText = "00:00:00"
    @Published var keepMacAwakeDuringSession = true
    @Published var sleepPreventionStatus = "Awake ready"
    @Published var appMemoryUsageText = "Unknown"

    private let simulatorTranscriber = MockLocalTranscriber()
    private let whisperKitTranscriber = WhisperKitTranscriber()
    private let audioMonitor = AudioLevelMonitor()
    private let translator = RuleBasedTranslator()
    private let commandLineTranslator = CommandLineTranslator()
    private let sessionRecorder = SessionRecorder()
    private let settingsStore = AppSettingsStore()
    private let sleepPreventer = SleepPreventer()
    private var outputController: OutputWindowController?
    private var sessionStartedAt: Date?
    private var sessionTimer: Timer?

    init() {
        loadSettings()
        refreshAudioInputDevice()
        refreshResourceUsage()
        updateSleepPreventionStatusForIdle()
    }

    func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        errorMessage = nil
        saveSettings()
        engineStatus = transcriptionEngine.statusLabel
        startSleepPreventionIfNeeded()
        startSessionLog()
        startSessionTimer()
        refreshResourceUsage()

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await self.audioMonitor.start(recordingURL: self.sessionRecorder.audioRecordingURL) { [weak self] level in
                    Task { @MainActor [weak self] in
                        self?.audioLevel = Double(level)
                    }
                }
            } catch {
                self.errorMessage = "Audio level unavailable: \(error.localizedDescription)"
            }
        }

        startTranscriptionEngine()
    }

    func stop() {
        guard isRunning else {
            return
        }

        simulatorTranscriber.stopNow()
        Task {
            await whisperKitTranscriber.stop()
        }
        audioMonitor.stop()
        audioLevel = 0
        isRunning = false
        engineStatus = transcriptionEngine.idleStatusLabel
        stopSleepPrevention()
        stopSessionTimer()
        stopSessionLog()
        refreshResourceUsage()
    }

    func pushManualCaption() {
        let trimmed = manualCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        submitTranscript(trimmed, isFinal: true)
        manualCaption = ""
    }

    func clearCaptions() {
        currentEvent = nil
        captionLayout = CaptionLayout(lines: [])
    }

    func showOutputWindow() {
        if outputController == nil {
            outputController = OutputWindowController(state: self)
        }
        outputController?.show()
    }

    func fillExternalDisplay() {
        if outputController == nil {
            outputController = OutputWindowController(state: self)
        }
        outputController?.fillExternalDisplay()
    }

    func restoreOutputWindow() {
        outputController?.restoreWindow()
    }

    func useChromaGreen() {
        backgroundColor = Color(red: 0.0, green: 0.82, blue: 0.0)
    }

    func useBlackBackground() {
        backgroundColor = .black
    }

    func openSessionFolder() {
        guard let url = sessionRecorder.currentDirectoryURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func refreshAudioInputDevice() {
        if let input = AudioDeviceInspector.defaultInputDevice() {
            let rate = input.sampleRate > 0 ? " \(Int(input.sampleRate)) Hz" : ""
            audioInputDescription = "\(input.name)\(rate)"
        } else {
            audioInputDescription = "Input unknown"
        }
    }

    var systemMemoryText: String {
        byteCountString(ProcessInfo.processInfo.physicalMemory)
    }

    func refreshResourceUsage() {
        appMemoryUsageText = currentResidentMemoryText()
    }

    func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }

    func setKeepMacAwakeDuringSession(_ enabled: Bool) {
        keepMacAwakeDuringSession = enabled
        saveSettings()

        if isRunning {
            if enabled {
                startSleepPreventionIfNeeded()
            } else {
                stopSleepPrevention()
            }
        } else {
            updateSleepPreventionStatusForIdle()
        }
    }

    func saveSettings() {
        settingsStore.save(
            AppSettings(
                mode: mode,
                sourceLanguage: sourceLanguage,
                transcriptionEngine: transcriptionEngine.rawValue,
                translationEngine: translationEngine.rawValue,
                sessionName: sessionName,
                whisperModelName: whisperModelName,
                translationCommandPath: translationCommandPath,
                translationCommandArguments: translationCommandArguments,
                glossaryText: glossaryText,
                fontName: fontName,
                fontSize: fontSize,
                maxLines: maxLines,
                targetCharactersPerLine: targetCharactersPerLine,
                safeMargin: safeMargin,
                lineSpacing: lineSpacing,
                foregroundColor: CodableColor(color: foregroundColor),
                backgroundColor: CodableColor(color: backgroundColor),
                shadowEnabled: shadowEnabled,
                shadowRadius: shadowRadius,
                captionPosition: captionPosition.rawValue,
                captionOffsetX: captionOffsetX,
                captionOffsetY: captionOffsetY,
                keepMacAwakeDuringSession: keepMacAwakeDuringSession
            )
        )
    }

    func importGlossary() {
        let panel = NSOpenPanel()
        panel.title = "Import Glossary"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .json,
            .commaSeparatedText,
            .plainText
        ]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let importedText = try glossaryText(from: data, fileExtension: url.pathExtension.lowercased())
            glossaryText = importedText
            saveSettings()
        } catch {
            errorMessage = "Glossary import failed: \(error.localizedDescription)"
        }
    }

    func exportGlossaryJSON() {
        exportGlossary(format: .json)
    }

    func exportGlossaryCSV() {
        exportGlossary(format: .csv)
    }

    private func loadSettings() {
        guard let settings = settingsStore.load() else {
            return
        }

        mode = settings.mode
        sourceLanguage = settings.sourceLanguage
        transcriptionEngine = TranscriptionEngineChoice(rawValue: settings.transcriptionEngine) ?? .simulator
        translationEngine = TranslationEngineChoice(rawValue: settings.translationEngine) ?? .ruleBased
        sessionName = settings.sessionName
        whisperModelName = settings.whisperModelName
        translationCommandPath = settings.translationCommandPath
        translationCommandArguments = settings.translationCommandArguments
        glossaryText = settings.glossaryText
        fontName = settings.fontName
        fontSize = settings.fontSize
        maxLines = settings.maxLines
        targetCharactersPerLine = settings.targetCharactersPerLine
        safeMargin = settings.safeMargin
        lineSpacing = settings.lineSpacing
        foregroundColor = settings.foregroundColor.color
        backgroundColor = settings.backgroundColor.color
        shadowEnabled = settings.shadowEnabled
        shadowRadius = settings.shadowRadius
        captionPosition = CaptionVerticalPosition(rawValue: settings.captionPosition) ?? .bottom
        captionOffsetX = settings.captionOffsetX ?? 0
        captionOffsetY = settings.captionOffsetY ?? 0
        keepMacAwakeDuringSession = settings.keepMacAwakeDuringSession ?? true
    }

    private func exportGlossary(format: GlossaryExportFormat) {
        let panel = NSSavePanel()
        panel.title = "Export Glossary"
        panel.nameFieldStringValue = "\(sessionName.slugified)-glossary.\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data: Data
            switch format {
            case .json:
                data = try exportGlossaryJSONData()
            case .csv:
                data = exportGlossaryCSVData()
            }
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = "Glossary export failed: \(error.localizedDescription)"
        }
    }

    private func glossaryText(from data: Data, fileExtension: String) throws -> String {
        switch fileExtension {
        case "json":
            return try importGlossaryJSON(data)
        case "csv":
            return try importGlossaryCSV(data)
        default:
            guard let text = String(data: data, encoding: .utf8) else {
                throw GlossaryIOError.invalidTextEncoding
            }
            return text
        }
    }

    private func importGlossaryJSON(_ data: Data) throws -> String {
        let decoder = JSONDecoder()

        if let file = try? decoder.decode(GlossaryJSONFile.self, from: data) {
            return glossaryText(from: file.entries)
        }

        if let entries = try? decoder.decode([GlossaryJSONEntry].self, from: data) {
            return glossaryText(from: entries)
        }

        if let dictionary = try? decoder.decode([String: String].self, from: data) {
            return dictionary
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { "\($0.key) => \($0.value)" }
                .joined(separator: "\n")
        }

        throw GlossaryIOError.invalidJSON
    }

    private func importGlossaryCSV(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw GlossaryIOError.invalidTextEncoding
        }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return lines.enumerated().compactMap { index, line in
            let columns = parseCSVLine(line)
            guard columns.count >= 2 else {
                return nil
            }

            if index == 0,
               columns[0].localizedCaseInsensitiveContains("input") ||
                columns[0].localizedCaseInsensitiveContains("term") {
                return nil
            }

            let input = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let output = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !input.isEmpty, !output.isEmpty else {
                return nil
            }
            return "\(input) => \(output)"
        }
        .joined(separator: "\n")
    }

    private func exportGlossaryJSONData() throws -> Data {
        let file = GlossaryJSONFile(entries: glossaryEntriesForExport().map {
            GlossaryJSONEntry(input: $0.input, output: $0.output)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    private func exportGlossaryCSVData() -> Data {
        var lines = ["input,output"]
        lines.append(contentsOf: glossaryEntriesForExport().map {
            "\(csvEscape($0.input)),\(csvEscape($0.output))"
        })
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func glossaryEntriesForExport() -> [(input: String, output: String)] {
        glossaryText
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#") else {
                    return nil
                }

                if let separator = line.range(of: "=>") {
                    let input = line[..<separator.lowerBound]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let output = line[separator.upperBound...]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !input.isEmpty, !output.isEmpty else {
                        return nil
                    }
                    return (String(input), String(output))
                }

                return (line, line)
            }
    }

    private func glossaryText(from entries: [GlossaryJSONEntry]) -> String {
        entries.compactMap { entry in
            let input = entry.input.trimmingCharacters(in: .whitespacesAndNewlines)
            let output = entry.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !input.isEmpty, !output.isEmpty, entry.enabled ?? true else {
                return nil
            }
            return "\(input) => \(output)"
        }
        .joined(separator: "\n")
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var isQuoted = false
        var iterator = line.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if isQuoted, let next = iterator.next() {
                    if next == "\"" {
                        current.append("\"")
                    } else {
                        isQuoted = false
                        if next != "," {
                            current.append(next)
                        } else {
                            columns.append(current)
                            current = ""
                        }
                    }
                } else {
                    isQuoted.toggle()
                }
            } else if character == ",", !isQuoted {
                columns.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }

        columns.append(current)
        return columns
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    func prepareWhisperKitModel() {
        guard !isPreparingModel else {
            return
        }

        isPreparingModel = true
        modelStatus = "Preparing \(whisperModelName)"
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                self.whisperKitTranscriber.setModelName(self.whisperModelName)
                try await self.whisperKitTranscriber.prepareModel()
                self.modelStatus = "Prepared \(self.whisperModelName)"
                self.refreshResourceUsage()
            } catch {
                self.modelStatus = "Prepare failed"
                self.errorMessage = "WhisperKit model prepare failed: \(error.localizedDescription)"
            }

            self.isPreparingModel = false
        }
    }

    private func startSleepPreventionIfNeeded() {
        guard keepMacAwakeDuringSession else {
            sleepPreventionStatus = "Sleep allowed"
            return
        }

        do {
            try sleepPreventer.enable(reason: "Subtitles is running an event subtitle session.")
            sleepPreventionStatus = "Awake on"
        } catch {
            sleepPreventionStatus = "Awake failed"
            errorMessage = "Sleep prevention unavailable: \(error.localizedDescription)"
        }
    }

    private func stopSleepPrevention() {
        sleepPreventer.disable()
        updateSleepPreventionStatusForIdle()
    }

    private func updateSleepPreventionStatusForIdle() {
        sleepPreventionStatus = keepMacAwakeDuringSession ? "Awake ready" : "Sleep allowed"
    }

    private func currentResidentMemoryText() -> String {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return "Unknown"
        }

        return byteCountString(UInt64(info.resident_size))
    }

    private func byteCountString(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func startSessionLog() {
        do {
            let url = try sessionRecorder.start(
                sessionName: sessionName,
                engineName: transcriptionEngine.label,
                whisperModelName: whisperModelName,
                translationEngineName: translationEngine.label,
                captionStyle: SessionRecorder.CaptionStyleMetadata(
                    fontName: fontName,
                    fontSize: fontSize,
                    maxLines: maxLines,
                    targetCharactersPerLine: targetCharactersPerLine,
                    safeMargin: safeMargin,
                    lineSpacing: lineSpacing,
                    captionPosition: captionPosition.rawValue
                ),
                mode: mode,
                sourceLanguage: sourceLanguage,
                glossary: glossaryText
            )
            sessionDirectoryPath = url.path
            sessionSegmentCount = 0
            sessionLogStatus = "Recording"
        } catch {
            sessionDirectoryPath = nil
            sessionLogStatus = "Log unavailable"
            errorMessage = "Session log unavailable: \(error.localizedDescription)"
        }
    }

    private func stopSessionLog() {
        do {
            try sessionRecorder.stop()
            if sessionDirectoryPath != nil {
                sessionLogStatus = "Saved"
            } else {
                sessionLogStatus = "No active session"
            }
        } catch {
            sessionLogStatus = "Save failed"
            errorMessage = "Session log save failed: \(error.localizedDescription)"
        }
    }

    private func startSessionTimer() {
        sessionStartedAt = Date()
        updateSessionElapsed()
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSessionElapsed()
            }
        }
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        updateSessionElapsed()
    }

    private func updateSessionElapsed() {
        guard let sessionStartedAt else {
            sessionElapsedText = "00:00:00"
            return
        }

        let elapsed = max(0, Int(Date().timeIntervalSince(sessionStartedAt)))
        let hours = elapsed / 3_600
        let minutes = (elapsed % 3_600) / 60
        let seconds = elapsed % 60
        sessionElapsedText = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func startTranscriptionEngine() {
        switch transcriptionEngine {
        case .simulator:
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                do {
                    try await self.simulatorTranscriber.start(
                        configuration: SpeechEngineConfiguration(
                            sourceLanguage: self.sourceLanguage,
                            glossary: self.glossaryText
                        )
                    ) { [weak self] result in
                        Task { @MainActor [weak self] in
                            self?.submitRecognitionResult(result)
                        }
                    }
                } catch {
                    self.errorMessage = "Transcription unavailable: \(error.localizedDescription)"
                }
            }
        case .whisperKit:
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                do {
                    self.whisperKitTranscriber.setModelName(self.whisperModelName)
                    try await self.whisperKitTranscriber.start(
                        configuration: SpeechEngineConfiguration(
                            sourceLanguage: self.sourceLanguage,
                            glossary: self.glossaryText
                        )
                    ) { [weak self] result in
                        Task { @MainActor [weak self] in
                            self?.engineStatus = "WhisperKit running"
                            self?.submitRecognitionResult(result)
                        }
                    }
                } catch {
                    self.engineStatus = "WhisperKit failed"
                    self.errorMessage = "WhisperKit unavailable: \(error.localizedDescription)"
                }
            }
        case .audioOnly:
            currentEvent = nil
            captionLayout = CaptionLayout(lines: ["Recording audio"])
        }
    }

    private func submitRecognitionResult(_ result: SpeechRecognitionResult) {
        submitTranscript(
            result.text,
            isFinal: result.isFinal,
            detectedLanguage: result.language,
            startedAt: result.startedAt,
            endedAt: result.endedAt
        )
    }

    private func submitTranscript(
        _ text: String,
        isFinal: Bool,
        detectedLanguage: SourceLanguage? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        Task { @MainActor [weak self] in
            await self?.processTranscript(
                text,
                isFinal: isFinal,
                detectedLanguage: detectedLanguage,
                startedAt: startedAt,
                endedAt: endedAt
            )
        }
    }

    private func processTranscript(
        _ text: String,
        isFinal: Bool,
        detectedLanguage: SourceLanguage? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) async {
        let corrector = GlossaryCorrector(rawGlossary: glossaryText)
        let source = corrector.apply(to: text)
        let translated = await translate(source, isFinal: isFinal)
        let display = corrector.apply(to: translated)

        let event = TranscriptEvent(
            sourceText: source,
            displayText: display,
            isFinal: isFinal,
            startedAt: startedAt,
            endedAt: endedAt
        )

        currentEvent = event
        recomputeCaption()

        if isFinal {
            history.insert(event, at: 0)
            if history.count > 50 {
                history.removeLast(history.count - 50)
            }

            do {
                try sessionRecorder.record(
                    event: event,
                    mode: mode,
                    sourceLanguage: detectedLanguage ?? sourceLanguage
                )
                sessionSegmentCount = sessionRecorder.segmentCount
            } catch {
                sessionLogStatus = "Save failed"
                errorMessage = "Session log save failed: \(error.localizedDescription)"
            }
        }
    }

    private func translate(_ source: String, isFinal: Bool) async -> String {
        guard mode != .subtitlesOnly else {
            return source
        }

        switch translationEngine {
        case .ruleBased:
            return translator.translate(source, mode: mode)
        case .localCommand:
            guard isFinal else {
                return translator.translate(source, mode: mode)
            }

            do {
                return try await commandLineTranslator.translate(
                    text: source,
                    mode: mode,
                    executablePath: translationCommandPath,
                    argumentTemplate: translationCommandArguments
                )
            } catch {
                errorMessage = "Translation failed: \(error.localizedDescription)"
                return translator.translate(source, mode: mode)
            }
        }
    }

    private func recomputeCaption() {
        let composer = CaptionComposer(
            maxLines: maxLines,
            targetCharactersPerLine: targetCharactersPerLine
        )
        captionLayout = composer.compose(currentEvent?.displayText ?? "")
    }
}

private enum GlossaryExportFormat {
    case json
    case csv

    var fileExtension: String {
        switch self {
        case .json: "json"
        case .csv: "csv"
        }
    }

    var contentType: UTType {
        switch self {
        case .json: .json
        case .csv: .commaSeparatedText
        }
    }
}

private struct GlossaryJSONFile: Codable {
    var entries: [GlossaryJSONEntry]
}

private struct GlossaryJSONEntry: Codable {
    var input: String
    var output: String
    var language: String?
    var type: String?
    var notes: String?
    var enabled: Bool?
}

private enum GlossaryIOError: LocalizedError {
    case invalidJSON
    case invalidTextEncoding

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "JSON must be an object with an entries array, an array of entries, or a string dictionary."
        case .invalidTextEncoding:
            "The file must be UTF-8 text."
        }
    }
}

private extension String {
    var slugified: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "session" : collapsed
    }
}
