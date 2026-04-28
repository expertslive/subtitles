import SwiftUI

struct AudioWorkspace: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    WorkspaceSection(title: "Input") {
                        audioInputRow

                        Button {
                            state.refreshAudioInputDevice()
                        } label: {
                            Label("Refresh input", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
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
        .navigationTitle("Audio")
    }

    private var audioInputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            Text(state.audioInputDescription)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var dbText: String {
        let db = 20 * log10(max(state.audioLevel, 0.0001))
        return "\(db.formatted(.number.precision(.fractionLength(0)))) dB"
    }
}
