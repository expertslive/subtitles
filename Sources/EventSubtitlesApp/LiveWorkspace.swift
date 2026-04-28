import SwiftUI

struct LiveWorkspace: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        GeometryReader { proxy in
            let useColumns = proxy.size.width >= 900
            if useColumns {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        PreviewPanel(maxHeight: 430)
                        currentTranscript
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    historyPanel
                        .frame(width: min(380, max(300, proxy.size.width * 0.3)))
                }
                .padding(18)
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
        .navigationTitle("Live")
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Draft")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(state.draftEvent?.sourceText ?? "No transcript yet.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Public")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(state.publicCaptionText.isEmpty ? "No public caption yet." : state.publicCaptionText)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !state.stableCaptionQueueText.isEmpty {
                Divider()
                Text("Queued stable text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(state.stableCaptionQueueText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var historyPanel: some View {
        WorkspaceSection(title: "History") {
            CaptionHistoryList(history: state.history)
        }
    }
}
