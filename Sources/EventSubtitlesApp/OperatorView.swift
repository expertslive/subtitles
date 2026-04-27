import EventSubtitlesCore
import SwiftUI

struct OperatorView: View {
    @EnvironmentObject private var state: AppState

    private let operatorStripWidth: CGFloat = 390

    @State private var selectedWorkspace: OperatorWorkspace = .live
    @State private var glossarySearch = ""
    @State private var glossaryTestInput = "We deploy kubernetes with postgres and oauth on apple silicon."
    @State private var translationTestInput = "Welcome developers, this conference session is about cloud latency and security."

    var body: some View {
        HStack(spacing: 0) {
            operatorStrip
                .frame(width: operatorStripWidth)

            Divider()

            workspaceShell
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var operatorStrip: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                sessionControls
                quickOutputControls
            }
            .padding(14)
            .frame(width: operatorStripWidth, alignment: .topLeading)
        }
    }

    private var workspaceShell: some View {
        VStack(alignment: .leading, spacing: 16) {
            workspaceTabs

            HStack {
                Label(selectedWorkspace.title, systemImage: selectedWorkspace.systemImage)
                    .font(.title2.weight(.semibold))

                Spacer()

                Text(state.isRunning ? "Running" : "Idle")
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(state.isRunning ? Color.green.opacity(0.22) : Color.secondary.opacity(0.16))
                    .clipShape(Capsule())
            }

            workspaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(22)
    }

    private var workspaceTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(OperatorWorkspace.allCases) { workspace in
                    Button {
                        selectedWorkspace = workspace
                    } label: {
                        Label(workspace.title, systemImage: workspace.systemImage)
                            .font(.callout.weight(selectedWorkspace == workspace ? .semibold : .regular))
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(selectedWorkspace == workspace ? Color.accentColor.opacity(0.22) : Color(nsColor: .controlBackgroundColor).opacity(0.72))
                            .foregroundStyle(selectedWorkspace == workspace ? Color.accentColor : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        selectedWorkspace == workspace ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.16),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help(workspace.title)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch selectedWorkspace {
        case .live:
            liveWorkspace
        case .style:
            styleWorkspace
        case .glossary:
            glossaryWorkspace
        case .logs:
            logsWorkspace
        case .models:
            modelsWorkspace
        case .translation:
            translationWorkspace
        case .audio:
            audioWorkspace
        case .output:
            outputWorkspace
        }
    }

    private var sessionControls: some View {
        ControlPanel(title: "Session") {
            TextField("Session name", text: $state.sessionName)
                .textFieldStyle(.roundedBorder)

            Picker("Capture", selection: $state.transcriptionEngine) {
                ForEach(TranscriptionEngineChoice.allCases) { engine in
                    Text(engine.label).tag(engine)
                }
            }
            .disabled(state.isRunning)

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                Text(state.transcriptionEngine.helpText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Picker("Mode", selection: $state.mode) {
                ForEach(ProcessingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("Source", selection: $state.sourceLanguage) {
                ForEach(SourceLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }

            audioInputRow
            sleepPreventionRow

            HStack {
                Button {
                    state.isRunning ? state.stop() : state.start()
                } label: {
                    Label(state.isRunning ? "Stop" : "Start", systemImage: state.isRunning ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    state.clearCaptions()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
            }

            AudioMeter(level: state.audioLevel)

            sessionStatusRow

            if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                TextField("Manual caption", text: $state.manualCaption)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        state.pushManualCaption()
                    }

                Button {
                    state.pushManualCaption()
                } label: {
                    Image(systemName: "text.bubble")
                }
                .help("Send manual caption")
            }
        }
    }

    private var quickOutputControls: some View {
        ControlPanel(title: "Output") {
            Button {
                state.showOutputWindow()
            } label: {
                Label("Show Window", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Button {
                    state.fillExternalDisplay()
                } label: {
                    Label("Fill Display", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    state.restoreOutputWindow()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .help("Restore output window")
            }
        }
    }

    private var audioInputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            Text(state.audioInputDescription)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                state.refreshAudioInputDevice()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh audio input")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var sleepPreventionRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(
                "Keep Mac awake",
                isOn: Binding(
                    get: { state.keepMacAwakeDuringSession },
                    set: { state.setKeepMacAwakeDuringSession($0) }
                )
            )

            Spacer(minLength: 8)

            Label(
                state.sleepPreventionStatus,
                systemImage: state.keepMacAwakeDuringSession ? "moon.zzz.slash" : "moon.zzz"
            )
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .foregroundStyle(state.sleepPreventionStatus == "Awake failed" ? .orange : .secondary)
        }
        .font(.caption)
        .help("Keeps the Mac and connected output display awake while a session is running.")
    }

    private var sessionStatusRow: some View {
        HStack(spacing: 7) {
            Text(state.engineStatus)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(state.sessionElapsedText)
                .monospacedDigit()

            Image(systemName: state.sessionLogStatus == "Recording" ? "record.circle.fill" : "checkmark.circle")
                .foregroundStyle(state.sessionLogStatus == "Recording" ? .red : .secondary)

            Text(state.sessionLogStatus)
                .lineLimit(1)

            Text("\(state.sessionSegmentCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var liveWorkspace: some View {
        GeometryReader { proxy in
            let useColumns = proxy.size.width >= 980
            let historyWidth = min(390, max(320, proxy.size.width * 0.28))

            if useColumns {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        previewPanel(maxHeight: 430)
                        currentTranscript
                            .frame(minHeight: 150)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    historyPanel
                        .frame(width: historyWidth)
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    previewPanel(maxHeight: 430)
                    currentTranscript
                        .frame(minHeight: 150)
                    historyPanel
                }
            }
        }
    }

    private var compactLiveWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            previewPanel(maxHeight: 430)
            HStack(alignment: .top, spacing: 18) {
                currentTranscript
                historyPanel
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var styleWorkspace: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    ControlPanel(title: "Typography") {
                        typographyControls
                    }

                    ControlPanel(title: "Layout") {
                        layoutControls
                    }
                }
                .frame(width: 430)

                VStack(alignment: .leading, spacing: 16) {
                    previewPanel(maxHeight: 360)

                    ControlPanel(title: "Color And Shadow") {
                        colorControls
                    }

                    ControlPanel(title: "Presets") {
                        stylePresetControls
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var typographyControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Font") {
                Picker("Font", selection: $state.fontName) {
                    ForEach(["Helvetica Neue", "Arial", "Avenir Next", "Menlo"], id: \.self) { fontName in
                        Text(fontName).tag(fontName)
                    }
                }
                .labelsHidden()
            }

            SliderRow(title: "Font size", value: $state.fontSize, range: 18...120, step: 1)
            SliderRow(title: "Line width", value: Binding(
                get: { Double(state.targetCharactersPerLine) },
                set: { state.targetCharactersPerLine = Int($0) }
            ), range: 12...60, step: 1)

            Button {
                state.saveSettings()
            } label: {
                Label("Save Settings", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var layoutControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SliderRow(title: "Safe margin", value: $state.safeMargin, range: 28...180, step: 1)
            SliderRow(title: "Line spacing", value: $state.lineSpacing, range: 0...28, step: 1)

            HStack(spacing: 12) {
                Text("Lines")

                Picker("Lines", selection: $state.maxLines) {
                    Text("2").tag(2)
                    Text("3").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(width: 92)

                Spacer()
            }

            Picker("Position", selection: $state.captionPosition) {
                ForEach(CaptionVerticalPosition.allCases) { position in
                    Text(position.label).tag(position)
                }
            }
            .pickerStyle(.segmented)

            captionFinePositionControls
        }
    }

    private var captionFinePositionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fine position")
                Spacer()
                Text("X \(Int(state.captionOffsetX)) / Y \(Int(state.captionOffsetY))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                VStack(spacing: 6) {
                    positionNudgeButton(systemImage: "arrow.up", help: "Move captions up") {
                        state.captionOffsetY -= 8
                    }

                    HStack(spacing: 6) {
                        positionNudgeButton(systemImage: "arrow.left", help: "Move captions left") {
                            state.captionOffsetX -= 8
                        }

                        Button {
                            state.captionOffsetX = 0
                            state.captionOffsetY = 0
                        } label: {
                            Image(systemName: "scope")
                                .frame(width: 28, height: 28)
                        }
                        .help("Reset caption offset")

                        positionNudgeButton(systemImage: "arrow.right", help: "Move captions right") {
                            state.captionOffsetX += 8
                        }
                    }

                    positionNudgeButton(systemImage: "arrow.down", help: "Move captions down") {
                        state.captionOffsetY += 8
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Stepper("Horizontal", value: $state.captionOffsetX, in: -400...400, step: 1)
                    Stepper("Vertical", value: $state.captionOffsetY, in: -300...300, step: 1)
                }
            }
        }
    }

    private func positionNudgeButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
        }
        .help(help)
    }

    private var colorControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                ColorPicker("Text", selection: $state.foregroundColor)
                ColorPicker("Background", selection: $state.backgroundColor)
            }

            Toggle("Text shadow", isOn: $state.shadowEnabled)
            SliderRow(title: "Shadow", value: $state.shadowRadius, range: 0...18, step: 1)
        }
    }

    private var stylePresetControls: some View {
        HStack {
            Button {
                state.useChromaGreen()
                state.foregroundColor = .white
                state.shadowEnabled = true
                state.captionPosition = .bottom
            } label: {
                Label("Chroma", systemImage: "wand.and.stars")
            }

            Button {
                state.useBlackBackground()
                state.foregroundColor = .white
                state.shadowEnabled = false
                state.captionPosition = .bottom
            } label: {
                Label("Black", systemImage: "rectangle.fill")
            }

            Button {
                state.foregroundColor = .yellow
                state.useBlackBackground()
                state.shadowEnabled = false
                state.fontSize = 78
            } label: {
                Label("High Contrast", systemImage: "circle.lefthalf.filled")
            }
        }
    }

    private var glossaryWorkspace: some View {
        GeometryReader { proxy in
            let useColumns = proxy.size.width >= 920
            let toolsWidth = min(420, max(340, proxy.size.width * 0.34))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    glossaryHeader

                    if useColumns {
                        HStack(alignment: .top, spacing: 18) {
                            glossaryEditorPanel
                                .frame(maxWidth: .infinity)

                            glossaryToolsPanel
                                .frame(width: toolsWidth)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            glossaryEditorPanel
                            glossaryToolsPanel
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var glossaryHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                TextField("Search glossary", text: $glossarySearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)

                Spacer()

                glossaryFileActions
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Search glossary", text: $glossarySearch)
                    .textFieldStyle(.roundedBorder)

                glossaryFileActions
            }
        }
    }

    private var glossaryFileActions: some View {
        HStack(spacing: 8) {
            Button {
                state.importGlossary()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down.on.square")
            }

            Menu {
                Button {
                    state.exportGlossaryJSON()
                } label: {
                    Label("JSON", systemImage: "curlybraces")
                }

                Button {
                    state.exportGlossaryCSV()
                } label: {
                    Label("CSV", systemImage: "tablecells")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Button {
                state.saveSettings()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
        }
    }

    private var glossaryEditorPanel: some View {
        ControlPanel(title: "Glossary Editor") {
            TextEditor(text: $state.glossaryText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 420)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                }
        }
    }

    private var glossaryToolsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            ControlPanel(title: "Term Table") {
                glossaryTable
            }

            ControlPanel(title: "Test Phrase") {
                glossaryTestPanel
            }
        }
    }

    private var glossaryTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Output")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredGlossaryEntries) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.input)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)
                            Text(entry.output)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)
                        }
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                        Divider()
                    }

                    if filteredGlossaryEntries.isEmpty {
                        Text("No terms")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 190)
        }
    }

    private var glossaryTestPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Test phrase", text: $glossaryTestInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            Divider()

            Text(glossaryTestOutput)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var logsWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    ControlPanel(title: "Current Session") {
                        LabeledContent("Status", value: state.sessionLogStatus)
                        LabeledContent("Segments", value: "\(state.sessionSegmentCount)")
                        LabeledContent("Elapsed", value: state.sessionElapsedText)
                    }
                    .frame(width: 300)

                    ControlPanel(title: "Session Folder") {
                        if let path = state.sessionDirectoryPath {
                            Text(path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                                .textSelection(.enabled)

                            Button {
                                state.openSessionFolder()
                            } label: {
                                Label("Open Folder", systemImage: "folder")
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            Text("No active session folder")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: 18) {
                    ControlPanel(title: "Files") {
                        logFileList
                    }
                    .frame(width: 300)

                    ControlPanel(title: "Captured Captions") {
                        captionHistoryList
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var logFileList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sessionFileNames, id: \.self) { fileName in
                Label(fileName, systemImage: "doc.text")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelsWorkspace: some View {
        GeometryReader { proxy in
            let useColumns = proxy.size.width >= 800
            let readinessWidth = min(360, max(300, proxy.size.width * 0.34))

            ScrollView {
                Group {
                    if useColumns {
                        HStack(alignment: .top, spacing: 18) {
                            modelSetupPanel
                                .frame(maxWidth: .infinity)

                            modelSideColumn
                                .frame(width: readinessWidth)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            modelSetupPanel
                            modelSideColumn
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var modelSideColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            offlineReadinessPanel
            modelPreparationPanel
            modelResourcesPanel
        }
    }

    private var modelSetupPanel: some View {
        ControlPanel(title: "WhisperKit Model") {
            modelControls
        }
    }

    private var offlineReadinessPanel: some View {
        ControlPanel(title: "Offline Readiness") {
            LabeledContent("Engine", value: state.transcriptionEngine.label)
            LabeledContent("Model", value: state.whisperModelName)
            LabeledContent("Status", value: state.modelStatus)
            LabeledContent("Running", value: state.isRunning ? "Yes" : "No")
        }
    }

    private var modelPreparationPanel: some View {
        ControlPanel(title: "Prepare Model") {
            VStack(alignment: .leading, spacing: 10) {
                Label("Caches the selected WhisperKit model for offline use.", systemImage: "externaldrive")
                Label("Run this before the event while you still have network.", systemImage: "wifi")
                Label("The first Start can take a few seconds while the model warms up.", systemImage: "timer")
                Label("After Stop, the model stays loaded so restart is faster.", systemImage: "bolt")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelResourcesPanel: some View {
        ControlPanel(title: "Resources") {
            LabeledContent("Mac memory", value: state.systemMemoryText)
            LabeledContent("App memory", value: state.appMemoryUsageText)
            LabeledContent("CPU/GPU", value: "Activity Monitor")

            Text("Large models can use several GB while loaded. If memory pressure turns yellow or red, switch to a smaller model or close other apps.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    state.refreshResourceUsage()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    state.openActivityMonitor()
                } label: {
                    Label("Activity Monitor", systemImage: "gauge")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            state.refreshResourceUsage()
        }
    }

    private var modelControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Whisper model", selection: $state.whisperModelName) {
                Text("Large v3 626 MB").tag("large-v3-v20240930_626MB")
                Text("Large v3 turbo 632 MB").tag("large-v3-v20240930_turbo_632MB")
                Text("Distil large v3 594 MB").tag("distil-large-v3_594MB")
                Text("Small").tag("small")
                Text("Base").tag("base")
                Text("Tiny").tag("tiny")
            }
            .disabled(state.isRunning || state.isPreparingModel)

            TextField("Model name", text: $state.whisperModelName)
                .textFieldStyle(.roundedBorder)
                .disabled(state.isRunning || state.isPreparingModel)

            Button {
                state.prepareWhisperKitModel()
            } label: {
                Label(
                    state.isPreparingModel ? "Preparing" : "Prepare Offline Model",
                    systemImage: "arrow.down.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .disabled(state.isRunning || state.isPreparingModel)

            Text(state.modelStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var translationWorkspace: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 18) {
                ControlPanel(title: "Translation") {
                    translationControls
                }
                .frame(width: 440)

                ControlPanel(title: "Test Translation") {
                    translationTestPanel
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var translationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $state.mode) {
                ForEach(ProcessingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("Engine", selection: $state.translationEngine) {
                ForEach(TranslationEngineChoice.allCases) { engine in
                    Text(engine.label).tag(engine)
                }
            }

            TextField("Executable path", text: $state.translationCommandPath)
                .textFieldStyle(.roundedBorder)
                .disabled(state.translationEngine != .localCommand)

            TextField("Arguments", text: $state.translationCommandArguments)
                .textFieldStyle(.roundedBorder)
                .disabled(state.translationEngine != .localCommand)
        }
    }

    private var translationTestPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Test caption", text: $translationTestInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(translationPreviewSource)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Display")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(translationPreviewDisplay)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var audioWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    ControlPanel(title: "Input") {
                        audioInputRow

                        Button {
                            state.refreshAudioInputDevice()
                        } label: {
                            Label("Refresh Input", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: 360)

                    ControlPanel(title: "Level") {
                        AudioMeter(level: state.audioLevel)
                            .frame(height: 22)

                        LabeledContent("Level", value: "\(Int(state.audioLevel * 100))%")
                        LabeledContent("Clipping", value: state.audioLevel > 0.92 ? "Yes" : "No")
                    }
                    .frame(width: 280)
                }

                ControlPanel(title: "Recording") {
                    LabeledContent("Status", value: state.sessionLogStatus)
                    LabeledContent("Segments", value: "\(state.sessionSegmentCount)")

                    if let path = state.sessionDirectoryPath {
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: 660)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var outputWorkspace: some View {
        GeometryReader { proxy in
            let useColumns = proxy.size.width >= 900
            let controlsWidth = min(380, max(330, proxy.size.width * 0.3))

            ScrollView {
                Group {
                    if useColumns {
                        HStack(alignment: .top, spacing: 18) {
                            outputSetupColumn
                                .frame(width: controlsWidth)

                            outputPreviewColumn
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            outputPreviewColumn
                            outputSetupColumn
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var outputSetupColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            outputWindowPanel
            outputBackgroundPanel
        }
    }

    private var outputPreviewColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            previewPanel(maxHeight: 430)
            outputSignalPanel
        }
    }

    private var outputWindowPanel: some View {
        ControlPanel(title: "Output Window") {
            Button {
                state.showOutputWindow()
            } label: {
                Label("Show Output Window", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }

            Button {
                state.fillExternalDisplay()
            } label: {
                Label("Fill Display", systemImage: "arrow.up.left.and.arrow.down.right")
                    .frame(maxWidth: .infinity)
            }

            Button {
                state.restoreOutputWindow()
            } label: {
                Label("Restore Window", systemImage: "arrow.down.right.and.arrow.up.left")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var outputBackgroundPanel: some View {
        ControlPanel(title: "Background") {
            HStack(alignment: .top, spacing: 12) {
                backgroundSwatch

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        state.useChromaGreen()
                    } label: {
                        Label("Chroma Green", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        state.useBlackBackground()
                    } label: {
                        Label("Black", systemImage: "rectangle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var outputSignalPanel: some View {
        ControlPanel(title: "Signal") {
            HStack(alignment: .top, spacing: 18) {
                LabeledContent("Position", value: state.captionPosition.label)
                LabeledContent("Lines", value: "\(state.maxLines)")
                LabeledContent("Safe margin", value: "\(Int(state.safeMargin))")
            }
        }
    }

    private var currentTranscript: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current")
                .font(.headline)

            Text(state.currentEvent?.sourceText ?? "No transcript yet.")
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.primary)

            if state.mode != .subtitlesOnly {
                Divider()
                Text(state.currentEvent?.displayText ?? "")
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline)

            captionHistoryList
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var captionHistoryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(state.history) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.displayText)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(event.createdAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }

                if state.history.isEmpty {
                    Text("No captions yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func previewPanel(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Preview")
                .font(.headline)

            SubtitleOutputView()
                .environmentObject(state)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25))
                }
        }
    }

    private var backgroundSwatch: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(state.backgroundColor)
            .frame(width: 96, height: 96)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3))
            }
    }

    private var glossaryEntries: [GlossaryEntry] {
        state.glossaryText
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

                    return GlossaryEntry(input: String(input), output: String(output))
                }

                return GlossaryEntry(input: line, output: line)
            }
    }

    private var filteredGlossaryEntries: [GlossaryEntry] {
        let search = glossarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else {
            return glossaryEntries
        }

        return glossaryEntries.filter { entry in
            entry.input.localizedCaseInsensitiveContains(search) ||
                entry.output.localizedCaseInsensitiveContains(search)
        }
    }

    private var glossaryTestOutput: String {
        GlossaryCorrector(rawGlossary: state.glossaryText).apply(to: glossaryTestInput)
    }

    private var translationPreviewSource: String {
        GlossaryCorrector(rawGlossary: state.glossaryText).apply(to: translationTestInput)
    }

    private var translationPreviewDisplay: String {
        let translated = RuleBasedTranslator().translate(translationPreviewSource, mode: state.mode)
        return GlossaryCorrector(rawGlossary: state.glossaryText).apply(to: translated)
    }

    private var sessionFileNames: [String] {
        [
            "metadata.json",
            "source-transcript.txt",
            "display-transcript.txt",
            "segments.jsonl",
            "draft.srt",
            "source.srt",
            "display.srt",
            "input-audio.caf"
        ]
    }
}

private enum OperatorWorkspace: String, CaseIterable, Identifiable {
    case live
    case style
    case glossary
    case logs
    case models
    case translation
    case audio
    case output

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .style: "Style"
        case .glossary: "Glossary"
        case .logs: "Logs"
        case .models: "Models"
        case .translation: "Translation"
        case .audio: "Audio"
        case .output: "Output"
        }
    }

    var systemImage: String {
        switch self {
        case .live: "captions.bubble"
        case .style: "textformat.size"
        case .glossary: "list.bullet.rectangle"
        case .logs: "folder"
        case .models: "cpu"
        case .translation: "arrow.left.arrow.right"
        case .audio: "waveform"
        case .output: "display"
        }
    }
}

private struct GlossaryEntry: Identifiable {
    let input: String
    let output: String

    var id: String {
        "\(input)=>\(output)"
    }
}

private struct ControlPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

private struct AudioMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.18))

                RoundedRectangle(cornerRadius: 4)
                    .fill(levelColor)
                    .frame(width: max(4, proxy.size.width * level))
            }
        }
        .frame(height: 10)
    }

    private var levelColor: Color {
        switch level {
        case 0.78...:
            .red
        case 0.58...:
            .yellow
        default:
            .green
        }
    }
}
