import SwiftUI

struct LiveWorkspace: View {
    @Environment(AppState.self) private var state

    var body: some View {
        GeometryReader { proxy in
            let useColumns = proxy.size.width >= 720
            if useColumns {
                let chromePadding = 36.0
                let interPanelSpacing = 18.0
                let currentCaptionHeight = 230.0
                let previewHeight = max(
                    220.0,
                    min(390.0, proxy.size.height - chromePadding - interPanelSpacing - currentCaptionHeight)
                )

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        PreviewPanel(maxHeight: previewHeight)
                            .frame(maxWidth: .infinity)
                            .frame(height: previewHeight)
                        currentTranscript
                            .frame(height: currentCaptionHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    historyPanel
                        .frame(width: min(380, max(300, proxy.size.width * 0.3)))
                        .frame(maxHeight: .infinity)
                }
                .padding(18)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
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

    private var historyPanel: some View {
        WorkspaceSection(title: "History") {
            CaptionHistoryList(history: state.history)
        }
    }
}
