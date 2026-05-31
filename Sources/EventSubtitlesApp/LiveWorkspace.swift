import SwiftUI

struct LiveWorkspace: View {
    @Environment(AppState.self) private var state

    var body: some View {
        GeometryReader { proxy in
            let useColumns = proxy.size.width >= 720
            if useColumns {
                let chromePadding = 36.0
                let interPanelSpacing = 18.0
                let currentCaptionHeight = 260.0
                let statusHeight = 92.0
                let previewHeight = max(
                    220.0,
                    min(390.0, proxy.size.height - chromePadding - interPanelSpacing * 2 - currentCaptionHeight - statusHeight)
                )

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        eventStatusPanel
                            .frame(height: statusHeight)
                        PreviewPanel(maxHeight: previewHeight)
                            .frame(maxWidth: .infinity)
                            .frame(height: previewHeight)
                        currentTranscript
                            .frame(height: currentCaptionHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 18) {
                        preflightPanel
                            .frame(maxHeight: min(360, proxy.size.height * 0.38))
                        historyPanel
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: min(430, max(340, proxy.size.width * 0.32)))
                    .frame(maxHeight: .infinity)
                }
                .padding(18)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        eventStatusPanel
                        preflightPanel
                        PreviewPanel(maxHeight: 390)
                        currentTranscript
                        historyPanel
                    }
                    .padding(18)
                }
            }
        }
    }

    private var currentTranscript: some View {
        WorkspaceSection(title: "Current caption") {
            liveControls

            Divider()

            HStack {
                Text(state.captionDisplayMode.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(state.captionDisplayLatencyText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Draft")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(state.draftEvent?.sourceText ?? "No transcript yet.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Public")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(state.publicCaptionText.isEmpty ? "No public caption yet." : state.publicCaptionText)
                            .font(.title3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !state.stableCaptionQueueText.isEmpty {
                        Divider()
                        Text("Queued stable text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(state.stableCaptionQueueText)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: 150)
        }
    }

    private var eventStatusPanel: some View {
        WorkspaceSection(title: "Event mode") {
            HStack(alignment: .top, spacing: 14) {
                statusBlock("Preflight", value: state.preflightSummaryText, status: state.preflightSummaryStatus)
                statusBlock("Audio", value: "\(Int(state.audioLevel * 100))% - \(state.audioInputDescription)", status: audioStatus)
                statusBlock("Recording", value: state.isRunning || state.isStarting ? state.sessionElapsedText : state.sessionLogStatus, status: state.isRunning || state.isStarting ? .pass : .warning)
                statusBlock("Output", value: state.outputStatusText, status: state.outputWindowVisible ? .pass : .warning)
            }
        }
    }

    private func statusBlock(_ title: String, value: String, status: OperationalStatus) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var audioStatus: OperationalStatus {
        if state.audioInputSelectionStatus == "No input device available" {
            return .fail
        }
        if state.audioInputSelectionStatus.contains("unavailable") || state.audioLevel < 0.05 {
            return .warning
        }
        return .pass
    }

    private var liveControls: some View {
        HStack(spacing: 10) {
            Button {
                if state.isRunning || state.isStarting {
                    Task { await state.stop() }
                } else {
                    state.start()
                }
            } label: {
                Label(
                    state.isRunning || state.isStarting ? "Stop" : "Start",
                    systemImage: state.isRunning || state.isStarting ? "stop.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                state.panicBlank()
            } label: {
                Label("Panic blank", systemImage: "eye.slash.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.orange)

            Button {
                state.clearCaptions()
            } label: {
                Label("Clear captions", systemImage: "text.badge.xmark")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var preflightPanel: some View {
        PreflightSummaryCard(checks: state.preflightChecks)
    }

    private var historyPanel: some View {
        WorkspaceSection(title: "History") {
            CaptionHistoryList(history: state.history)
        }
    }
}
