import SwiftUI

@main
struct EventSubtitlesApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("EventSubtitles") {
            OperatorView()
                .environmentObject(appState)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .commands {
            CommandMenu("Output") {
                Button("Show Output Window") {
                    appState.showOutputWindow()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Fill External Display") {
                    appState.fillExternalDisplay()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Restore Output Window") {
                    appState.restoreOutputWindow()
                }
            }
        }
    }
}
