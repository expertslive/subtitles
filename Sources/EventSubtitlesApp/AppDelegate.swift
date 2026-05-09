import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // If a session is running, do NOT terminate when the operator window closes —
        // the chroma output window may still be live for the audience.
        !(state?.isRunning ?? false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state, state.isRunning else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "End the live session?"
        alert.informativeText = "A subtitle session is currently running. Quitting will stop transcription and audio recording."
        alert.addButton(withTitle: "End Session and Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        state?.flushSettingsImmediately()
    }
}
