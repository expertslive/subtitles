import EventSubtitlesCore
import SwiftUI

struct TranslationWorkspace: View {
    @EnvironmentObject private var state: AppState
    @State private var translationTestInput = "Welcome developers, this conference session is about cloud latency and security."

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 18) {
                WorkspaceSection(title: "Translation") {
                    translationControls
                }
                .frame(width: 440)

                WorkspaceSection(title: "Test translation") {
                    translationTestPanel
                }
                .frame(maxWidth: .infinity)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Translation")
    }

    private var translationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: Binding(
                get: { state.mode },
                set: {
                    state.mode = $0
                    state.saveSettings()
                }
            )) {
                ForEach(ProcessingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("Engine", selection: Binding(
                get: { state.translationEngine },
                set: {
                    state.translationEngine = $0
                    state.saveSettings()
                }
            )) {
                ForEach(TranslationEngineChoice.allCases) { engine in
                    Text(engine.label).tag(engine)
                }
            }

            TextField("Executable path", text: Binding(
                get: { state.translationCommandPath },
                set: {
                    state.translationCommandPath = $0
                    state.saveSettings()
                }
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(state.translationEngine != .localCommand)

            TextField("Arguments", text: Binding(
                get: { state.translationCommandArguments },
                set: {
                    state.translationCommandArguments = $0
                    state.saveSettings()
                }
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(state.translationEngine != .localCommand)
        }
    }

    private var translationTestPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Test caption", text: $translationTestInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(translationPreviewSource)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Display")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(translationPreviewDisplay)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var translationPreviewSource: String {
        GlossaryCorrector(rawGlossary: state.glossaryText).apply(to: translationTestInput)
    }

    private var translationPreviewDisplay: String {
        let translated = RuleBasedTranslator().translate(translationPreviewSource, mode: state.mode)
        return GlossaryCorrector(rawGlossary: state.glossaryText).apply(to: translated)
    }
}
