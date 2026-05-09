import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    private var isTerminatingAfterSessionStop = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // If a session is running, do NOT terminate when the operator window closes —
        // the chroma output window may still be live for the audience.
        guard let state else { return true }
        return !state.isRunning && !state.isStarting
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTerminatingAfterSessionStop {
            return .terminateNow
        }

        guard let state, state.isRunning || state.isStarting else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "End the live session?"
        alert.informativeText = "A subtitle session is currently running. Quitting will stop transcription and audio recording."
        alert.addButton(withTitle: "End Session and Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }

        Task { @MainActor [weak self] in
            await state.stop()
            self?.isTerminatingAfterSessionStop = true
            sender.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        state?.flushSettingsImmediately()
    }
}
