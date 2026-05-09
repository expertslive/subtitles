@preconcurrency import AppKit
import SwiftUI

@MainActor
final class OutputWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var window: NSWindow?
    private var screenObserver: NSObjectProtocol?
    private var isFilled = false

    init(state: AppState) {
        self.state = state
        super.init()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenChange()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
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

        let target = preferredOutputScreen() ?? NSScreen.main
        guard let target else {
            restoreWindow()
            return
        }

        window.styleMask = [.borderless]
        window.level = .screenSaver
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.isMovableByWindowBackground = false
        window.canHide = false
        window.acceptsMouseMovedEvents = false
        window.hasShadow = false
        window.colorSpace = .sRGB
        window.setFrame(target.frame, display: true)

        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableAppleMenu,
            .disableProcessSwitching,
            .disableHideApplication
        ]

        isFilled = true
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

        NSApp.presentationOptions = []
        isFilled = false

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
        NSApp.presentationOptions = []
        isFilled = false
        window = nil
    }

    private func handleScreenChange() {
        guard isFilled, let window else {
            return
        }

        if let target = preferredOutputScreen() {
            window.setFrame(target.frame, display: true)
        } else {
            restoreWindow()
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func preferredOutputScreen() -> NSScreen? {
        NSScreen.screens.first { $0 != NSScreen.main }
    }

    private func createWindow() {
        let hostingController = NSHostingController(
            rootView: SubtitleOutputView(governsLayout: true)
                .environmentObject(state)
        )

        let newWindow = NSWindow(
            contentRect: NSRect(x: 160, y: 160, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Subtitle Output"
        newWindow.setFrameAutosaveName("SubtitleOutput")
        newWindow.isRestorable = true
        newWindow.contentViewController = hostingController
        newWindow.delegate = self
        newWindow.isReleasedWhenClosed = false
        newWindow.colorSpace = .sRGB
        window = newWindow
    }
}
