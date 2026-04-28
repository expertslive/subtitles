import AppKit
import SwiftUI

struct OutputWorkspace: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedDisplay = 0
    @State private var outputMode: OutputWorkspaceMode = .window

    var body: some View {
        GeometryReader { proxy in
            let useColumns = proxy.size.width >= 900
            let controlsWidth = min(390, max(340, proxy.size.width * 0.32))

            ScrollView {
                Group {
                    if useColumns {
                        HStack(alignment: .top, spacing: 18) {
                            outputSetupColumn
                                .frame(width: controlsWidth)

                            outputPreviewColumn
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            outputPreviewColumn
                            outputSetupColumn
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle("Output")
    }

    private var outputSetupColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            outputWindowPanel
            outputBackgroundPanel
        }
    }

    private var outputPreviewColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            PreviewPanel(maxHeight: 430)
            outputSignalPanel
        }
    }

    private var outputWindowPanel: some View {
        WorkspaceSection(title: "Output window") {
            Picker("Display", selection: $selectedDisplay) {
                Text("Built-in display").tag(0)
            }
            // TODO: enumerate NSScreen.screens here when explicit display selection is implemented.
            .disabled(NSScreen.screens.count <= 1)

            Picker("Mode", selection: $outputMode) {
                Text("Window").tag(OutputWorkspaceMode.window)
                Text("Filled").tag(OutputWorkspaceMode.filled)
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Apply") {
                    switch outputMode {
                    case .window:
                        state.showOutputWindow()
                    case .filled:
                        state.fillExternalDisplay()
                    }
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    Button {
                        state.restoreOutputWindow()
                    } label: {
                        Label("Restore window", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private var outputBackgroundPanel: some View {
        WorkspaceSection(title: "Background") {
            HStack(alignment: .top, spacing: 12) {
                BackgroundSwatch(color: state.backgroundColor)

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        state.useChromaGreen()
                        state.saveSettings()
                    } label: {
                        Label("Chroma green", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        state.useBlackBackground()
                        state.saveSettings()
                    } label: {
                        Label("Black", systemImage: "rectangle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var outputSignalPanel: some View {
        WorkspaceSection(title: "Signal") {
            HStack(alignment: .top, spacing: 18) {
                LabeledContent("Position", value: state.captionPosition.label)
                LabeledContent("Lines", value: "\(state.maxLines)")
                LabeledContent("Safe margin", value: "\(Int(state.safeMargin)) pt")
            }
        }
    }
}

private enum OutputWorkspaceMode: Hashable {
    case window
    case filled
}
