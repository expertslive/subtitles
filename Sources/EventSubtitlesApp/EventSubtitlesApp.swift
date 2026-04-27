import AppKit
import SwiftUI

@main
struct EventSubtitlesApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Subtitles") {
            OperatorView()
                .environmentObject(appState)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Subtitles") {
                    showAboutPanel()
                }
            }

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
