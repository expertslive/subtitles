import SwiftUI

struct WorkspaceSidebar: View {
    @EnvironmentObject private var state: AppState
    @Binding var selection: OperatorWorkspace

    var body: some View {
        List(selection: $selection) {
            Section("Event") {
                sidebarRow(.live)
                sidebarRow(.style)
                sidebarRow(.glossary)
                sidebarRow(.translation)
            }

            Section("Hardware") {
                sidebarRow(.audio)
                sidebarRow(.models)
                sidebarRow(.output)
            }

            Section("Session") {
                sidebarRow(.logs)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    private func sidebarRow(_ workspace: OperatorWorkspace) -> some View {
        Label(workspace.title, systemImage: workspace.systemImage)
            .tag(workspace)
            .keyboardShortcut(workspace.keyboardShortcut, modifiers: .command)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            LabeledContent("Engine", value: state.transcriptionEngine.label)
            LabeledContent("Model", value: state.whisperModelName)
            LabeledContent {
                Text(state.modelStatus)
                    .foregroundStyle(modelStatusColor)
                    .lineLimit(2)
            } label: {
                Text("Status")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var modelStatusColor: Color {
        state.modelStatus.localizedCaseInsensitiveContains("prepared") ? .green : .secondary
    }
}
