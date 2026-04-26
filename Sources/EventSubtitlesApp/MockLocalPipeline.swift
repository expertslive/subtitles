import Foundation
import EventSubtitlesCore

final class MockLocalTranscriber: SpeechTranscribing, @unchecked Sendable {
    private var timer: Timer?
    private var pendingFinalTimer: Timer?
    private var index = 0
    private var configuration = SpeechEngineConfiguration()

    private let script = [
        "Welcome to the conference. Today we are testing real time subtitles for developers.",
        "The next demo shows a Kubernetes deployment with PostgreSQL and OAuth.",
        "Latency matters because people need enough time to read each subtitle.",
        "We can switch between Dutch and English without sending audio to the cloud.",
        "Voor Nederlandstalige sprekers willen we technische termen zoals Kubernetes goed herkennen.",
        "Deze MacBook Air gebruikt Apple Silicon voor lokale transcriptie en vertaling."
    ]

    func start(
        configuration: SpeechEngineConfiguration,
        onResult: @escaping @Sendable (SpeechRecognitionResult) -> Void
    ) async throws {
        self.configuration = configuration
        stopTimers()
        emit(onResult: onResult)
        timer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: true) { [weak self] _ in
            self?.emit(onResult: onResult)
        }
    }

    func stop() async {
        stopTimers()
    }

    func stopNow() {
        stopTimers()
    }

    private func stopTimers() {
        timer?.invalidate()
        timer = nil
        pendingFinalTimer?.invalidate()
        pendingFinalTimer = nil
    }

    private func emit(onResult: @escaping @Sendable (SpeechRecognitionResult) -> Void) {
        let text = script[index % script.count]
        index += 1

        let words = text.split(separator: " ").map(String.init)
        let partial = words.prefix(max(4, words.count / 2)).joined(separator: " ")
        onResult(result(text: partial, isFinal: false))

        pendingFinalTimer?.invalidate()
        pendingFinalTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }
            onResult(self.result(text: text, isFinal: true))
        }
    }

    private func result(text: String, isFinal: Bool) -> SpeechRecognitionResult {
        SpeechRecognitionResult(
            text: text,
            language: configuration.sourceLanguage,
            isFinal: isFinal,
            startedAt: nil,
            endedAt: Date()
        )
    }
}
