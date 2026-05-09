import SwiftUI

struct OperatorView: View {
    @Environment(AppState.self) var state

    var body: some View {
        @Bindable var bindableState = state
        NavigationSplitView {
            WorkspaceSidebar(selection: $bindableState.selectedWorkspace)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } content: {
            NowPanel()
                .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 340)
        } detail: {
            WorkspaceDetail(workspace: state.selectedWorkspace)
        }
        .toolbar {
            operatorToolbar
        }
        .navigationTitle("Subtitles")
        .navigationSubtitle(state.sessionName.isEmpty ? "" : state.sessionName)
    }
}
