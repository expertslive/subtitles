import SwiftUI

struct AudioWorkspace: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    WorkspaceSection(title: "Input") {
                        audioInputPicker
                        audioInputStatusRow

                        Button {
                            state.useSystemDefaultAudioInput()
                        } label: {
                            Label("Use system default", systemImage: "mic")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(state.selectedAudioInputDeviceID == nil || state.isRunning)
                    }
                    .frame(width: 360)

                    WorkspaceSection(title: "Level") {
                        AudioLevelMeter(level: state.audioLevel, showsDB: true, showsTicks: true, peakHold: true)
                            .frame(height: 24)

                        LabeledContent("Level", value: "\(Int(state.audioLevel * 100))%")
                        LabeledContent("Current", value: dbText)
                        LabeledContent("Clipping", value: state.audioLevel > 0.92 ? "Yes" : "No")
                    }
                    .frame(width: 300)
                }

                WorkspaceSection(title: "Power") {
                    Toggle(
                        "Keep Mac awake during session",
                        isOn: Binding(
                            get: { state.keepMacAwakeDuringSession },
                            set: { state.setKeepMacAwakeDuringSession($0) }
                        )
                    )

                    Label(
                        state.sleepPreventionStatus,
                        systemImage: state.keepMacAwakeDuringSession ? "moon.zzz.slash" : "moon.zzz"
                    )
                    .foregroundStyle(state.sleepPreventionStatus == "Awake failed" ? .orange : .secondary)
                }
                .frame(maxWidth: 680)

                WorkspaceSection(title: "Recording") {
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
                .frame(maxWidth: 680)

                WorkspaceSection(title: "Test recording") {
                    Button {
                        state.errorMessage = "Test recording not implemented yet."
                    } label: {
                        Label("Run test recording", systemImage: "record.circle")
                    }
                }
                .frame(maxWidth: 680)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var audioInputPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio interface")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker(
                    "Audio interface",
                    selection: Binding<String?>(
                        get: { state.selectedAudioInputDeviceID },
                        set: { state.setSelectedAudioInputDeviceID($0) }
                    )
                ) {
                    Text("System default").tag(String?.none)

                    ForEach(state.audioInputDevices, id: \.id) { device in
                        Text(device.displayName).tag(Optional(device.id))
                    }

                    if let selectedDeviceID = state.selectedAudioInputDeviceID,
                       !state.audioInputDevices.contains(where: { $0.id == selectedDeviceID }) {
                        Text("Unavailable interface").tag(Optional(selectedDeviceID))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .disabled(state.isRunning)

                Button {
                    state.refreshAudioInputDevice()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 18)
                }
                .help("Refresh input devices")
            }
        }
    }

    private var audioInputStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.audioInputDescription)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(state.audioInputSelectionStatus)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        state.audioInputSelectionStatus.contains("unavailable") ? .orange : .secondary
    }

    private var dbText: String {
        let db = 20 * log10(max(state.audioLevel, 0.0001))
        return "\(db.formatted(.number.precision(.fractionLength(0)))) dB"
    }
}
