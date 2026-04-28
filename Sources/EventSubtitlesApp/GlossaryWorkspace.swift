import EventSubtitlesCore
import SwiftUI

struct GlossaryWorkspace: View {
    @EnvironmentObject private var state: AppState

    @State private var glossarySearch = ""
    @State private var glossaryTestInput = "We deploy kubernetes with postgres and oauth on apple silicon."
    @State private var glossaryNewInput = ""
    @State private var glossaryNewOutput = ""
    @State private var glossaryEditingID: Int?
    @State private var glossaryEditingInput = ""
    @State private var glossaryEditingOutput = ""
    @State private var glossaryBulkEditorExpanded = false

    var body: some View {
        GeometryReader { proxy in
            let useColumns = proxy.size.width >= 980
            let toolsWidth = min(420, max(340, proxy.size.width * 0.34))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    glossaryHeader

                    if useColumns {
                        HStack(alignment: .top, spacing: 18) {
                            glossaryEditorPanel
                                .frame(maxWidth: .infinity)

                            glossaryToolsPanel
                                .frame(width: toolsWidth)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            glossaryEditorPanel
                            glossaryToolsPanel
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle("Glossary")
    }

    private var glossaryHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                TextField("Search glossary", text: $glossarySearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)

                Spacer()

                glossaryFileActions
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Search glossary", text: $glossarySearch)
                    .textFieldStyle(.roundedBorder)

                glossaryFileActions
            }
        }
    }

    private var glossaryFileActions: some View {
        HStack(spacing: 8) {
            Button {
                state.importGlossary()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down.on.square")
            }

            Menu {
                Button {
                    state.exportGlossaryJSON()
                } label: {
                    Label("JSON", systemImage: "curlybraces")
                }

                Button {
                    state.exportGlossaryCSV()
                } label: {
                    Label("CSV", systemImage: "tablecells")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var glossaryEditorPanel: some View {
        WorkspaceSection(title: "Glossary terms") {
            glossaryAddTermControls

            Divider()

            glossaryEditableTable

            Divider()

            DisclosureGroup("Advanced bulk edit", isExpanded: $glossaryBulkEditorExpanded) {
                TextEditor(text: Binding(
                    get: { state.glossaryText },
                    set: {
                        state.glossaryText = $0
                        state.saveSettings()
                    }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                }
            }
        }
    }

    private var glossaryToolsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceSection(title: "Quality") {
                glossaryQualityPanel
            }

            WorkspaceSection(title: "Alias groups") {
                glossaryAliasPanel
            }

            WorkspaceSection(title: "Test phrase") {
                glossaryTestPanel
            }

            WorkspaceSection(title: "Session suggestions") {
                glossarySuggestionsPanel
            }
        }
    }

    private var glossaryAddTermControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Heard as")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Show as")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("")
                    .frame(width: 88)
            }

            HStack(spacing: 10) {
                TextField("postgres", text: $glossaryNewInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                TextField("PostgreSQL", text: $glossaryNewOutput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Button {
                    addGlossaryEntry()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(glossaryNewInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .frame(width: 88, alignment: .trailing)
            }
        }
    }

    private var glossaryEditableTable: some View {
        Table(filteredGlossaryEntries) {
            TableColumn("Heard as") { entry in
                editableField(entry: entry, value: .input)
            }

            TableColumn("Show as") { entry in
                editableField(entry: entry, value: .output)
            }

            TableColumn("Actions") { entry in
                actionButtons(entry)
            }
            .width(90)
        }
        .frame(minHeight: 360)
    }

    private func editableField(entry: GlossaryEntry, value: GlossaryEditableValue) -> some View {
        Group {
            if glossaryEditingID == entry.id {
                TextField(
                    value == .input ? "Heard as" : "Show as",
                    text: value == .input ? $glossaryEditingInput : $glossaryEditingOutput
                )
                .textFieldStyle(.roundedBorder)
            } else {
                Text(value == .input ? entry.input : entry.output)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .font(.system(.caption, design: .monospaced))
    }

    private func actionButtons(_ entry: GlossaryEntry) -> some View {
        HStack(spacing: 4) {
            if glossaryEditingID == entry.id {
                Button {
                    commitGlossaryEdit(entry)
                } label: {
                    Image(systemName: "checkmark")
                }
                .disabled(glossaryEditingInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Save term")

                Button {
                    cancelGlossaryEdit()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Cancel")
            } else {
                Button {
                    startGlossaryEdit(entry)
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit term")

                Button {
                    deleteGlossaryEntry(entry)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete term")
            }
        }
        .buttonStyle(.borderless)
    }

    private var glossaryQualityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("\(glossaryEntries.count) terms", systemImage: "list.bullet")
                Label("\(glossaryAliasGroups.count) alias groups", systemImage: "link")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            if glossaryValidationIssues.isEmpty {
                Label("No glossary conflicts", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(glossaryValidationIssues) { issue in
                        Label(issue.message, systemImage: issue.systemImage)
                            .foregroundStyle(issue.tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.caption)
            }
        }
    }

    private var glossaryAliasPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if glossaryAliasGroups.isEmpty {
                Text("No aliases yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(glossaryAliasGroups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.output)
                                    .font(.caption.weight(.semibold))

                                Text(group.inputs.joined(separator: ", "))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
        }
    }

    private var glossaryTestPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Test phrase", text: $glossaryTestInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            Divider()

            Text(glossaryTestOutput)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var glossarySuggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if glossarySuggestions.isEmpty {
                Text("No session suggestions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(glossarySuggestions) { suggestion in
                    HStack {
                        Text(suggestion.term)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Text("\(suggestion.count)x")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            glossaryNewInput = suggestion.term
                            glossaryNewOutput = suggestion.term
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.borderless)
                        .help("Use as new glossary term")
                    }
                }
            }
        }
    }

    private var glossaryRawLines: [String] {
        guard !state.glossaryText.isEmpty else {
            return []
        }
        return state.glossaryText.components(separatedBy: .newlines)
    }

    private var glossaryEntries: [GlossaryEntry] {
        glossaryRawLines.enumerated().compactMap { index, rawLine in
            parseGlossaryLine(rawLine, lineIndex: index)
        }
    }

    private var filteredGlossaryEntries: [GlossaryEntry] {
        let search = glossarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else {
            return glossaryEntries
        }

        return glossaryEntries.filter { entry in
            entry.input.localizedCaseInsensitiveContains(search) ||
                entry.output.localizedCaseInsensitiveContains(search)
        }
    }

    private var glossaryAliasGroups: [GlossaryAliasGroup] {
        Dictionary(grouping: glossaryEntries, by: { normalizedGlossaryKey($0.output) })
            .compactMap { _, entries in
                let inputs = Array(Set(entries.map(\.input))).sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
                guard inputs.count > 1, let output = entries.first?.output else {
                    return nil
                }
                return GlossaryAliasGroup(output: output, inputs: inputs)
            }
            .sorted { $0.output.localizedCaseInsensitiveCompare($1.output) == .orderedAscending }
    }

    private var glossaryValidationIssues: [GlossaryValidationIssue] {
        var issues: [GlossaryValidationIssue] = []

        for (index, rawLine) in glossaryRawLines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.range(of: "=>") else {
                continue
            }

            let input = line[..<separator.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let output = line[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty || output.isEmpty {
                issues.append(
                    GlossaryValidationIssue(
                        severity: .warning,
                        message: "Line \(index + 1) has an empty side"
                    )
                )
            }
        }

        let groupedByInput = Dictionary(grouping: glossaryEntries) {
            normalizedGlossaryKey($0.input)
        }

        for (_, entries) in groupedByInput {
            let outputKeys = Set(entries.map { normalizedGlossaryKey($0.output) })
            if outputKeys.count > 1, let input = entries.first?.input {
                let outputs = Array(Set(entries.map(\.output))).sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
                issues.append(
                    GlossaryValidationIssue(
                        severity: .warning,
                        message: "\(input) maps to \(outputs.joined(separator: " / "))"
                    )
                )
                continue
            }

            let pairKeys = entries.map {
                "\(normalizedGlossaryKey($0.input))=>\(normalizedGlossaryKey($0.output))"
            }
            if Set(pairKeys).count < pairKeys.count, let input = entries.first?.input {
                issues.append(
                    GlossaryValidationIssue(
                        severity: .info,
                        message: "\(input) appears more than once"
                    )
                )
            }
        }

        return issues
    }

    private var glossarySuggestions: [GlossarySuggestion] {
        let knownTerms = Set(glossaryEntries.flatMap {
            [normalizedGlossaryKey($0.input), normalizedGlossaryKey($0.output)]
        })
        let transcriptText = ([state.draftEvent?.sourceText, state.currentEvent?.sourceText, state.publicCaptionText]
            .compactMap { $0 } + state.history.flatMap { [$0.sourceText, $0.displayText] })
            .joined(separator: " ")
        let tokens = transcriptText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                let key = normalizedGlossaryKey(token)
                return token.count >= 5 &&
                    !key.isEmpty &&
                    !knownTerms.contains(key) &&
                    !commonGlossarySuggestionWords.contains(key)
            }

        let examples = Dictionary(tokens.map { (normalizedGlossaryKey($0), $0) }, uniquingKeysWith: { first, _ in first })
        let frequencies = Dictionary(grouping: tokens, by: normalizedGlossaryKey).mapValues(\.count)

        return frequencies
            .compactMap { key, count in
                guard let term = examples[key] else {
                    return nil
                }
                return GlossarySuggestion(term: term, count: count)
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
                }
                return $0.count > $1.count
            }
            .prefix(8)
            .map { $0 }
    }

    private var commonGlossarySuggestionWords: Set<String> {
        [
            "about", "after", "again", "alleen", "already", "andere", "because", "before",
            "comes", "could", "daarom", "deze", "doing", "english", "event", "going",
            "heeft", "hello", "komen", "later", "maybe", "moeten", "onder", "other",
            "right", "screen", "session", "shown", "staat", "terms", "there", "these",
            "thing", "think", "through", "vandaag", "wacht", "waarom", "words", "would"
        ]
    }

    private var glossaryTestOutput: String {
        GlossaryCorrector(rawGlossary: state.glossaryText).apply(to: glossaryTestInput)
    }

    private func parseGlossaryLine(_ rawLine: String, lineIndex: Int) -> GlossaryEntry? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else {
            return nil
        }

        if let separator = line.range(of: "=>") {
            let input = line[..<separator.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let output = line[separator.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !input.isEmpty, !output.isEmpty else {
                return nil
            }

            return GlossaryEntry(lineIndex: lineIndex, input: String(input), output: String(output))
        }

        return GlossaryEntry(lineIndex: lineIndex, input: line, output: line)
    }

    private func addGlossaryEntry() {
        guard let line = formattedGlossaryLine(input: glossaryNewInput, output: glossaryNewOutput) else {
            return
        }

        var lines = glossaryRawLines
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
        lines.append(line)
        writeGlossaryLines(lines)
        glossaryNewInput = ""
        glossaryNewOutput = ""
    }

    private func startGlossaryEdit(_ entry: GlossaryEntry) {
        glossaryEditingID = entry.id
        glossaryEditingInput = entry.input
        glossaryEditingOutput = entry.output
    }

    private func commitGlossaryEdit(_ entry: GlossaryEntry) {
        guard let line = formattedGlossaryLine(input: glossaryEditingInput, output: glossaryEditingOutput) else {
            return
        }

        var lines = glossaryRawLines
        guard lines.indices.contains(entry.lineIndex) else {
            return
        }
        lines[entry.lineIndex] = line
        writeGlossaryLines(lines)
        cancelGlossaryEdit()
    }

    private func cancelGlossaryEdit() {
        glossaryEditingID = nil
        glossaryEditingInput = ""
        glossaryEditingOutput = ""
    }

    private func deleteGlossaryEntry(_ entry: GlossaryEntry) {
        var lines = glossaryRawLines
        guard lines.indices.contains(entry.lineIndex) else {
            return
        }
        lines.remove(at: entry.lineIndex)
        writeGlossaryLines(lines)
        cancelGlossaryEdit()
    }

    private func formattedGlossaryLine(input: String, output: String) -> String? {
        let cleanedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedInput.isEmpty else {
            return nil
        }

        return "\(cleanedInput) => \(cleanedOutput.isEmpty ? cleanedInput : cleanedOutput)"
    }

    private func writeGlossaryLines(_ lines: [String]) {
        state.glossaryText = lines.joined(separator: "\n")
        state.saveSettings()
    }

    private func normalizedGlossaryKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

private enum GlossaryEditableValue {
    case input
    case output
}

private struct GlossaryEntry: Identifiable {
    let lineIndex: Int
    let input: String
    let output: String

    var id: Int { lineIndex }
}

private struct GlossaryAliasGroup: Identifiable {
    let output: String
    let inputs: [String]

    var id: String { output }
}

private struct GlossarySuggestion: Identifiable {
    let term: String
    let count: Int

    var id: String { term }
}

private struct GlossaryValidationIssue: Identifiable {
    let severity: GlossaryValidationSeverity
    let message: String

    var id: String { "\(severity)-\(message)" }

    var systemImage: String {
        switch severity {
        case .warning: "exclamationmark.triangle"
        case .info: "info.circle"
        }
    }

    var tint: Color {
        switch severity {
        case .warning: .orange
        case .info: .secondary
        }
    }
}

private enum GlossaryValidationSeverity {
    case warning
    case info
}
