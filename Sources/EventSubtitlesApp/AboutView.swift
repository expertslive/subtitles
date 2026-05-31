import EventSubtitlesCore
import SwiftUI

struct AboutView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            updateSection
            installSection
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 620)
        .frame(minHeight: 390)
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
                    Button("Open Release Page") {
                        state.openLatestReleasePage()
                    }
                }
            }
        }
    }

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install Update")
                .font(.headline)
            Text("When you are ready to update, paste this command in Terminal. The app will not run installers automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                Text(AppUpdateConstants.installCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Button("Copy") {
                    state.copyInstallCommandToClipboard()
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
