import SwiftUI

struct NowPanel: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            draftCard
            publicCard
            recentCard
                .frame(maxHeight: .infinity)
            manualCaptionCard
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var draftCard: some View {
        NowCard(
            title: "Draft (ASR)",
            accessory: state.captionUnstableWordCount > 0
                ? AnyView(StatusPill(text: "\(state.captionUnstableWordCount) hidden", tint: .orange))
                : nil
        ) {
            Text(state.draftEvent?.sourceText ?? "No transcript yet.")
                .font(.body)
                .italic()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var publicCard: some View {
        NowCard(
            title: "Public",
            accessory: state.publicCaptionText.isEmpty
                ? nil
                : AnyView(StatusPill(text: "On screen", tint: .green))
        ) {
            Text(state.publicCaptionText.isEmpty ? "No public caption yet." : state.publicCaptionText)
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recentCard: some View {
        NowCard(title: "Recent") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(state.history.suffix(8).reversed())) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.createdAt, style: .time)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(event.displayText)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                    }

                    if state.history.isEmpty {
                        Text("No captions yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var manualCaptionCard: some View {
        NowCard(title: "Manual caption") {
            HStack {
                TextField("Send manual caption...", text: $state.manualCaption)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        state.pushManualCaption()
                    }

                Button("Send") {
                    state.pushManualCaption()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}
