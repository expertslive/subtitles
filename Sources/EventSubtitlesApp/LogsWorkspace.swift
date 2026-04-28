import AppKit
import SwiftUI

struct LogsWorkspace: View {
    @EnvironmentObject private var state: AppState

    private let sessionFileNames = [
        "metadata.json",
        "source-transcript.txt",
        "display-transcript.txt",
        "segments.jsonl",
        "draft.srt",
        "source.srt",
        "display.srt",
        "input-audio.caf"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    WorkspaceSection(title: "Current session") {
                        LabeledContent("Status", value: state.sessionLogStatus)
                        LabeledContent("Segments", value: "\(state.sessionSegmentCount)")
                        LabeledContent("Elapsed", value: state.sessionElapsedText)
                    }
                    .frame(width: 300)

                    WorkspaceSection(title: "Session folder") {
                        if let path = state.sessionDirectoryPath {
                            Text(path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                                .textSelection(.enabled)

                            HStack {
                                Button {
                                    openSessionFolder(path)
                                } label: {
                                    Label("Open folder", systemImage: "folder")
                                        .frame(maxWidth: .infinity)
                                }

                                Button {
                                    revealSessionFolder(path)
                                } label: {
                                    Label("Reveal in Finder", systemImage: "finder")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        } else {
                            Text("No active session folder")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: 18) {
                    WorkspaceSection(title: "Files") {
                        logFileList
                    }
                    .frame(width: 300)

                    WorkspaceSection(title: "Captured captions") {
                        CaptionHistoryList(history: state.history)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Logs")
    }

    private var logFileList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sessionFileNames, id: \.self) { fileName in
                Label(fileName, systemImage: "doc.text")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openSessionFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func revealSessionFolder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
