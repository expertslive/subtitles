import SwiftUI

struct OperatorView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            WorkspaceSidebar(selection: $state.selectedWorkspace)
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
