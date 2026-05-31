import SwiftUI

struct OperatorView: View {
    @Environment(AppState.self) var state

    var body: some View {
        @Bindable var bindableState = state
        VStack(spacing: 0) {
            if let errorMessage = state.errorMessage {
                ErrorBanner(message: errorMessage) {
                    state.selectedWorkspace = .logs
                } onDismiss: {
                    state.clearError()
                }
            }

            NavigationSplitView {
                WorkspaceSidebar(selection: $bindableState.selectedWorkspace)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            } content: {
                NowPanel()
                    .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 340)
            } detail: {
                WorkspaceDetail(workspace: state.selectedWorkspace)
            }
        }
        .toolbar {
            operatorToolbar
        }
        .navigationTitle("Subtitles")
        .navigationSubtitle(state.sessionName.isEmpty ? "" : state.sessionName)
    }
}

private struct ErrorBanner: View {
    let message: String
    let openLogs: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                openLogs()
            } label: {
                Label("Logs", systemImage: "list.bullet.rectangle")
            }
            .controlSize(.small)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.16))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.orange.opacity(0.35))
                .frame(height: 1)
        }
    }
}
