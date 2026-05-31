import EventSubtitlesCore
import SwiftUI

struct AboutView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            updateSection
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 460)
        .frame(minHeight: 300)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subtitles")
                .font(.title)
                .fontWeight(.semibold)
            Text("Version \(state.currentAppVersionText) · Build \(state.currentAppBuildText)")
                .foregroundStyle(.secondary)
            Text("Offline live subtitles and Dutch/English translation for events. Session logs stay local.")
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Updates")
                .font(.headline)
            Text(updateStatusText)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = updateFailureDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Check for Updates") {
                    state.checkForUpdatesManually()
                }
                .disabled(state.updateStatus == .checking)

                if updateAvailable {
                    Button("Copy Install Command") {
                        state.copyInstallCommandToClipboard()
                    }
                    Button("Open Release Page") {
                        state.openLatestReleasePage()
                    }
                }
            }
        }
    }

    private var updateAvailable: Bool {
        if case .available = state.updateStatus {
            return true
        }
        return false
    }

    private var updateFailureDetail: String? {
        if case let .failed(_, reason) = state.updateStatus {
            return reason.displayText
        }
        return nil
    }

    private var updateStatusText: String {
        switch state.updateStatus {
        case .idle:
            return "Update status unknown."
        case .checking:
            return "Checking for updates..."
        case .upToDate:
            return "You are up to date."
        case let .available(_, latestVersion):
            if state.isRunning || state.isStarting {
                return "Update available: \(latestVersion). Update after the current session."
            }
            return "Update available: \(latestVersion)."
        case .failed:
            return "Could not check for updates."
        }
    }
}
