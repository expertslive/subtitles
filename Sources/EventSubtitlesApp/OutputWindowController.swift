import AppKit
import SwiftUI

@MainActor
final class OutputWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        if window == nil {
            createWindow()
        }

        restoreWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func fillExternalDisplay() {
        if window == nil {
            createWindow()
        }

        guard let window else {
            return
        }

        let screen = NSScreen.screens.first { $0 != NSScreen.main } ?? NSScreen.main
        guard let screen else {
            restoreWindow()
            return
        }

        window.styleMask = [.borderless]
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func restoreWindow() {
        if window == nil {
            createWindow()
        }

        guard let window else {
            return
        }

        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.level = .normal
        window.collectionBehavior = [.managed, .fullScreenPrimary]

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 120, y: 120, width: 1280, height: 720)
        let size = NSSize(width: min(1280, screen.width * 0.82), height: min(720, screen.height * 0.82))
        let origin = NSPoint(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func createWindow() {
        let hostingController = NSHostingController(
            rootView: SubtitleOutputView()
                .environmentObject(state)
        )

        let newWindow = NSWindow(
            contentRect: NSRect(x: 160, y: 160, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Subtitle Output"
        newWindow.contentViewController = hostingController
        newWindow.delegate = self
        newWindow.isReleasedWhenClosed = false
        window = newWindow
    }
}
