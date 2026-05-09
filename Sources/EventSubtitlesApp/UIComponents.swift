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

    @State private var displayedLevel: Double = 0
    @State private var displayedPeak: Double = 0
    @State private var lastUpdate: Date = .distantPast

    var body: some View {
        HStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                MeterCanvas(
                    target: clamped(level),
                    displayedLevel: displayedLevel,
                    displayedPeak: displayedPeak,
                    showsTicks: showsTicks
                )
                .onChange(of: context.date) { _, newDate in
                    updateEnvelopes(now: newDate)
                }
            }
            .frame(height: 10)

            if showsDB {
                Text(dbText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(displayedLevel > 0.92 ? .red : .secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(clamped(level) * 100)) percent, \(dbText)")
    }

    private func clamped(_ v: Double) -> Double { min(max(v, 0), 1) }

    private func updateEnvelopes(now: Date) {
        let dt = max(0, min(0.1, now.timeIntervalSince(lastUpdate)))
        lastUpdate = now
        let target = clamped(level)

        // RMS: low-pass smooth, time constant ~80ms.
        let rmsAlpha = 1 - exp(-dt / 0.08)
        displayedLevel = displayedLevel + (target - displayedLevel) * rmsAlpha

        // Peak: instant attack, slow release.
        if target >= displayedPeak {
            displayedPeak = target
        } else if peakHold {
            // Decay ~0.6 unit per second.
            let releasePerSec = 0.6
            displayedPeak = max(target, displayedPeak - releasePerSec * dt)
        } else {
            displayedPeak = displayedLevel
        }
    }

    private var dbText: String {
        let db = 20 * log10(max(displayedLevel, 0.0001))
        return "\(db.formatted(.number.precision(.fractionLength(0)))) dB"
    }
}

private struct MeterCanvas: View {
    let target: Double
    let displayedLevel: Double
    let displayedPeak: Double
    let showsTicks: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.18))

                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [.green, .yellow, .orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(3, proxy.size.width * displayedLevel))

                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2)
                    .offset(x: max(0, proxy.size.width * displayedPeak - 1))

                if displayedLevel > 0.92 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.red)
                        .offset(x: proxy.size.width - 14, y: -2)
                        .accessibilityHidden(true)
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
    @Environment(AppState.self) private var state

    var title = "Output preview"
    var maxHeight: CGFloat = 430

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            GeometryReader { proxy in
                SubtitleOutputView(ignoresSafeArea: false, animatesCaptionChanges: false)
                    .environment(state)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
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
    @Environment(AppState.self) private var state

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
