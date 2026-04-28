import SwiftUI

struct ModelsWorkspace: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        GeometryReader { proxy in
            let useColumns = proxy.size.width >= 820
            let readinessWidth = min(370, max(310, proxy.size.width * 0.34))

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
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle("Models")
    }

    private var modelSideColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            offlineReadinessPanel
            modelPreparationPanel
            modelResourcesPanel
        }
    }

    private var modelSetupPanel: some View {
        WorkspaceSection(title: "WhisperKit model") {
            modelControls
        }
    }

    private var offlineReadinessPanel: some View {
        WorkspaceSection(title: "Offline readiness") {
            LabeledContent("Engine", value: state.transcriptionEngine.label)
            LabeledContent("Model", value: state.whisperModelName)
            LabeledContent("Status", value: state.modelStatus)
            LabeledContent("Running", value: state.isRunning ? "Yes" : "No")
        }
    }

    private var modelPreparationPanel: some View {
        WorkspaceSection(title: "Prepare model") {
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
        WorkspaceSection(title: "Resources") {
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
            Picker("Whisper model", selection: Binding(
                get: { state.whisperModelName },
                set: {
                    state.whisperModelName = $0
                    state.saveSettings()
                }
            )) {
                Text("Large v3 626 MB").tag("large-v3-v20240930_626MB")
                Text("Large v3 turbo 632 MB").tag("large-v3-v20240930_turbo_632MB")
                Text("Distil large v3 594 MB").tag("distil-large-v3_594MB")
                Text("Small").tag("small")
                Text("Base").tag("base")
                Text("Tiny").tag("tiny")
            }
            .disabled(state.isRunning || state.isPreparingModel)

            TextField("Model name", text: Binding(
                get: { state.whisperModelName },
                set: {
                    state.whisperModelName = $0
                    state.saveSettings()
                }
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(state.isRunning || state.isPreparingModel)

            Button {
                state.prepareWhisperKitModel()
            } label: {
                Label(
                    state.isPreparingModel ? "Preparing" : "Prepare offline model",
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
}
