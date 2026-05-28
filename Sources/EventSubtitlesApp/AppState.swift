import AppKit
import CoreAudio
import Darwin
import EventSubtitlesCore
import EventSubtitlesRemoteControl
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    static let chromaKeyGreen = Color(.sRGB, red: 0.0, green: 177.0 / 255.0, blue: 64.0 / 255.0, opacity: 1.0)

    static func colorMatches(_ a: Color, _ b: Color, tolerance: CGFloat = 0.01) -> Bool {
        let lhs = NSColor(a).usingColorSpace(.sRGB) ?? NSColor(a)
        let rhs = NSColor(b).usingColorSpace(.sRGB) ?? NSColor(b)
        return abs(lhs.redComponent - rhs.redComponent) < tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) < tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) < tolerance
    }

    static func screenID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return number.stringValue
    }

    var mode: ProcessingMode = .subtitlesOnly {
        didSet {
            if mode != .subtitlesOnly {
                sourceLanguage = mode.sourceLanguage
            }
        }
    }
    var sourceLanguage: SourceLanguage = .automatic

    var isRunning = false
    var isStarting = false
    var audioLevel = 0.0
    var audioInputDevices: [AudioInputDeviceInfo] = []
    var selectedAudioInputDeviceID: String?
    var effectiveAudioInputDeviceID: String?
    var audioInputDescription = "Input unknown"
    var audioInputSelectionStatus = "Input unknown"
    var lastAudibleInputAt: Date?
    var isSelectedAudioInputAvailable = false
    var hasAudioCaptureFailure = false
    var didFailToStartSession = false
    var engineStatus = "Simulator idle"
    var errorMessage: String?
    var sessionName = "Main stage"
    var selectedWorkspace: OperatorWorkspace = .live
    var transcriptionEngine: TranscriptionEngineChoice = .simulator
    var whisperModelName = "large-v3-v20240930_626MB"
    var modelStatus = "Not prepared"
    var isPreparingModel = false
    var translationEngine: TranslationEngineChoice = .ruleBased
    var translationCommandPath = ""
    var translationCommandArguments = "--from {source} --to {target}"

    var currentEvent: TranscriptEvent?
    var publicCaptionText = "" {
        didSet {
            if !publicCaptionText.isEmpty && publicCaptionText != oldValue {
                lastCaptionActivityAt = Date()
            }
        }
    }
    var captionLayout = CaptionLayout(lines: []) {
        didSet { recomputeVisibleCaptionLines() }
    }
    var history: [TranscriptEvent] = []

    var fontName = "Helvetica Neue" {
        didSet { perCharWidthCache.removeValue(forKey: "\(oldValue)|\(fontSize)"); recomputeVisibleCaptionLines() }
    }
    var fontSize = 68.0 {
        didSet { recomputeCaption(); recomputeVisibleCaptionLines() }
    }
    var maxLines = 2 {
        didSet { recomputeCaption(); recomputeVisibleCaptionLines() }
    }
    var targetCharactersPerLine = 42 {
        didSet { recomputeCaption(); recomputeVisibleCaptionLines() }
    }
    var safeMargin = 78.0 {
        didSet { recomputeVisibleCaptionLines() }
    }
    var lineSpacing = 8.0
    var foregroundColor = Color.white
    var backgroundColor = AppState.chromaKeyGreen
    var shadowEnabled = true
    var shadowRadius = 7.0
    var captionPosition: CaptionVerticalPosition = .bottom
    var captionOffsetX = 0.0
    var captionOffsetY = 0.0
    var captionDisplayMode: CaptionDisplayMode = .calmBlocks
    var captionStabilityLevel: CaptionStabilityLevel = .calm
    var captionCommitDelay = CaptionStabilityLevel.calm.defaultCommitDelay
    var captionUnstableWordCount = CaptionStabilityLevel.calm.defaultUnstableWordCount
    var captionMinimumHold = CaptionStabilityLevel.calm.defaultMinimumHold
    var captionMaximumLatency = 3.0
    var captionLineMinHold = 2.0
    var captionIdleFlushAfter = 1.5
    /// Seconds of caption inactivity after which the green output auto-clears.
    /// 0 disables the auto-clear (captions stay on screen until cleared manually
    /// or until the next session begins).
    var captionAutoClearAfter = 5.0
    var draftEvent: TranscriptEvent?
    var stableCaptionQueueText = ""
    var captionDisplayLatencyText = "0.0s"

    var glossaryText = """
    kubernetes => Kubernetes
    postgres => PostgreSQL
    postgresql => PostgreSQL
    oauth => OAuth
    openai => OpenAI
    apple silicon => Apple Silicon
    macbook air => MacBook Air
    """

    var manualCaption = ""
    var outputBlanked = false
    var sessionLogStatus = "No active session"
    var sessionDirectoryPath: String?
    var sessionSegmentCount = 0
    var sessionElapsedText = "00:00:00"
    var keepMacAwakeDuringSession = true
    var sleepPreventionStatus = "Awake ready"
    var appMemoryUsageText = "Unknown"
    var selectedOutputDisplayID: String?
    var outputWindowVisible = false
    var outputWindowFilled = false
    var outputWindowDisplayID: String?
    var isTestingAudio = false
    var audioTestResult: AudioTestRecordingResult?

    @ObservationIgnored private let simulatorTranscriber = MockLocalTranscriber()
    @ObservationIgnored private let whisperKitTranscriber = WhisperKitTranscriber()
    @ObservationIgnored private let capturePipeline = AudioCapturePipeline()
    @ObservationIgnored private let audioTestRecorder = AudioTestRecorder()
    @ObservationIgnored private let translator = RuleBasedTranslator()
    @ObservationIgnored private let commandLineTranslator = CommandLineTranslator()
    @ObservationIgnored private let sessionRecorder = SessionRecorder()
    @ObservationIgnored private let sessionLogger = SessionLogger()
    @ObservationIgnored private let settingsStore = AppSettingsStore()
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    @ObservationIgnored private let sleepPreventer = SleepPreventer()
    @ObservationIgnored private var captionStabilityEngine = CaptionStabilityEngine()
    @ObservationIgnored private var captionDisplayScheduler = CaptionDisplayScheduler()
    @ObservationIgnored private var linePacedRoller = LinePacedRoller(targetCharactersPerLine: 42, maxLines: 2)
    @ObservationIgnored private var outputController: OutputWindowController?
    @ObservationIgnored private var streamDeckControlServer: StreamDeckControlServer?
    @ObservationIgnored private var streamDeckControlServerStartTask: Task<Void, Never>?
    @ObservationIgnored private var activeCaptureStartAttempt: UUID?
    @ObservationIgnored private var runningCaptureSessionID: UUID?
    @ObservationIgnored var sessionStartedAt: Date?
    @ObservationIgnored private var lastCaptionSnapshotAt: Date?
    @ObservationIgnored var lastCaptionActivityAt: Date?
    /// Pixel width of the live output window's render area. Set by SubtitleOutputView
    /// when it has `governsLayout: true`. Drives the `effectiveTargetCharactersPerLine`
    /// calculation so each logical line fits on one visual row at the chosen font.
    @ObservationIgnored private var outputRenderWidth: CGFloat = 0
    @ObservationIgnored private var sessionTimer: Timer?
    @ObservationIgnored private var captionDisplayTimer: DispatchSourceTimer?
    @ObservationIgnored private var lastDetectedLanguageForDisplay: SourceLanguage?
    @ObservationIgnored private var lastAudioLevelPublishedAt = Date.distantPast
    var visibleCaptionLines: [String] = []
    @ObservationIgnored private var perCharWidthCache: [String: CGFloat] = [:]  // key: "fontName|fontSize"

    init() {
        loadSettings()
        refreshAudioInputDevice()
        refreshResourceUsage()
        updateSleepPreventionStatusForIdle()
        startStreamDeckControlServer()
    }

    private func startStreamDeckControlServer() {
        let server = StreamDeckControlServer(
            commandHandler: { [weak self] request in
                guard let self else {
                    return StreamDeckCommandResult(id: request.id, accepted: false, reason: .internalError)
                }
                return await self.handleStreamDeckCommand(request)
            },
            statusProvider: { [weak self] in
                guard let self else {
                    return StreamDeckStatusSnapshot(
                        sessionState: .error,
                        elapsedText: "00:00:00",
                        displayState: .hidden,
                        outputState: .live,
                        captionState: .clear,
                        audioState: .unknown,
                        errorSummary: "App unavailable",
                        displayedSegmentCount: 0
                    )
                }
                return await self.streamDeckStatusSnapshot()
            },
            diagnostics: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.sessionLogger.info("Stream Deck control: \(message)")
                }
            }
        )
        streamDeckControlServer = server
        let startTask = Task { @MainActor [weak self, server] in
            guard !Task.isCancelled else {
                return
            }
            do {
                try await server.start()
                guard !Task.isCancelled else {
                    return
                }
                self?.publishStreamDeckStatus()
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.sessionLogger.error("Stream Deck control server failed: \(error.localizedDescription)")
            }
        }
        streamDeckControlServerStartTask = startTask
    }

    func publishStreamDeckStatus() {
        guard let streamDeckControlServer else {
            return
        }
        Task {
            await streamDeckControlServer.publishStatus()
        }
    }

    func stopStreamDeckControlServer() async {
        guard let streamDeckControlServer else {
            return
        }
        let startTask = streamDeckControlServerStartTask
        streamDeckControlServerStartTask = nil
        self.streamDeckControlServer = nil
        if let startTask {
            startTask.cancel()
            await startTask.value
        }
        do {
            try await streamDeckControlServer.stop()
        } catch {
            sessionLogger.error("Stream Deck control server stop failed: \(error.localizedDescription)")
        }
    }

    func start() {
        guard !isRunning, !isStarting else {
            return
        }

        let startAttemptID = UUID()
        activeCaptureStartAttempt = startAttemptID
        let captureOperationGeneration = capturePipeline.reserveControlOperation()
        didFailToStartSession = false
        hasAudioCaptureFailure = false
        isStarting = true
        errorMessage = nil
        saveSettings()
        engineStatus = "Starting capture"
        resetCaptionDisplayPipeline(clearOutput: true)
        startSessionLog()
        refreshResourceUsage()

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.activeCaptureStartAttempt == startAttemptID, self.isStarting else { return }
            do {
                try await self.capturePipeline.start(
                    operationGeneration: captureOperationGeneration,
                    inputDeviceID: self.selectedAudioInputDeviceForCapture(),
                    recordingURL: self.sessionRecorder.audioRecordingURL,
                    onLevel: { [weak self] sample in
                        Task { @MainActor [weak self] in
                            self?.publishAudioLevel(Double(max(sample.rms, sample.peak)), for: startAttemptID)
                        }
                    },
                    onSamples: { [weak self] samples in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  self.isRunning,
                                  self.runningCaptureSessionID == startAttemptID else { return }
                            self.whisperKitTranscriber.ingest(samples)
                        }
                    },
                    onConfigurationChange: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.handleAudioConfigurationChange(for: startAttemptID)
                        }
                    }
                )
                guard self.activeCaptureStartAttempt == startAttemptID else {
                    if self.activeCaptureStartAttempt == nil && !self.isRunning {
                        self.capturePipeline.stop()
                    }
                    return
                }
                guard self.isStarting else {
                    self.activeCaptureStartAttempt = nil
                    self.capturePipeline.stop()
                    return
                }
                self.activeCaptureStartAttempt = nil
                self.isRunning = true
                self.isStarting = false
                self.runningCaptureSessionID = startAttemptID
                self.hasAudioCaptureFailure = false
                self.engineStatus = self.transcriptionEngine.statusLabel
                self.startSleepPreventionIfNeeded()
                self.startSessionTimer()
                self.startCaptionDisplayTimer()
                self.refreshResourceUsage()
                self.startTranscriptionEngine()
            } catch {
                guard self.activeCaptureStartAttempt == startAttemptID else { return }
                guard self.isStarting else { return }
                self.activeCaptureStartAttempt = nil
                self.sessionLogger.error("Audio capture start failed: \(error.localizedDescription)")
                self.handleCaptureStartFailure(error)
            }
        }
    }

    func stop() async {
        guard isRunning || isStarting else { return }

        activeCaptureStartAttempt = nil
        runningCaptureSessionID = nil
        simulatorTranscriber.stopNow()
        capturePipeline.stop()
        await whisperKitTranscriber.stop()
        audioLevel = 0
        isRunning = false
        isStarting = false
        engineStatus = transcriptionEngine.idleStatusLabel
        if captionDisplayMode == .liveRollUp {
            flushLinePacedOutput(now: Date())
        } else {
            publishNextCaptionCue(force: true)
        }
        stopCaptionDisplayTimer()
        stopSleepPrevention()
        stopSessionTimer()
        stopSessionLog()
        flushSettingsImmediately()
        refreshResourceUsage()
    }

    private func handleCaptureStartFailure(_ error: Error) {
        capturePipeline.stop()
        audioLevel = 0
        isRunning = false
        isStarting = false
        runningCaptureSessionID = nil
        didFailToStartSession = true
        hasAudioCaptureFailure = true
        engineStatus = transcriptionEngine.idleStatusLabel
        stopCaptionDisplayTimer()
        stopSleepPrevention()
        stopSessionTimer()
        stopSessionLog()
        sessionLogStatus = "Start failed"
        errorMessage = "Audio capture unavailable: \(error.localizedDescription)"
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
        resetCaptionDisplayPipeline(clearOutput: true)
    }

    func panicBlank() {
        outputBlanked = true
        resetCaptionDisplayPipeline(clearOutput: true)
    }

    func toggleOutputBlank() {
        outputBlanked.toggle()
    }

    func unblankOutput() {
        outputBlanked = false
    }

    func showOutputWindow() {
        if outputController == nil {
            outputController = OutputWindowController(state: self)
        }
        outputController?.show()
    }

    @discardableResult
    func fillExternalDisplay() -> Bool {
        if outputController == nil {
            outputController = OutputWindowController(state: self)
        }
        return outputController?.fillExternalDisplay() ?? false
    }

    func restoreOutputWindow() {
        outputController?.restoreWindow()
    }

    func useChromaGreen() {
        backgroundColor = AppState.chromaKeyGreen
    }

    func useBlackBackground() {
        backgroundColor = .black
    }

    func showOutputTestCard() {
        unblankOutput()
        let display = selectedOutputDisplay?.displayLabel ?? "Output"
        publicCaptionText = "SUBTITLE TEST - \(display)"
        recomputeCaption()
    }

    func openSessionFolder() {
        guard let url = sessionRecorder.currentDirectoryURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func clearError() {
        errorMessage = nil
    }

    func selectOutputDisplay(_ id: String?) {
        selectedOutputDisplayID = id
        saveSettings()
    }

    var outputDisplays: [OutputDisplayInfo] {
        NSScreen.screens.enumerated().map { index, screen in
            let frame = screen.frame
            let id = Self.screenID(for: screen) ?? "screen-\(index)"
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            let resolution = "\(Int(frame.width)) x \(Int(frame.height))"
            let scale = Double(screen.backingScaleFactor)
                .formatted(.number.precision(.fractionLength(0...1)))
            return OutputDisplayInfo(
                id: id,
                name: name,
                frameDescription: "\(resolution) @ \(scale)x",
                isMain: screen == NSScreen.main
            )
        }
    }

    var selectedOutputDisplay: OutputDisplayInfo? {
        let displays = outputDisplays
        if let selectedOutputDisplayID,
           let display = displays.first(where: { $0.id == selectedOutputDisplayID }) {
            return display
        }
        return displays.first { !$0.isMain } ?? displays.first
    }

    var outputStatusText: String {
        if outputWindowFilled {
            return "Filled \(selectedOutputDisplay?.displayLabel ?? "display")"
        }
        if outputWindowVisible {
            return "Window visible"
        }
        return "Output not visible"
    }

    var preflightChecks: [PreflightCheck] {
        [
            audioPreflightCheck,
            audioSignalPreflightCheck,
            modelPreflightCheck,
            outputPreflightCheck,
            displayPreflightCheck,
            sessionFolderPreflightCheck,
            sleepPreflightCheck,
            translationPreflightCheck,
            glossaryPreflightCheck
        ]
    }

    var preflightSummaryStatus: OperationalStatus {
        preflightChecks.map(\.status).max() ?? .pass
    }

    var preflightSummaryText: String {
        let failed = preflightChecks.filter { $0.status == .fail }.count
        let warnings = preflightChecks.filter { $0.status == .warning }.count
        if failed > 0 {
            return "\(failed) blocked, \(warnings) check"
        }
        if warnings > 0 {
            return "\(warnings) check"
        }
        return "Ready"
    }

    private var audioPreflightCheck: PreflightCheck {
        if audioInputDevices.isEmpty || audioInputSelectionStatus == "No input device available" {
            return PreflightCheck(
                id: "audio-input",
                title: "Audio input",
                detail: "No input device is available.",
                status: .fail,
                actionTitle: "Open Audio",
                action: { [weak self] in self?.selectedWorkspace = .audio }
            )
        }

        let status: OperationalStatus = audioInputSelectionStatus.contains("unavailable") ? .warning : .pass
        return PreflightCheck(
            id: "audio-input",
            title: "Audio input",
            detail: "\(audioInputDescription) - \(audioInputSelectionStatus)",
            status: status,
            actionTitle: "Open Audio",
            action: { [weak self] in self?.selectedWorkspace = .audio }
        )
    }

    private var audioSignalPreflightCheck: PreflightCheck {
        let heardRecently = lastAudibleInputAt.map { Date().timeIntervalSince($0) < 10 } ?? false
        let hasSignal = audioLevel > 0.05 || heardRecently
        return PreflightCheck(
            id: "audio-signal",
            title: "Audio signal",
            detail: hasSignal ? "Input signal detected." : "No recent signal. Speak into the stage mic or run a test.",
            status: hasSignal || transcriptionEngine == .simulator ? .pass : .warning,
            actionTitle: "Test",
            action: { [weak self] in self?.selectedWorkspace = .audio }
        )
    }

    private var modelPreflightCheck: PreflightCheck {
        guard transcriptionEngine == .whisperKit else {
            return PreflightCheck(
                id: "model",
                title: "Model",
                detail: "\(transcriptionEngine.label) does not require a Whisper model.",
                status: .pass
            )
        }

        let prepared = modelStatus.localizedCaseInsensitiveContains("prepared")
            && modelStatus.localizedCaseInsensitiveContains(whisperModelName)
        return PreflightCheck(
            id: "model",
            title: "Whisper model",
            detail: prepared ? modelStatus : "Selected model is not prepared for offline use.",
            status: prepared ? .pass : .fail,
            actionTitle: "Open Models",
            action: { [weak self] in self?.selectedWorkspace = .models }
        )
    }

    private var outputPreflightCheck: PreflightCheck {
        PreflightCheck(
            id: "output-window",
            title: "Output window",
            detail: outputStatusText,
            status: outputWindowVisible ? .pass : .warning,
            actionTitle: outputWindowVisible ? "Open Output" : "Show",
            action: { [weak self] in
                guard let self else { return }
                if self.outputWindowVisible {
                    self.selectedWorkspace = .output
                } else {
                    self.showOutputWindow()
                }
            }
        )
    }

    private var displayPreflightCheck: PreflightCheck {
        let displays = outputDisplays
        let hasExternal = displays.contains { !$0.isMain }
        let selectedMissing = selectedOutputDisplayID != nil
            && !displays.contains { $0.id == selectedOutputDisplayID }
        let status: OperationalStatus = selectedMissing ? .warning : (hasExternal ? .pass : .warning)
        let detail: String
        if selectedMissing {
            detail = "The selected output display is no longer connected."
        } else if hasExternal {
            detail = "External display detected."
        } else {
            detail = "Only the main display is connected."
        }
        return PreflightCheck(
            id: "display",
            title: "Display",
            detail: detail,
            status: status,
            actionTitle: "Open Output",
            action: { [weak self] in self?.selectedWorkspace = .output }
        )
    }

    private var sessionFolderPreflightCheck: PreflightCheck {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let writable = documents.map { FileManager.default.isWritableFile(atPath: $0.path) } ?? false
        return PreflightCheck(
            id: "session-folder",
            title: "Session folder",
            detail: writable ? "Documents folder is writable." : "Documents folder is not writable.",
            status: writable ? .pass : .fail,
            actionTitle: "Open Logs",
            action: { [weak self] in self?.selectedWorkspace = .logs }
        )
    }

    private var sleepPreflightCheck: PreflightCheck {
        PreflightCheck(
            id: "sleep",
            title: "Power",
            detail: sleepPreventionStatus,
            status: sleepPreventionStatus == "Awake failed" ? .warning : .pass,
            actionTitle: "Open Audio",
            action: { [weak self] in self?.selectedWorkspace = .audio }
        )
    }

    private var translationPreflightCheck: PreflightCheck {
        guard mode != .subtitlesOnly, translationEngine == .localCommand else {
            return PreflightCheck(
                id: "translation",
                title: "Translation",
                detail: mode == .subtitlesOnly ? "Translation is off." : "\(translationEngine.label) is selected.",
                status: .pass
            )
        }

        let path = translationCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let executable = !path.isEmpty && FileManager.default.isExecutableFile(atPath: path)
        return PreflightCheck(
            id: "translation",
            title: "Translation command",
            detail: executable ? "Local command is executable." : "Local command path is missing or not executable.",
            status: executable ? .pass : .fail,
            actionTitle: "Open Translation",
            action: { [weak self] in self?.selectedWorkspace = .translation }
        )
    }

    private var glossaryPreflightCheck: PreflightCheck {
        let termCount = glossaryText
            .split(whereSeparator: \.isNewline)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            }
            .count
        return PreflightCheck(
            id: "glossary",
            title: "Glossary",
            detail: termCount == 0 ? "No glossary terms loaded." : "\(termCount) terms loaded.",
            status: termCount == 0 ? .warning : .pass,
            actionTitle: "Open Glossary",
            action: { [weak self] in self?.selectedWorkspace = .glossary }
        )
    }

    func outputWindowDidUpdate(isVisible: Bool, isFilled: Bool, displayID: String?) {
        outputWindowVisible = isVisible
        outputWindowFilled = isFilled
        outputWindowDisplayID = displayID
    }

    func runAudioTestRecording() {
        guard !isRunning, !isStarting, !isTestingAudio else { return }
        isTestingAudio = true
        audioTestResult = nil
        errorMessage = nil

        let input = selectedAudioInputDeviceForCapture()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.audioTestRecorder.record(inputDeviceID: input, duration: 5)
                self.audioTestResult = result
                self.sessionLogger.info("Audio test recording saved: \(result.url.path)")
            } catch {
                self.errorMessage = "Audio test recording failed: \(error.localizedDescription)"
                self.sessionLogger.error("Audio test recording failed: \(error.localizedDescription)")
            }
            self.isTestingAudio = false
        }
    }

    func revealAudioTestRecording() {
        guard let url = audioTestResult?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func refreshAudioInputDevice() {
        let devices = AudioDeviceInspector.inputDevices()
        let defaultDeviceID = AudioDeviceInspector.defaultInputDeviceID()
        let result = AudioInputSelectionResolver.resolve(
            selectedDeviceID: selectedAudioInputDeviceID,
            devices: devices.map { AudioInputSelectionDevice(id: $0.id, name: $0.name) },
            defaultDeviceID: defaultDeviceID
        )

        audioInputDevices = devices
        effectiveAudioInputDeviceID = result.effectiveDeviceID
        isSelectedAudioInputAvailable = result.effectiveDeviceID.map { effectiveID in
            devices.contains(where: { $0.id == effectiveID })
        } ?? false
        if result.status == .overrideUnavailable {
            isSelectedAudioInputAvailable = false
        }

        if let effectiveDevice = devices.first(where: { $0.id == result.effectiveDeviceID }) {
            audioInputDescription = effectiveDevice.displayName
        } else {
            audioInputDescription = "Input unknown"
        }

        audioInputSelectionStatus = audioInputStatusText(for: result)
    }

    func setSelectedAudioInputDeviceID(_ deviceID: String?) {
        selectedAudioInputDeviceID = deviceID
        refreshAudioInputDevice()
        saveSettings()
    }

    func useSystemDefaultAudioInput() {
        setSelectedAudioInputDeviceID(nil)
    }

    @MainActor
    private func handleAudioConfigurationChange(for runningSessionID: UUID) {
        guard isRunning, self.runningCaptureSessionID == runningSessionID else { return }
        refreshAudioInputDevice()
        sessionLogger.warn("Audio configuration change; restarting capture")

        let priorDescription = audioInputDescription
        engineStatus = "Capture restarting"
        let restartOperationGeneration = capturePipeline.reserveControlOperation()

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isRunning, self.runningCaptureSessionID == runningSessionID else { return }
            do {
                try await self.capturePipeline.restart(
                    operationGeneration: restartOperationGeneration,
                    inputDeviceID: self.selectedAudioInputDeviceForCapture(),
                    recordingURL: nil // Keep the active CAF writer instead of rotating files mid-session.
                )
                guard self.isRunning, self.runningCaptureSessionID == runningSessionID else { return }
                self.hasAudioCaptureFailure = false
                self.engineStatus = "Capture restarted on \(self.audioInputDescription)"
                if priorDescription != self.audioInputDescription {
                    self.errorMessage = "Audio device changed: \(self.audioInputDescription)"
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.isRunning, self.runningCaptureSessionID == runningSessionID else { return }
                self.sessionLogger.error("Capture restart failed: \(error.localizedDescription)")
                self.hasAudioCaptureFailure = true
                self.engineStatus = "Capture restart failed"
                self.errorMessage = "Audio capture restart failed: \(error.localizedDescription)"
            }
        }
    }

    private func selectedAudioInputDeviceForCapture() -> AudioDeviceID? {
        refreshAudioInputDevice()
        guard let selectedAudioInputDeviceID,
              effectiveAudioInputDeviceID == selectedAudioInputDeviceID else {
            return nil
        }

        return AudioDeviceInspector.inputDevice(id: selectedAudioInputDeviceID)?.deviceID
    }

    private func publishAudioLevel(_ level: Double, for runningSessionID: UUID) {
        guard isRunning, self.runningCaptureSessionID == runningSessionID else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAudioLevelPublishedAt) >= 1.0 / 60.0 else { return }
        lastAudioLevelPublishedAt = now
        audioLevel = level
        if level > 0.05 {
            lastAudibleInputAt = now
        }
    }

    var systemMemoryText: String {
        byteCountString(ProcessInfo.processInfo.physicalMemory)
    }

    var captionDisplayConfiguration: CaptionDisplayConfiguration {
        CaptionDisplayConfiguration(
            mode: captionDisplayMode,
            stability: captionStabilityLevel,
            commitDelay: captionCommitDelay,
            unstableWordCount: captionUnstableWordCount,
            minimumHold: captionMinimumHold,
            maximumLatency: captionMaximumLatency,
            lineMinHold: captionLineMinHold,
            idleFlushAfter: captionIdleFlushAfter
        )
    }

    /// Called by `SubtitleOutputView` (with `governsLayout: true`) on appear and
    /// on width changes. Records the actual render width so wrap can be tuned
    /// to fit one logical line on one visual row at the chosen font size.
    func applyOutputRenderWidth(_ width: CGFloat) {
        let clamped = max(0, width)
        if abs(clamped - outputRenderWidth) > 1 {
            outputRenderWidth = clamped
            recomputeVisibleCaptionLines()
        }
    }

    /// Pixel-aware wrap target. Computes how many characters of the current
    /// font fit in the available width, then caps with the operator's
    /// "Line width" slider. Falls back to the slider value if no width has
    /// been observed yet (e.g., output window not opened).
    var effectiveTargetCharactersPerLine: Int {
        let sliderValue = max(8, targetCharactersPerLine)
        guard outputRenderWidth > 0 else { return sliderValue }

        let availableWidth = max(0, outputRenderWidth - 2 * safeMargin)
        guard availableWidth > 0 else { return sliderValue }

        // Build a representative bold font in the operator's chosen face.
        let baseFont = NSFont(name: fontName, size: CGFloat(fontSize))
            ?? NSFont.systemFont(ofSize: CGFloat(fontSize))
        let boldDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.bold)
        let font = NSFont(descriptor: boldDescriptor, size: CGFloat(fontSize)) ?? baseFont

        // Measure the average pixel width of a representative wide-character run.
        // Bold sans-serif fonts at 68pt average ~37–40px per char; using a 10-char
        // sample averages out kerning variance.
        let sample = "Mwoenarsl" as NSString
        let sampleWidth = sample.size(withAttributes: [.font: font]).width
        let perChar = sampleWidth / CGFloat(sample.length)
        guard perChar > 0 else { return sliderValue }

        let fits = Int((availableWidth / perChar).rounded(.down)) - 1 // 1-char safety
        let measured = max(8, fits)

        return min(sliderValue, measured)
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

    func setCaptionDisplayMode(_ mode: CaptionDisplayMode) {
        captionDisplayMode = mode
        resetCaptionDisplayPipeline(clearOutput: false)
        saveSettings()
    }

    func setCaptionStabilityLevel(_ level: CaptionStabilityLevel) {
        captionStabilityLevel = level
        captionCommitDelay = level.defaultCommitDelay
        captionUnstableWordCount = level.defaultUnstableWordCount
        captionMinimumHold = level.defaultMinimumHold
        resetCaptionDisplayPipeline(clearOutput: false)
        saveSettings()
    }

    /// Writes the current settings to disk synchronously, cancelling any in-flight
    /// debounce. Call from `stop()` and from app termination to ensure no work is
    /// lost when the user ends a session or quits.
    func flushSettingsImmediately() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        settingsStore.save(currentAppSettings())
    }

    private func currentAppSettings() -> AppSettings {
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
            keepMacAwakeDuringSession: keepMacAwakeDuringSession,
            captionDisplayMode: captionDisplayMode,
            captionStabilityLevel: captionStabilityLevel,
            captionCommitDelay: captionCommitDelay,
            captionUnstableWordCount: captionUnstableWordCount,
            captionMinimumHold: captionMinimumHold,
            captionMaximumLatency: captionMaximumLatency,
            captionLineMinHold: captionLineMinHold,
            captionIdleFlushAfter: captionIdleFlushAfter,
            captionAutoClearAfter: captionAutoClearAfter,
            selectedAudioInputDeviceID: selectedAudioInputDeviceID,
            selectedOutputDisplayID: selectedOutputDisplayID
        )
    }

    func saveSettings() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.settingsStore.save(self.currentAppSettings())
            self.pendingSaveTask = nil
        }
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
        captionDisplayMode = settings.captionDisplayMode ?? .calmBlocks
        captionStabilityLevel = settings.captionStabilityLevel ?? .calm
        captionCommitDelay = settings.captionCommitDelay ?? captionStabilityLevel.defaultCommitDelay
        captionUnstableWordCount = settings.captionUnstableWordCount ?? captionStabilityLevel.defaultUnstableWordCount
        captionMinimumHold = settings.captionMinimumHold ?? captionStabilityLevel.defaultMinimumHold
        captionMaximumLatency = settings.captionMaximumLatency ?? 3.0
        captionLineMinHold = settings.captionLineMinHold ?? 2.0
        captionIdleFlushAfter = settings.captionIdleFlushAfter ?? 1.5
        captionAutoClearAfter = settings.captionAutoClearAfter ?? 5.0
        selectedAudioInputDeviceID = settings.selectedAudioInputDeviceID
        selectedOutputDisplayID = settings.selectedOutputDisplayID
    }

    private func audioInputStatusText(for result: AudioInputSelectionResult) -> String {
        switch result.status {
        case .usingSystemDefault:
            return "Using system default"
        case .usingOverride:
            return "Using selected interface"
        case .overrideUnavailable:
            return "Selected interface unavailable; using system default"
        case .noInputAvailable:
            return "No input device available"
        }
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
            sessionLogger.warn("Sleep prevention failed: \(error.localizedDescription)")
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
                    captionPosition: captionPosition.rawValue,
                    displayMode: captionDisplayMode.rawValue,
                    stability: captionStabilityLevel.rawValue,
                    commitDelay: captionCommitDelay,
                    minimumHold: captionMinimumHold
                ),
                mode: mode,
                sourceLanguage: sourceLanguage,
                glossary: glossaryText
            )
            sessionDirectoryPath = url.path
            sessionLogger.open(at: url)
            sessionLogger.info("Session started: name=\(sessionName) engine=\(transcriptionEngine.label) model=\(whisperModelName) device=\(audioInputDescription)")
            sessionSegmentCount = 0
            sessionLogStatus = "Recording"
        } catch {
            sessionDirectoryPath = nil
            sessionLogStatus = "Log unavailable"
            errorMessage = "Session log unavailable: \(error.localizedDescription)"
        }
    }

    private func stopSessionLog() {
        sessionLogger.info("Session stopping")
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
        sessionLogger.close()
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

    private func startCaptionDisplayTimer() {
        stopCaptionDisplayTimer()
        scheduleNextCaptionTick()
    }

    private func scheduleNextCaptionTick() {
        captionDisplayTimer?.cancel()
        let now = Date()
        let deadline = nextCaptionDeadline(now: now)
        let delay = max(0.05, deadline.timeIntervalSince(now))

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.tickCaptionDisplayPipeline()
                if self.isRunning {
                    self.scheduleNextCaptionTick()
                }
            }
        }
        timer.resume()
        captionDisplayTimer = timer
    }

    /// Computes the next time the caption pipeline should wake up. Looks at
    /// auto-clear and idle-flush deadlines. Falls back to 1 second if nothing
    /// is pending — that's the demand-driven equivalent of the old 5 Hz poll
    /// but at 1 Hz instead.
    private func nextCaptionDeadline(now: Date) -> Date {
        var deadlines: [Date?] = []

        // Auto-clear deadline
        if captionAutoClearAfter > 0, !publicCaptionText.isEmpty, let last = lastCaptionActivityAt {
            deadlines.append(last.addingTimeInterval(captionAutoClearAfter))
        }

        // Idle-flush deadline (only meaningful when not in fastDraft and pending snapshot exists)
        if captionDisplayMode != .fastDraft, mode == .subtitlesOnly, let snap = lastCaptionSnapshotAt {
            deadlines.append(snap.addingTimeInterval(captionMaximumLatency))
        }

        return CaptionTickScheduler.nearestDeadline(
            from: deadlines,
            fallback: now.addingTimeInterval(1.0)
        )
    }

    private func stopCaptionDisplayTimer() {
        captionDisplayTimer?.cancel()
        captionDisplayTimer = nil
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
                            glossary: self.glossaryText,
                            sessionName: self.sessionName
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
                guard let self else { return }
                do {
                    self.whisperKitTranscriber.setModelName(self.whisperModelName)
                    try await self.whisperKitTranscriber.start(
                        configuration: SpeechEngineConfiguration(
                            sourceLanguage: self.sourceLanguage,
                            glossary: self.glossaryText,
                            sessionName: self.sessionName
                        )
                    ) { [weak self] result in
                        Task { @MainActor [weak self] in
                            self?.engineStatus = "WhisperKit running"
                            self?.submitRecognitionResult(result)
                        }
                    }
                } catch {
                    self.sessionLogger.error("WhisperKit start failed: \(error.localizedDescription)")
                    self.engineStatus = "WhisperKit failed"
                    self.errorMessage = "WhisperKit unavailable: \(error.localizedDescription)"
                }
            }
        case .audioOnly:
            currentEvent = nil
            publicCaptionText = ""
            recomputeCaption()
            engineStatus = "Recording audio"
        }
    }

    private func submitRecognitionResult(_ result: SpeechRecognitionResult) {
        submitTranscript(
            result.text,
            isFinal: result.isFinal,
            detectedLanguage: result.language,
            startedAt: result.startedAt,
            endedAt: result.endedAt,
            words: result.words
        )
    }

    private func submitTranscript(
        _ text: String,
        isFinal: Bool,
        detectedLanguage: SourceLanguage? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        words: [RecognizedWord] = []
    ) {
        Task { @MainActor [weak self] in
            await self?.processTranscript(
                text,
                isFinal: isFinal,
                detectedLanguage: detectedLanguage,
                startedAt: startedAt,
                endedAt: endedAt,
                words: words
            )
        }
    }

    private func processTranscript(
        _ text: String,
        isFinal: Bool,
        detectedLanguage: SourceLanguage? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        words: [RecognizedWord] = []
    ) async {
        let now = Date()
        let corrector = GlossaryCorrector(rawGlossary: glossaryText)
        let draftSource = corrector.apply(to: text)
        let draftEvent = TranscriptEvent(
            sourceText: draftSource,
            displayText: draftSource,
            isFinal: isFinal,
            createdAt: now,
            startedAt: startedAt,
            endedAt: endedAt
        )
        self.draftEvent = draftEvent
        lastDetectedLanguageForDisplay = detectedLanguage ?? sourceLanguage

        if captionDisplayMode == .fastDraft {
            await publishFastDraft(
                draftSource,
                isFinal: isFinal,
                detectedLanguage: detectedLanguage,
                startedAt: startedAt,
                endedAt: endedAt,
                corrector: corrector
            )
            return
        }

        if mode != .subtitlesOnly, !isFinal {
            updateCaptionSchedulerStatus()
            return
        }

        let snapshot = TranscriptSnapshot(text: text, createdAt: now, isFinal: isFinal, words: words)
        lastCaptionSnapshotAt = isFinal ? nil : snapshot.createdAt

        let phrases = captionStabilityEngine.ingest(
            snapshot,
            configuration: captionDisplayConfiguration
        )

        let isRolling = captionDisplayMode == .liveRollUp
        let configuration = captionDisplayConfiguration
        linePacedRoller.updateLayout(
            targetCharactersPerLine: effectiveTargetCharactersPerLine,
            maxLines: maxLines
        )

        for phrase in phrases {
            let stableSource = corrector.apply(to: phrase.text)
            let translated = await translate(stableSource, isFinal: phrase.isFinal)
            let display = corrector.apply(to: translated)

            if isRolling {
                let rolling = StableCaptionPhrase(
                    text: display,
                    committedAt: phrase.committedAt,
                    isFinal: phrase.isFinal
                )
                linePacedRoller.ingest(rolling, now: phrase.committedAt)
            } else {
                captionDisplayScheduler.enqueue(
                    sourceText: stableSource,
                    displayText: display,
                    now: phrase.committedAt
                )
            }
        }

        if isRolling {
            refreshLinePacedOutput(
                now: Date(),
                configuration: configuration
            )
        } else {
            publishNextCaptionCue(force: isFinal)
        }

        if isFinal {
            lastCaptionSnapshotAt = nil
        }

        if isRunning { scheduleNextCaptionTick() }
    }

    private func publishFastDraft(
        _ source: String,
        isFinal: Bool,
        detectedLanguage: SourceLanguage? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        corrector: GlossaryCorrector
    ) async {
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
        publicCaptionText = display
        recomputeCaption()

        if isFinal {
            recordDisplayedEvent(event, detectedLanguage: detectedLanguage)
        }

        if isRunning { scheduleNextCaptionTick() }
    }

    private func publishNextCaptionCue(force: Bool = false) {
        guard let cue = captionDisplayScheduler.nextCueIfDue(
            configuration: captionDisplayConfiguration,
            force: force
        ) else {
            updateCaptionSchedulerStatus()
            return
        }

        let event = TranscriptEvent(
            sourceText: cue.sourceText,
            displayText: cue.displayText,
            isFinal: true,
            createdAt: cue.startsAt,
            startedAt: nil,
            endedAt: nil
        )

        currentEvent = event
        switch captionDisplayMode {
        case .calmBlocks, .fastDraft:
            publicCaptionText = cue.displayText
            recomputeCaption()
        case .liveRollUp:
            let rollingText = [captionLayout.text, cue.displayText]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " ")
            publicCaptionText = rollingText
            let composer = CaptionComposer(
                maxLines: maxLines,
                targetCharactersPerLine: targetCharactersPerLine
            )
            captionLayout = composer.compose(rollingText)
        }

        recordDisplayedEvent(event, detectedLanguage: lastDetectedLanguageForDisplay)
        updateCaptionSchedulerStatus()
        if isRunning { scheduleNextCaptionTick() }
    }

    private func refreshLinePacedOutput(
        now: Date,
        configuration: CaptionDisplayConfiguration
    ) {
        linePacedRoller.updateLayout(
            targetCharactersPerLine: effectiveTargetCharactersPerLine,
            maxLines: maxLines
        )
        let changed = linePacedRoller.tick(
            now: now,
            lineMinHold: configuration.lineMinHold,
            idleFlushAfter: configuration.idleFlushAfter
        )

        // Record any lines the line builder emitted since the last refresh into
        // the history / session log. This is the rolling-mode equivalent of
        // calmBlocks's recordDisplayedEvent on each scheduler cue.
        let emittedLines = linePacedRoller.drainEmittedLines()
        for line in emittedLines {
            let event = TranscriptEvent(
                sourceText: line,
                displayText: line,
                isFinal: true,
                createdAt: now
            )
            recordDisplayedEvent(event, detectedLanguage: lastDetectedLanguageForDisplay)
        }

        let lines = linePacedRoller.visibleLines
        let joined = lines.joined(separator: " ")

        if joined != publicCaptionText {
            publicCaptionText = joined
        }
        if lines != captionLayout.lines {
            captionLayout = CaptionLayout(lines: lines)
        }

        updateCaptionSchedulerStatus()
        _ = changed // explicit no-op so the compiler doesn't complain about the unused return
    }

    private func flushLinePacedOutput(now: Date) {
        linePacedRoller.updateLayout(
            targetCharactersPerLine: effectiveTargetCharactersPerLine,
            maxLines: maxLines
        )
        _ = linePacedRoller.tick(
            now: now,
            lineMinHold: 0,
            idleFlushAfter: 0
        )

        let emittedLines = linePacedRoller.drainEmittedLines()
        for line in emittedLines {
            let event = TranscriptEvent(
                sourceText: line,
                displayText: line,
                isFinal: true,
                createdAt: now
            )
            recordDisplayedEvent(event, detectedLanguage: lastDetectedLanguageForDisplay)
        }

        let lines = linePacedRoller.visibleLines
        publicCaptionText = lines.joined(separator: " ")
        captionLayout = CaptionLayout(lines: lines)
        updateCaptionSchedulerStatus()
    }

    private func tickCaptionDisplayPipeline() async {
        if captionDisplayMode == .liveRollUp {
            refreshLinePacedOutput(
                now: Date(),
                configuration: captionDisplayConfiguration
            )
        } else {
            await flushIdleCaptionTailIfNeeded()
            publishNextCaptionCue()
        }
        checkAutoClearIfNeeded(now: Date())
    }

    /// If captions have sat unchanged for `captionAutoClearAfter` seconds, clear
    /// the visible state and reset the underlying pipelines so the next utterance
    /// starts fresh.
    private func checkAutoClearIfNeeded(now: Date) {
        guard captionAutoClearAfter > 0 else { return }
        guard !publicCaptionText.isEmpty else { return }
        guard let lastActivity = lastCaptionActivityAt else { return }
        guard now.timeIntervalSince(lastActivity) >= captionAutoClearAfter else { return }

        captionStabilityEngine.reset()
        captionDisplayScheduler.reset()
        linePacedRoller.reset()
        linePacedRoller.updateLayout(
            targetCharactersPerLine: effectiveTargetCharactersPerLine,
            maxLines: maxLines
        )
        currentEvent = nil
        draftEvent = nil
        publicCaptionText = ""
        captionLayout = CaptionLayout(lines: [])
        stableCaptionQueueText = ""
        captionDisplayLatencyText = "0.0s"
        lastCaptionSnapshotAt = nil
        lastCaptionActivityAt = nil
    }

    private func flushIdleCaptionTailIfNeeded() async {
        guard captionDisplayMode != .fastDraft, mode == .subtitlesOnly, let lastCaptionSnapshotAt else {
            return
        }

        let configuration = captionDisplayConfiguration
        let now = Date()
        guard now.timeIntervalSince(lastCaptionSnapshotAt) >= configuration.maximumLatency else {
            return
        }

        let phrases = captionStabilityEngine.flushPending(committedAt: now, isFinal: false)
        guard !phrases.isEmpty else {
            self.lastCaptionSnapshotAt = nil
            return
        }

        self.lastCaptionSnapshotAt = nil
        let corrector = GlossaryCorrector(rawGlossary: glossaryText)
        for phrase in phrases {
            let stableSource = corrector.apply(to: phrase.text)
            let translated = await translate(stableSource, isFinal: true)
            let display = corrector.apply(to: translated)
            captionDisplayScheduler.enqueue(
                sourceText: stableSource,
                displayText: display,
                now: phrase.committedAt
            )
        }
    }

    private func recordDisplayedEvent(
        _ event: TranscriptEvent,
        detectedLanguage: SourceLanguage? = nil
    ) {
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

    private func resetCaptionDisplayPipeline(clearOutput: Bool) {
        captionStabilityEngine.reset()
        captionDisplayScheduler.reset()
        linePacedRoller.reset()
        linePacedRoller.updateLayout(
            targetCharactersPerLine: effectiveTargetCharactersPerLine,
            maxLines: maxLines
        )
        stableCaptionQueueText = ""
        captionDisplayLatencyText = "0.0s"
        lastDetectedLanguageForDisplay = nil
        lastCaptionSnapshotAt = nil

        if clearOutput {
            currentEvent = nil
            draftEvent = nil
            publicCaptionText = ""
            captionLayout = CaptionLayout(lines: [])
        }
    }

    private func updateCaptionSchedulerStatus() {
        stableCaptionQueueText = captionDisplayScheduler.pendingDisplayText
        captionDisplayLatencyText = captionDisplayScheduler.estimatedLatencyText()
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
                sessionLogger.error("Translation failed: \(error.localizedDescription)")
                errorMessage = "Translation failed: \(error.localizedDescription)"
                return translator.translate(source, mode: mode)
            }
        }
    }

    private func recomputeCaption() {
        if captionDisplayMode == .liveRollUp {
            linePacedRoller.updateLayout(
                targetCharactersPerLine: effectiveTargetCharactersPerLine,
                maxLines: maxLines
            )
            captionLayout = CaptionLayout(lines: linePacedRoller.visibleLines)
            publicCaptionText = captionLayout.text.replacingOccurrences(of: "\n", with: " ")
            return
        }

        let composer = CaptionComposer(
            maxLines: maxLines,
            targetCharactersPerLine: targetCharactersPerLine
        )
        captionLayout = composer.compose(publicCaptionText)
    }

    /// Recomputes the visible logical lines for the audience-facing output. Called
    /// whenever captionLayout, fontName, fontSize, maxLines, safeMargin, or
    /// outputRenderWidth changes. Caches per-character widths per (fontName, fontSize)
    /// so the per-word NSAttributedString measurement runs at most once per font.
    func recomputeVisibleCaptionLines() {
        let candidates = captionLayout.lines
        guard !candidates.isEmpty, maxLines > 0 else {
            if !visibleCaptionLines.isEmpty { visibleCaptionLines = [] }
            return
        }

        let availableWidth = max(100, outputRenderWidth - 2 * safeMargin)
        let cacheKey = "\(fontName)|\(fontSize)"
        let perChar: CGFloat
        if let cached = perCharWidthCache[cacheKey] {
            perChar = cached
        } else {
            let baseFont = NSFont(name: fontName, size: CGFloat(fontSize))
                ?? NSFont.systemFont(ofSize: CGFloat(fontSize))
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.bold)
            let font = NSFont(descriptor: descriptor, size: CGFloat(fontSize)) ?? baseFont
            let sample = "Mwoenarsl" as NSString
            let sampleWidth = sample.size(withAttributes: [.font: font]).width
            perChar = sampleWidth / CGFloat(sample.length)
            perCharWidthCache[cacheKey] = perChar
        }
        guard perChar > 0 else { return }

        let measure: (String) -> Int = { line in
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { return 0 }
            var lines = 1
            var currentWidth: CGFloat = 0
            for word in words {
                let wordWidth = CGFloat(word.count + 1) * perChar
                if currentWidth + wordWidth <= availableWidth || currentWidth == 0 {
                    currentWidth += wordWidth
                } else {
                    lines += 1
                    currentWidth = wordWidth
                }
            }
            return lines
        }

        let picked = CaptionLineFitter.pickVisibleLogicalLines(
            candidates: candidates,
            maxVisualLines: maxLines,
            measureVisualLineCount: measure
        )
        if picked != visibleCaptionLines {
            visibleCaptionLines = picked
        }
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
