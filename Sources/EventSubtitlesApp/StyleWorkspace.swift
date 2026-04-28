import EventSubtitlesCore
import SwiftUI

struct StyleWorkspace: View {
    @EnvironmentObject private var state: AppState
    @State private var showSafeArea = true

    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            previewBand
            Divider()
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                    typographySection
                    layoutSection
                    colorSection
                    displayFlowSection
                    presetsSection
                        .gridCellColumns(2)
                }
                .padding(18)
            }
        }
        .navigationTitle("Style")
    }

    private var previewBand: some View {
        GeometryReader { proxy in
            let height = min(260, max(180, proxy.size.height))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Output preview")
                        .font(.headline)
                    Spacer()
                    Toggle("Show safe area", isOn: $showSafeArea)
                        .toggleStyle(.checkbox)
                    Text("16:9 - \(backgroundModeLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    Color.black
                    SubtitleOutputView()
                        .environmentObject(state)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .padding(.vertical, 8)

                    if showSafeArea {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                Color.white.opacity(0.55),
                                style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                            )
                            .padding(CGFloat(state.safeMargin / 3))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(18)
        }
        .frame(height: 312)
    }

    private var typographySection: some View {
        WorkspaceSection(title: "Typography") {
            LabeledContent("Font") {
                Picker("Font", selection: Binding(
                    get: { state.fontName },
                    set: {
                        state.fontName = $0
                        state.saveSettings()
                    }
                )) {
                    ForEach(["Helvetica Neue", "Arial", "Avenir Next", "Menlo"], id: \.self) { fontName in
                        Text(fontName).tag(fontName)
                    }
                }
                .labelsHidden()
            }

            SliderRow(
                title: "Font size",
                value: Binding(
                    get: { state.fontSize },
                    set: {
                        state.fontSize = $0
                        state.saveSettings()
                    }
                ),
                range: 18...120,
                step: 1,
                unit: "pt"
            )

            SliderRow(
                title: "Line width",
                value: Binding(
                    get: { Double(state.targetCharactersPerLine) },
                    set: {
                        state.targetCharactersPerLine = Int($0)
                        state.saveSettings()
                    }
                ),
                range: 12...60,
                step: 1,
                unit: "chars"
            )
        }
    }

    private var layoutSection: some View {
        WorkspaceSection(title: "Layout") {
            Picker("Lines", selection: Binding(
                get: { state.maxLines },
                set: {
                    state.maxLines = $0
                    state.saveSettings()
                }
            )) {
                Text("2").tag(2)
                Text("3").tag(3)
            }
            .pickerStyle(.segmented)

            Picker("Position", selection: Binding(
                get: { state.captionPosition },
                set: {
                    state.captionPosition = $0
                    state.saveSettings()
                }
            )) {
                ForEach(CaptionVerticalPosition.allCases) { position in
                    Text(position.label).tag(position)
                }
            }
            .pickerStyle(.segmented)

            SliderRow(
                title: "Safe margin",
                value: Binding(
                    get: { state.safeMargin },
                    set: {
                        state.safeMargin = $0
                        state.saveSettings()
                    }
                ),
                range: 28...180,
                step: 1,
                unit: "pt"
            )

            SliderRow(
                title: "Line spacing",
                value: Binding(
                    get: { state.lineSpacing },
                    set: {
                        state.lineSpacing = $0
                        state.saveSettings()
                    }
                ),
                range: 0...28,
                step: 1,
                unit: "pt"
            )

            FinePositionControls()
        }
    }

    private var colorSection: some View {
        WorkspaceSection(title: "Color and shadow") {
            HStack(spacing: 18) {
                ColorPicker("Text", selection: Binding(
                    get: { state.foregroundColor },
                    set: {
                        state.foregroundColor = $0
                        state.saveSettings()
                    }
                ))
                ColorPicker("Background", selection: Binding(
                    get: { state.backgroundColor },
                    set: {
                        state.backgroundColor = $0
                        state.saveSettings()
                    }
                ))
            }

            Toggle("Text shadow", isOn: Binding(
                get: { state.shadowEnabled },
                set: {
                    state.shadowEnabled = $0
                    state.saveSettings()
                }
            ))

            SliderRow(
                title: "Shadow",
                value: Binding(
                    get: { state.shadowRadius },
                    set: {
                        state.shadowRadius = $0
                        state.saveSettings()
                    }
                ),
                range: 0...18,
                step: 1,
                unit: "pt"
            )
        }
    }

    private var displayFlowSection: some View {
        WorkspaceSection(title: "Display flow") {
            Picker(
                "Mode",
                selection: Binding(
                    get: { state.captionDisplayMode },
                    set: { state.setCaptionDisplayMode($0) }
                )
            ) {
                ForEach(CaptionDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Text(state.captionDisplayMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(
                "Stability",
                selection: Binding(
                    get: { state.captionStabilityLevel },
                    set: { state.setCaptionStabilityLevel($0) }
                )
            ) {
                ForEach(CaptionStabilityLevel.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)

            SliderRow(title: "Commit delay", value: Binding(
                get: { state.captionCommitDelay },
                set: {
                    state.captionCommitDelay = $0
                    state.saveSettings()
                }
            ), range: 0.3...2.0, step: 0.1, unit: "s", fractionLength: 1)

            SliderRow(title: "Minimum hold", value: Binding(
                get: { state.captionMinimumHold },
                set: {
                    state.captionMinimumHold = $0
                    state.saveSettings()
                }
            ), range: 0.8...3.0, step: 0.1, unit: "s", fractionLength: 1)

            SliderRow(title: "Max latency", value: Binding(
                get: { state.captionMaximumLatency },
                set: {
                    state.captionMaximumLatency = $0
                    state.saveSettings()
                }
            ), range: 1.5...5.0, step: 0.1, unit: "s", fractionLength: 1)

            Stepper(
                "Hidden unstable words: \(state.captionUnstableWordCount)",
                value: Binding(
                    get: { state.captionUnstableWordCount },
                    set: {
                        state.captionUnstableWordCount = $0
                        state.saveSettings()
                    }
                ),
                in: 0...6,
                step: 1
            )
        }
    }

    private var presetsSection: some View {
        WorkspaceSection(title: "Presets") {
            HStack {
                presetButton("Chroma green", systemImage: "wand.and.stars", selected: isChromaPreset) {
                    state.useChromaGreen()
                    state.foregroundColor = .white
                    state.shadowEnabled = true
                    state.captionPosition = .bottom
                    state.saveSettings()
                }

                presetButton("Black", systemImage: "rectangle.fill", selected: isBlackPreset) {
                    state.useBlackBackground()
                    state.foregroundColor = .white
                    state.shadowEnabled = false
                    state.captionPosition = .bottom
                    state.saveSettings()
                }

                presetButton("High contrast", systemImage: "circle.lefthalf.filled", selected: isHighContrastPreset) {
                    state.foregroundColor = .yellow
                    state.useBlackBackground()
                    state.shadowEnabled = false
                    state.fontSize = 78
                    state.saveSettings()
                }

                presetButton("Large venue", systemImage: "textformat.size", selected: isLargeVenuePreset) {
                    state.foregroundColor = .white
                    state.useBlackBackground()
                    state.shadowEnabled = false
                    state.fontSize = 96
                    state.maxLines = 2
                    state.saveSettings()
                }
            }
        }
    }

    private func presetButton(
        _ title: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
    }

    private var backgroundModeLabel: String {
        if isChromaPreset {
            return "chroma green"
        }
        if isBlackPreset || isHighContrastPreset || isLargeVenuePreset {
            return "black"
        }
        return "custom"
    }

    private var isChromaPreset: Bool {
        state.backgroundColor.description.contains("0.82")
    }

    private var isBlackPreset: Bool {
        state.backgroundColor == .black && state.foregroundColor == .white && !state.shadowEnabled && state.fontSize < 90
    }

    private var isHighContrastPreset: Bool {
        state.backgroundColor == .black && state.foregroundColor == .yellow
    }

    private var isLargeVenuePreset: Bool {
        state.backgroundColor == .black && state.fontSize >= 90
    }
}
