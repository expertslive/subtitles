import AppKit
import SwiftUI

@main
struct EventSubtitlesApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Subtitles") {
            OperatorView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Subtitles") {
                    showAboutPanel()
                }
            }

            CommandMenu("Session") {
                Button("Start") {
                    appState.start()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.isRunning)

                Button("Stop") {
                    appState.stop()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!appState.isRunning)
            }

            CommandMenu("Workspace") {
                ForEach(OperatorWorkspace.allCases) { workspace in
                    Button(workspace.title) {
                        appState.selectedWorkspace = workspace
                    }
                    .keyboardShortcut(workspace.keyboardShortcut, modifiers: .command)
                }
            }

            CommandMenu("Output") {
                Button("Show output window") {
                    appState.showOutputWindow()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Fill external display") {
                    appState.fillExternalDisplay()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Restore output window") {
                    appState.restoreOutputWindow()
                }
            }
        }
    }

    private func showAboutPanel() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.2.2"
        let build = info?["CFBundleVersion"] as? String ?? "4"
        let credits = NSAttributedString(
            string: """
            Offline live subtitles and Dutch/English translation for events.
            Powered by local WhisperKit on Apple Silicon.

            Session logs stay local: transcripts, SRT, JSONL, glossary, and audio.
            """,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            ]
        )

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Subtitles",
            .applicationVersion: version,
            .version: "Build \(build)",
            .credits: credits
        ])
    }
}
