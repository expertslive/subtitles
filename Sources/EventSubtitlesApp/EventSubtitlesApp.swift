import SwiftUI

@main
struct EventSubtitlesApp: App {
    @State private var appState = AppState()
    @State private var aboutWindowController = AboutWindowController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Subtitles") {
            OperatorView()
                .environment(appState)
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear {
                    appDelegate.state = appState
                    appState.checkForUpdatesOnLaunch()
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Subtitles") {
                    aboutWindowController.show(appState: appState)
                }
            }

            CommandMenu("Session") {
                Button("Start") {
                    appState.start()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.isRunning || appState.isStarting)

                Button("Stop") {
                    Task { await appState.stop() }
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!appState.isRunning && !appState.isStarting)

                Divider()

                Button("Panic Blank") {
                    appState.panicBlank()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button(appState.outputBlanked ? "Unblank Output" : "Blank Output") {
                    appState.toggleOutputBlank()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
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

        Settings {
            SettingsView()
                .environment(appState)
                .frame(minWidth: 640, minHeight: 480)
        }
    }
}

private struct SettingsView: View {
    var body: some View {
        TabView {
            StyleWorkspace()
                .tabItem { Label("Style", systemImage: "textformat") }

            AudioWorkspace()
                .tabItem { Label("Audio", systemImage: "waveform") }

            ModelsWorkspace()
                .tabItem { Label("Models", systemImage: "cpu") }

            TranslationWorkspace()
                .tabItem { Label("Translation", systemImage: "arrow.left.arrow.right") }
        }
        .padding(12)
    }
}
