import EventSubtitlesCore
import Foundation

struct CommandLineTranslator: Sendable {
    func translate(
        text: String,
        mode: ProcessingMode,
        executablePath: String,
        argumentTemplate: String
    ) async throws -> String {
        let trimmedPath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw CommandLineTranslatorError.missingExecutable
        }

        let arguments = parseArguments(argumentTemplate)
            .map { replaceTokens(in: $0, mode: mode) }

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: trimmedPath)
            process.arguments = arguments

            let input = Pipe()
            let output = Pipe()
            let errorOutput = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errorOutput

            try process.run()
            input.fileHandleForWriting.write(Data(text.utf8))
            try input.fileHandleForWriting.close()

            process.waitUntilExit()

            let stdout = output.fileHandleForReading.readDataToEndOfFile()
            let stderr = errorOutput.fileHandleForReading.readDataToEndOfFile()
            let translated = String(data: stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus != 0 {
                let message = String(data: stderr, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw CommandLineTranslatorError.commandFailed(message ?? "exit \(process.terminationStatus)")
            }

            guard !translated.isEmpty else {
                throw CommandLineTranslatorError.emptyOutput
            }

            return translated
        }.value
    }

    private func replaceTokens(in argument: String, mode: ProcessingMode) -> String {
        argument
            .replacingOccurrences(of: "{source}", with: sourceLanguageCode(for: mode))
            .replacingOccurrences(of: "{target}", with: targetLanguageCode(for: mode))
    }

    private func sourceLanguageCode(for mode: ProcessingMode) -> String {
        switch mode {
        case .subtitlesOnly:
            "auto"
        case .englishToDutch:
            "en"
        case .dutchToEnglish:
            "nl"
        }
    }

    private func targetLanguageCode(for mode: ProcessingMode) -> String {
        switch mode {
        case .subtitlesOnly:
            "auto"
        case .englishToDutch:
            "nl"
        case .dutchToEnglish:
            "en"
        }
    }

    private func parseArguments(_ template: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?

        for character in template {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                } else {
                    current.append(character)
                }
            } else if character.isWhitespace, quote == nil {
                if !current.isEmpty {
                    arguments.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            arguments.append(current)
        }

        return arguments
    }
}

enum CommandLineTranslatorError: LocalizedError {
    case missingExecutable
    case commandFailed(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            "No local translation command path is configured."
        case .commandFailed(let message):
            "Local translation command failed: \(message)"
        case .emptyOutput:
            "Local translation command returned no text."
        }
    }
}
