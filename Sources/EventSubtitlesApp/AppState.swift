import AppKit
import EventSubtitlesCore
import SwiftUI

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

    private let simulatorTranscriber = MockLocalTranscriber()
    private let whisperKitTranscriber = WhisperKitTranscriber()
    private let audioMonitor = AudioLevelMonitor()
    private let translator = RuleBasedTranslator()
    private let commandLineTranslator = CommandLineTranslator()
    private let sessionRecorder = SessionRecorder()
    private let settingsStore = AppSettingsStore()
    private var outputController: OutputWindowController?
    private var sessionStartedAt: Date?
    private var sessionTimer: Timer?

    init() {
        loadSettings()
        refreshAudioInputDevice()
    }

    func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        errorMessage = nil
        saveSettings()
        engineStatus = transcriptionEngine.statusLabel
        startSessionLog()
        startSessionTimer()

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
        engineStatus = "Simulator idle"
        stopSessionTimer()
        stopSessionLog()
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
                captionPosition: captionPosition.rawValue
            )
        )
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
            } catch {
                self.modelStatus = "Prepare failed"
                self.errorMessage = "WhisperKit model prepare failed: \(error.localizedDescription)"
            }

            self.isPreparingModel = false
        }
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
