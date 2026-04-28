import SwiftUI

struct WorkspaceDetail: View {
    let workspace: OperatorWorkspace

    var body: some View {
        Group {
            switch workspace {
            case .live:
                LiveWorkspace()
            case .style:
                StyleWorkspace()
            case .glossary:
                GlossaryWorkspace()
            case .translation:
                TranslationWorkspace()
            case .audio:
                AudioWorkspace()
            case .models:
                ModelsWorkspace()
            case .output:
                OutputWorkspace()
            case .logs:
                LogsWorkspace()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
