import SwiftUI

struct WorkspaceDetail: View {
    @EnvironmentObject private var state: AppState
    let workspace: OperatorWorkspace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: Binding(
            get: { workspace },
            set: { state.selectedWorkspace = $0 }
        )) {
            LiveWorkspace().tag(OperatorWorkspace.live)
            StyleWorkspace().tag(OperatorWorkspace.style)
            GlossaryWorkspace().tag(OperatorWorkspace.glossary)
            TranslationWorkspace().tag(OperatorWorkspace.translation)
            AudioWorkspace().tag(OperatorWorkspace.audio)
            ModelsWorkspace().tag(OperatorWorkspace.models)
            OutputWorkspace().tag(OperatorWorkspace.output)
            LogsWorkspace().tag(OperatorWorkspace.logs)
        }
        .tabViewStyle(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(workspace.title)
        .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: workspace)
    }
}
