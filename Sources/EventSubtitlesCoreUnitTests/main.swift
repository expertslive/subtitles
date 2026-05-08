import EventSubtitlesCore
import Foundation

@discardableResult
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) -> Bool {
    guard actual == expected else {
        fputs("FAIL: \(message). Expected \(expected), got \(actual)\n", stderr)
        return false
    }
    return true
}

func testSystemDefaultModeUsesDefaultDevice() -> Bool {
    let defaultDevice = AudioInputSelectionDevice(id: "built-in", name: "MacBook Pro Microphone")
    let result = AudioInputSelectionResolver.resolve(
        selectedDeviceID: nil,
        devices: [
            defaultDevice,
            AudioInputSelectionDevice(id: "scarlett", name: "Scarlett 2i2")
        ],
        defaultDeviceID: "built-in"
    )

    return expectEqual(result.effectiveDeviceID, "built-in", "system default effective device") &&
        expectEqual(result.status, .usingSystemDefault, "system default status")
}

func testAvailableOverrideWinsOverDefaultDevice() -> Bool {
    let result = AudioInputSelectionResolver.resolve(
        selectedDeviceID: "scarlett",
        devices: [
            AudioInputSelectionDevice(id: "built-in", name: "MacBook Pro Microphone"),
            AudioInputSelectionDevice(id: "scarlett", name: "Scarlett 2i2")
        ],
        defaultDeviceID: "built-in"
    )

    return expectEqual(result.effectiveDeviceID, "scarlett", "override effective device") &&
        expectEqual(result.status, .usingOverride, "override status")
}

func testUnavailableOverrideFallsBackToDefaultDevice() -> Bool {
    let result = AudioInputSelectionResolver.resolve(
        selectedDeviceID: "scarlett",
        devices: [
            AudioInputSelectionDevice(id: "built-in", name: "MacBook Pro Microphone")
        ],
        defaultDeviceID: "built-in"
    )

    return expectEqual(result.effectiveDeviceID, "built-in", "unavailable override fallback device") &&
        expectEqual(result.status, .overrideUnavailable, "unavailable override status")
}

func testPromptBuilderIncludesSessionAndGlossaryTerms() -> Bool {
    let prompt = SpeechPromptBuilder.promptText(
        sessionName: "Wortell Summit",
        glossary: """
        kubernetes => Kubernetes
        oauth => OAuth
        # comment
        """
    )
    return expectEqual(
        prompt,
        "Event: Wortell Summit. Vocabulary: kubernetes, oauth.",
        "prompt builder should include session and ignore comments"
    )
}

func testPromptBuilderDropsEmptyParts() -> Bool {
    return expectEqual(
        SpeechPromptBuilder.promptText(sessionName: "", glossary: ""),
        "",
        "empty inputs produce empty prompt"
    ) && expectEqual(
        SpeechPromptBuilder.promptText(sessionName: "  ", glossary: "kubernetes => Kubernetes"),
        "Vocabulary: kubernetes.",
        "blank session name is omitted"
    )
}

func testPromptBuilderTruncatesAtCharacterLimit() -> Bool {
    let bigGlossary = (1...500).map { "term\($0) => Term\($0)" }.joined(separator: "\n")
    let prompt = SpeechPromptBuilder.promptText(sessionName: "Show", glossary: bigGlossary, maxCharacters: 100)
    return expectEqual(prompt.count, 100, "prompt should be truncated to maxCharacters")
}

let tests = [
    ("systemDefaultModeUsesDefaultDevice", testSystemDefaultModeUsesDefaultDevice),
    ("availableOverrideWinsOverDefaultDevice", testAvailableOverrideWinsOverDefaultDevice),
    ("unavailableOverrideFallsBackToDefaultDevice", testUnavailableOverrideFallsBackToDefaultDevice),
    ("promptBuilderIncludesSessionAndGlossaryTerms", testPromptBuilderIncludesSessionAndGlossaryTerms),
    ("promptBuilderDropsEmptyParts", testPromptBuilderDropsEmptyParts),
    ("promptBuilderTruncatesAtCharacterLimit", testPromptBuilderTruncatesAtCharacterLimit)
]

var failed = 0
for (name, test) in tests {
    if test() {
        print("PASS: \(name)")
    } else {
        failed += 1
    }
}

if failed > 0 {
    exit(1)
}
