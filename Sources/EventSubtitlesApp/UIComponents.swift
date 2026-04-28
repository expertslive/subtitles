import AppKit
import EventSubtitlesCore
import SwiftUI

struct WorkspaceSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } label: {
            Text(title)
                .font(.headline)
        }
        .groupBoxStyle(.automatic)
    }
}

struct NowCard<Content: View>: View {
    let title: String
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(title: String, accessory: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let accessory {
                    accessory
                }
            }

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StatusPill: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit: String?
    var fractionLength = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedValue)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }

    private var formattedValue: String {
        let formatted = value.formatted(.number.precision(.fractionLength(fractionLength)))
        guard let unit else {
            return formatted
        }
        return "\(formatted) \(unit)"
    }
}

struct AudioLevelMeter: View {
    let level: Double
    var showsDB = true
    var showsTicks = true
    var peakHold = false

    @State private var peakLevel = 0.0

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.18))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(levelColor)
                        .frame(width: max(3, proxy.size.width * clampedLevel))

                    if peakHold {
                        Rectangle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 2)
                            .offset(x: max(0, proxy.size.width * peakLevel - 1))
                    }

                    if showsTicks {
                        ForEach([-18.0, -12.0, -6.0, 0.0], id: \.self) { tick in
                            Rectangle()
                                .fill(Color.white.opacity(tick == 0 ? 0.5 : 0.22))
                                .frame(width: 1)
                                .offset(x: proxy.size.width * tickPosition(tick))
                        }
                    }
                }
            }
            .frame(height: 10)

            if showsDB {
                Text(dbText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(level > 0.92 ? .red : .secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .onAppear {
            peakLevel = clampedLevel
        }
        .onChange(of: level) { _, newValue in
            let newLevel = min(max(newValue, 0), 1)
            if newLevel >= peakLevel {
                peakLevel = newLevel
            }
            guard peakHold else {
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.easeOut(duration: 0.2)) {
                    peakLevel = min(max(level, 0), 1)
                }
            }
        }
    }

    private var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    private var dbText: String {
        let db = 20 * log10(max(level, 0.0001))
        return "\(db.formatted(.number.precision(.fractionLength(0)))) dB"
    }

    private var levelColor: Color {
        switch level {
        case 0.92...:
            .red
        case 0.72...:
            .orange
        case 0.58...:
            .yellow
        default:
            .green
        }
    }

    private func tickPosition(_ db: Double) -> Double {
        min(max((db + 60) / 60, 0), 1)
    }
}

struct ToolbarAudioMeter: View {
    let level: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                AudioLevelMeter(level: level, showsDB: true, showsTicks: true, peakHold: false)
                    .frame(width: 140, height: 22)
            }
            .frame(width: 170, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Audio workspace")
    }
}

struct PreviewPanel: View {
    @EnvironmentObject private var state: AppState

    var title = "Output preview"
    var maxHeight: CGFloat = 430

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            SubtitleOutputView()
                .environmentObject(state)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25))
                }
        }
    }
}

struct CaptionHistoryList: View {
    let history: [TranscriptEvent]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(history) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.displayText)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(event.createdAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }

                if history.isEmpty {
                    Text("No captions yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BackgroundSwatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: 96, height: 96)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3))
            }
    }
}

struct FinePositionControls: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fine position")
                Spacer()
                Text("X \(Int(state.captionOffsetX)) pt / Y \(Int(state.captionOffsetY)) pt")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                VStack(spacing: 6) {
                    positionNudgeButton(systemImage: "arrow.up", help: "Move captions up") {
                        state.captionOffsetY -= 8
                        state.saveSettings()
                    }

                    HStack(spacing: 6) {
                        positionNudgeButton(systemImage: "arrow.left", help: "Move captions left") {
                            state.captionOffsetX -= 8
                            state.saveSettings()
                        }

                        Button {
                            state.captionOffsetX = 0
                            state.captionOffsetY = 0
                            state.saveSettings()
                        } label: {
                            Image(systemName: "scope")
                                .frame(width: 28, height: 28)
                        }
                        .help("Reset caption offset")

                        positionNudgeButton(systemImage: "arrow.right", help: "Move captions right") {
                            state.captionOffsetX += 8
                            state.saveSettings()
                        }
                    }

                    positionNudgeButton(systemImage: "arrow.down", help: "Move captions down") {
                        state.captionOffsetY += 8
                        state.saveSettings()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Stepper("Horizontal", value: Binding(
                        get: { state.captionOffsetX },
                        set: {
                            state.captionOffsetX = $0
                            state.saveSettings()
                        }
                    ), in: -400...400, step: 1)
                    Stepper("Vertical", value: Binding(
                        get: { state.captionOffsetY },
                        set: {
                            state.captionOffsetY = $0
                            state.saveSettings()
                        }
                    ), in: -300...300, step: 1)
                }
            }
        }
    }

    private func positionNudgeButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
        }
        .help(help)
    }
}
