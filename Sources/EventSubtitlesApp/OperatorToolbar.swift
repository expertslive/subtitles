import EventSubtitlesCore
import SwiftUI

extension OperatorView {
    @ToolbarContentBuilder
    var operatorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            TextField("Session", text: Binding(
                get: { state.sessionName },
                set: {
                    state.sessionName = $0
                    state.saveSettings()
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 140)

            Picker("Capture", selection: Binding(
                get: { state.transcriptionEngine },
                set: {
                    state.transcriptionEngine = $0
                    state.saveSettings()
                }
            )) {
                ForEach(TranscriptionEngineChoice.allCases) { engine in
                    Text(engine.label).tag(engine)
                }
            }
            .pickerStyle(.menu)
            .disabled(state.isRunning)

            Picker("Source", selection: Binding(
                get: { state.sourceLanguage },
                set: {
                    state.sourceLanguage = $0
                    state.saveSettings()
                }
            )) {
                ForEach(SourceLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .pickerStyle(.menu)

            Picker("Mode", selection: Binding(
                get: { state.mode },
                set: {
                    state.mode = $0
                    state.saveSettings()
                }
            )) {
                ForEach(ProcessingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)

            ToolbarAudioMeter(level: state.audioLevel) {
                state.selectedWorkspace = .audio
            }
            .frame(width: 220)
        }

        ToolbarItemGroup(placement: .confirmationAction) {
            if state.isRunning {
                Button {
                    state.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .keyboardShortcut(".", modifiers: .command)

                Label(
                    "\(state.sessionElapsedText) · \(state.sessionSegmentCount) segs",
                    systemImage: "record.circle.fill"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.red)
            } else {
                Button {
                    state.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .keyboardShortcut("r", modifiers: .command)
            }

            ControlGroup {
                Button {
                    state.showOutputWindow()
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                }
                .help("Show output window")

                Button {
                    state.fillExternalDisplay()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fill external display")

                Button {
                    state.restoreOutputWindow()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .help("Restore output window")
            }
        }
    }
}
