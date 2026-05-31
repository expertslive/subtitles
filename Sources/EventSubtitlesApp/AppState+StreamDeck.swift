import EventSubtitlesRemoteControl
import Foundation

@MainActor
extension AppState {
    func streamDeckStatusSnapshot(now: Date = Date()) -> StreamDeckStatusSnapshot {
        let sessionState: StreamDeckSessionState
        if isStarting {
            sessionState = .starting
        } else if isRunning {
            sessionState = .running
        } else if didFailToStartSession {
            sessionState = .error
        } else {
            sessionState = .stopped
        }

        let displayState: StreamDeckDisplayState
        if outputWindowFilled {
            displayState = .filled
        } else if outputWindowVisible {
            displayState = .window
        } else {
            displayState = .hidden
        }

        return StreamDeckStatusSnapshot(
            sessionState: sessionState,
            elapsedText: sessionElapsedText,
            displayState: displayState,
            outputState: outputBlanked ? .blanked : .live,
            captionState: StreamDeckStatusPolicy.captionState(
                text: publicCaptionText,
                lastActivityAt: lastCaptionActivityAt,
                now: now
            ),
            audioState: StreamDeckStatusPolicy.audioState(
                isRunning: isRunning,
                isDemo: transcriptionEngine == .simulator,
                isSelectedInputAvailable: isSelectedAudioInputAvailable,
                hasAudioFailure: hasAudioCaptureFailure,
                audioLevel: audioLevel,
                lastAudibleInputAt: lastAudibleInputAt,
                sessionStartedAt: sessionStartedAt,
                now: now
            ),
            errorSummary: StreamDeckStatusPolicy.errorSummary(errorMessage),
            displayedSegmentCount: sessionSegmentCount
        )
    }

    func handleStreamDeckCommand(_ request: StreamDeckCommandRequest) async -> StreamDeckCommandResult {
        switch request.command {
        case .startSession:
            guard !isRunning, !isStarting else {
                return StreamDeckCommandResult(id: request.id, accepted: false, reason: .invalidState)
            }
            start()
        case .stopSession:
            guard isRunning || isStarting else {
                return StreamDeckCommandResult(id: request.id, accepted: false, reason: .invalidState)
            }
            await stop()
        case .panicBlank:
            panicBlank()
        case .unblankOutput:
            unblankOutput()
        case .clearCaptions:
            clearCaptions()
        case .fillExternalDisplay:
            guard fillExternalDisplay() else {
                return StreamDeckCommandResult(id: request.id, accepted: false, reason: .noExternalDisplay)
            }
        case .restoreOutputWindow:
            restoreOutputWindow()
        }

        return StreamDeckCommandResult(id: request.id, accepted: true)
    }
}
