import Foundation

public let streamDeckProtocolVersion = 1

public enum StreamDeckCommand: String, Codable, Equatable, Sendable {
    case startSession
    case stopSession
    case panicBlank
    case unblankOutput
    case clearCaptions
    case fillExternalDisplay
    case restoreOutputWindow
}

public enum StreamDeckRejectionReason: String, Codable, Equatable, Sendable {
    case invalidState
    case noExternalDisplay
    case internalError
}

public struct StreamDeckHello: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let pluginVersion: String

    public init(protocolVersion: Int = streamDeckProtocolVersion, pluginVersion: String) {
        self.protocolVersion = protocolVersion
        self.pluginVersion = pluginVersion
    }
}

public struct StreamDeckCommandRequest: Codable, Equatable, Sendable {
    public let id: String
    public let command: StreamDeckCommand

    public init(id: String, command: StreamDeckCommand) {
        self.id = id
        self.command = command
    }
}

public struct StreamDeckCommandResult: Codable, Equatable, Sendable {
    public let id: String
    public let accepted: Bool
    public let reason: StreamDeckRejectionReason?

    private enum CodingKeys: String, CodingKey {
        case id
        case accepted
        case reason
    }

    fileprivate static func isValid(accepted: Bool, reason: StreamDeckRejectionReason?) -> Bool {
        accepted == (reason == nil)
    }

    public init(id: String, accepted: Bool, reason: StreamDeckRejectionReason? = nil) {
        precondition(
            Self.isValid(accepted: accepted, reason: reason),
            "Accepted command results must not have a rejection reason; rejected results must have one."
        )
        self.id = id
        self.accepted = accepted
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let accepted = try container.decode(Bool.self, forKey: .accepted)
        let reason = try container.decodeIfPresent(StreamDeckRejectionReason.self, forKey: .reason)
        guard Self.isValid(accepted: accepted, reason: reason) else {
            throw DecodingError.dataCorruptedError(
                forKey: .accepted,
                in: container,
                debugDescription: "Accepted command results must not have a rejection reason; rejected results must have one."
            )
        }
        self.id = id
        self.accepted = accepted
        self.reason = reason
    }

    public func encode(to encoder: Encoder) throws {
        precondition(
            Self.isValid(accepted: accepted, reason: reason),
            "Accepted command results must not have a rejection reason; rejected results must have one."
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(accepted, forKey: .accepted)
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}

public enum StreamDeckSessionState: String, Codable, Equatable, Sendable {
    case stopped
    case starting
    case running
    case error
}

public enum StreamDeckDisplayState: String, Codable, Equatable, Sendable {
    case hidden
    case window
    case filled
}

public enum StreamDeckOutputState: String, Codable, Equatable, Sendable {
    case live
    case blanked
}

public enum StreamDeckCaptionState: String, Codable, Equatable, Sendable {
    case clear
    case active
    case idle
}

public enum StreamDeckAudioState: String, Codable, Equatable, Sendable {
    case unknown
    case healthy
    case silent
    case warning
}

public struct StreamDeckStatusSnapshot: Codable, Equatable, Sendable {
    public let sessionState: StreamDeckSessionState
    public let elapsedText: String
    public let displayState: StreamDeckDisplayState
    public let outputState: StreamDeckOutputState
    public let captionState: StreamDeckCaptionState
    public let audioState: StreamDeckAudioState
    public let errorSummary: String?
    public let displayedSegmentCount: Int

    private enum CodingKeys: String, CodingKey {
        case sessionState
        case elapsedText
        case displayState
        case outputState
        case captionState
        case audioState
        case errorSummary
        case displayedSegmentCount
    }

    public init(
        sessionState: StreamDeckSessionState,
        elapsedText: String,
        displayState: StreamDeckDisplayState,
        outputState: StreamDeckOutputState,
        captionState: StreamDeckCaptionState,
        audioState: StreamDeckAudioState,
        errorSummary: String?,
        displayedSegmentCount: Int
    ) {
        self.sessionState = sessionState
        self.elapsedText = elapsedText
        self.displayState = displayState
        self.outputState = outputState
        self.captionState = captionState
        self.audioState = audioState
        self.errorSummary = errorSummary
        self.displayedSegmentCount = displayedSegmentCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.errorSummary) else {
            throw DecodingError.keyNotFound(
                CodingKeys.errorSummary,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Status snapshots must include errorSummary as a string or null."
                )
            )
        }
        sessionState = try container.decode(StreamDeckSessionState.self, forKey: .sessionState)
        elapsedText = try container.decode(String.self, forKey: .elapsedText)
        displayState = try container.decode(StreamDeckDisplayState.self, forKey: .displayState)
        outputState = try container.decode(StreamDeckOutputState.self, forKey: .outputState)
        captionState = try container.decode(StreamDeckCaptionState.self, forKey: .captionState)
        audioState = try container.decode(StreamDeckAudioState.self, forKey: .audioState)
        errorSummary = try container.decodeIfPresent(String.self, forKey: .errorSummary)
        displayedSegmentCount = try container.decode(Int.self, forKey: .displayedSegmentCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionState, forKey: .sessionState)
        try container.encode(elapsedText, forKey: .elapsedText)
        try container.encode(displayState, forKey: .displayState)
        try container.encode(outputState, forKey: .outputState)
        try container.encode(captionState, forKey: .captionState)
        try container.encode(audioState, forKey: .audioState)
        if let errorSummary {
            try container.encode(errorSummary, forKey: .errorSummary)
        } else {
            try container.encodeNil(forKey: .errorSummary)
        }
        try container.encode(displayedSegmentCount, forKey: .displayedSegmentCount)
    }
}

public struct StreamDeckStatusMessage: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let status: StreamDeckStatusSnapshot

    public init(protocolVersion: Int = streamDeckProtocolVersion, status: StreamDeckStatusSnapshot) {
        self.protocolVersion = protocolVersion
        self.status = status
    }
}

public enum StreamDeckIncomingMessage: Codable, Equatable, Sendable {
    case hello(StreamDeckHello)
    case command(StreamDeckCommandRequest)

    private enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion
        case pluginVersion
        case id
        case command
    }

    private enum MessageType: String, Codable {
        case hello
        case command
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(MessageType.self, forKey: .type) {
        case .hello:
            self = .hello(
                StreamDeckHello(
                    protocolVersion: try container.decode(Int.self, forKey: .protocolVersion),
                    pluginVersion: try container.decode(String.self, forKey: .pluginVersion)
                )
            )
        case .command:
            self = .command(
                StreamDeckCommandRequest(
                    id: try container.decode(String.self, forKey: .id),
                    command: try container.decode(StreamDeckCommand.self, forKey: .command)
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let message):
            try container.encode(MessageType.hello, forKey: .type)
            try container.encode(message.protocolVersion, forKey: .protocolVersion)
            try container.encode(message.pluginVersion, forKey: .pluginVersion)
        case .command(let message):
            try container.encode(MessageType.command, forKey: .type)
            try container.encode(message.id, forKey: .id)
            try container.encode(message.command, forKey: .command)
        }
    }
}

public enum StreamDeckOutgoingMessage: Codable, Equatable, Sendable {
    case commandResult(StreamDeckCommandResult)
    case status(StreamDeckStatusMessage)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case accepted
        case reason
        case protocolVersion
        case status
    }

    private enum MessageType: String, Codable {
        case commandResult
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(MessageType.self, forKey: .type) {
        case .commandResult:
            let id = try container.decode(String.self, forKey: .id)
            let accepted = try container.decode(Bool.self, forKey: .accepted)
            let reason = try container.decodeIfPresent(StreamDeckRejectionReason.self, forKey: .reason)
            guard StreamDeckCommandResult.isValid(accepted: accepted, reason: reason) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .accepted,
                    in: container,
                    debugDescription: "Accepted command results must not have a rejection reason; rejected results must have one."
                )
            }
            self = .commandResult(
                StreamDeckCommandResult(
                    id: id,
                    accepted: accepted,
                    reason: reason
                )
            )
        case .status:
            self = .status(
                StreamDeckStatusMessage(
                    protocolVersion: try container.decode(Int.self, forKey: .protocolVersion),
                    status: try container.decode(StreamDeckStatusSnapshot.self, forKey: .status)
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .commandResult(let message):
            precondition(
                StreamDeckCommandResult.isValid(accepted: message.accepted, reason: message.reason),
                "Accepted command results must not have a rejection reason; rejected results must have one."
            )
            try container.encode(MessageType.commandResult, forKey: .type)
            try container.encode(message.id, forKey: .id)
            try container.encode(message.accepted, forKey: .accepted)
            try container.encodeIfPresent(message.reason, forKey: .reason)
        case .status(let message):
            try container.encode(MessageType.status, forKey: .type)
            try container.encode(message.protocolVersion, forKey: .protocolVersion)
            try container.encode(message.status, forKey: .status)
        }
    }
}
