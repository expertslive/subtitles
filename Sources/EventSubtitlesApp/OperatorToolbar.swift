import EventSubtitlesCore
import SwiftUI

extension OperatorView {
    @ToolbarContentBuilder
    var operatorToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 12) {
                ToolbarSessionField(text: Binding(
                    get: { state.sessionName },
                    set: {
                        state.sessionName = $0
                        state.saveSettings()
                    }
                ))

                ToolbarMenuPicker(
                    "Capture",
                    selection: Binding(
                        get: { state.transcriptionEngine },
                        set: {
                            state.transcriptionEngine = $0
                            state.saveSettings()
                        }
                    ),
                    width: 150,
                    isDisabled: state.isRunning
                ) {
                    ForEach(TranscriptionEngineChoice.allCases) { engine in
                        Text(engine.label).tag(engine)
                    }
                }

                ToolbarMenuPicker(
                    "Source",
                    selection: Binding(
                        get: { state.sourceLanguage },
                        set: {
                            state.sourceLanguage = $0
                            state.saveSettings()
                        }
                    ),
                    width: 110
                ) {
                    ForEach(SourceLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }

                ToolbarMenuPicker(
                    "Mode",
                    selection: Binding(
                        get: { state.mode },
                        set: {
                            state.mode = $0
                            state.saveSettings()
                        }
                    ),
                    width: 145
                ) {
                    ForEach(ProcessingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                ToolbarAudioMeter(level: state.audioLevel) {
                    state.selectedWorkspace = .audio
                }
                .frame(width: 210, height: 28)
            }
            .fixedSize(horizontal: true, vertical: false)
        }

        ToolbarItem(placement: .confirmationAction) {
            HStack(spacing: 10) {
                if state.isRunning {
                    ToolbarRoundButton(
                        title: "Stop",
                        systemImage: "stop.fill",
                        tint: .red,
                        action: state.stop
                    )
                    .keyboardShortcut(".", modifiers: .command)

                    ToolbarRecordingStatus(
                        elapsedText: state.sessionElapsedText,
                        segmentCount: state.sessionSegmentCount
                    )
                } else {
                    ToolbarRoundButton(
                        title: "Start",
                        systemImage: "play.fill",
                        tint: .green,
                        action: state.start
                    )
                    .keyboardShortcut("r", modifiers: .command)
                }

                HStack(spacing: 8) {
                    ToolbarIconButton(
                        title: "Show output window",
                        systemImage: "rectangle.on.rectangle",
                        action: state.showOutputWindow
                    )

                    ToolbarIconButton(
                        title: "Fill external display",
                        systemImage: "arrow.up.left.and.arrow.down.right",
                        action: state.fillExternalDisplay
                    )

                    ToolbarIconButton(
                        title: "Restore output window",
                        systemImage: "arrow.down.right.and.arrow.up.left",
                        action: state.restoreOutputWindow
                    )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct ToolbarSessionField: View {
    @Binding var text: String

    var body: some View {
        TextField("Session", text: $text)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .default).weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(width: 120, height: 28)
            .background(toolbarControlBackground)
            .overlay(toolbarControlBorder)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .help("Session name")
    }
}

private struct ToolbarMenuPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    let width: CGFloat
    var isDisabled = false
    let content: Content

    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        width: CGFloat,
        isDisabled: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._selection = selection
        self.width = width
        self.isDisabled = isDisabled
        self.content = content()
    }

    var body: some View {
        Picker(title, selection: $selection) {
            content
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: width, height: 28)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(isDisabled)
        .help(title)
    }
}

private struct ToolbarRoundButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(0.72)))
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct ToolbarIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.secondary.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct ToolbarRecordingStatus: View {
    let elapsedText: String
    let segmentCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
            Text("\(elapsedText) · \(segmentCount)")
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.red)
        .padding(.horizontal, 9)
        .frame(width: 118, height: 28)
        .background(Capsule().fill(Color.red.opacity(0.12)))
        .help("Recording session status")
    }
}

private var toolbarControlBackground: some View {
    RoundedRectangle(cornerRadius: 7)
        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
}

private var toolbarControlBorder: some View {
    RoundedRectangle(cornerRadius: 7)
        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
}
