import EventSubtitlesCore
import SwiftUI

struct OperatorView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            controls
                .frame(width: 410)

            Divider()

            liveWorkspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sessionControls
                .layoutPriority(2)
            outputControls
                .layoutPriority(1)

            inspectorTabs
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var inspectorTabs: some View {
        TabView {
            ScrollView {
                styleControls
                    .padding(10)
            }
            .tabItem {
                Label("Style", systemImage: "textformat.size")
            }

            ScrollView {
                glossaryControls
                    .padding(10)
            }
            .tabItem {
                Label("Glossary", systemImage: "list.bullet.rectangle")
            }

            ScrollView {
                logControls
                    .padding(10)
            }
            .tabItem {
                Label("Log", systemImage: "folder")
            }

            ScrollView {
                modelControls
                    .padding(10)
            }
            .tabItem {
                Label("Model", systemImage: "cpu")
            }

            ScrollView {
                translationControls
                    .padding(10)
            }
            .tabItem {
                Label("Translate", systemImage: "arrow.left.arrow.right")
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var sessionControls: some View {
        ControlPanel(title: "Session") {
            TextField("Session name", text: $state.sessionName)
                .textFieldStyle(.roundedBorder)

            Picker("Engine", selection: $state.transcriptionEngine) {
                ForEach(TranscriptionEngineChoice.allCases) { engine in
                    Text(engine.label).tag(engine)
                }
            }
            .disabled(state.isRunning)

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

            HStack(spacing: 8) {
                Text(state.engineStatus)
                    .lineLimit(1)

                Spacer()

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

    private var outputControls: some View {
        ControlPanel(title: "Output") {
            Button {
                state.showOutputWindow()
            } label: {
                Label("Show Output Window", systemImage: "rectangle.on.rectangle")
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

            HStack {
                Button("Chroma Green") {
                    state.useChromaGreen()
                }

                Button("Black") {
                    state.useBlackBackground()
                }
            }
        }
    }

    private var styleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Font") {
                Picker("Font", selection: $state.fontName) {
                    ForEach(["Helvetica Neue", "Arial", "Avenir Next", "Menlo"], id: \.self) { fontName in
                        Text(fontName).tag(fontName)
                    }
                }
                .labelsHidden()
            }

            SliderRow(title: "Font size", value: $state.fontSize, range: 34...120, step: 1)
            SliderRow(title: "Line width", value: Binding(
                get: { Double(state.targetCharactersPerLine) },
                set: { state.targetCharactersPerLine = Int($0) }
            ), range: 28...60, step: 1)
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

                Toggle("Text shadow", isOn: $state.shadowEnabled)
            }

            Picker("Position", selection: $state.captionPosition) {
                ForEach(CaptionVerticalPosition.allCases) { position in
                    Text(position.label).tag(position)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 18) {
                ColorPicker("Text", selection: $state.foregroundColor)
                ColorPicker("Background", selection: $state.backgroundColor)
            }

            SliderRow(title: "Shadow", value: $state.shadowRadius, range: 0...18, step: 1)

            Button {
                state.saveSettings()
            } label: {
                Label("Save Settings", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var glossaryControls: some View {
        TextEditor(text: $state.glossaryText)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 280)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25))
            }
    }

    private var logControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Status", value: state.sessionLogStatus)
            LabeledContent("Segments", value: "\(state.sessionSegmentCount)")

            if let path = state.sessionDirectoryPath {
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)

                Button {
                    state.openSessionFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("metadata.json")
                Text("source-transcript.txt")
                Text("display-transcript.txt")
                Text("segments.jsonl")
                Text("draft.srt")
                Text("source.srt")
                Text("display.srt")
                Text("input-audio.caf")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
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

            Text("Prepare the model before the event while online. Once cached, the WhisperKit engine can run without network access.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var translationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Text("{source} and {target} are replaced with en/nl. Caption text is sent on stdin; stdout must contain the translated text.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var liveWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Output Preview")
                    .font(.headline)

                SubtitleOutputView()
                    .environmentObject(state)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxHeight: 430)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25))
                    }
            }

            HStack(alignment: .top, spacing: 18) {
                currentTranscript
                history
            }
            .frame(maxHeight: .infinity)
        }
        .padding(22)
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

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline)

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
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
