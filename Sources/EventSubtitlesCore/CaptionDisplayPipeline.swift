import Foundation

public enum CaptionDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case calmBlocks
    case liveRollUp
    case fastDraft

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .calmBlocks: "Calm Blocks"
        case .liveRollUp: "Live Roll-up"
        case .fastDraft: "Fast Draft"
        }
    }

    public var description: String {
        switch self {
        case .calmBlocks:
            "Shows stable caption blocks after a short delay."
        case .liveRollUp:
            "Appends stable phrases into a rolling caption stack."
        case .fastDraft:
            "Shows raw draft captions immediately for testing."
        }
    }
}

public enum CaptionStabilityLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case fast
    case balanced
    case calm

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fast: "Fast"
        case .balanced: "Balanced"
        case .calm: "Calm"
        }
    }

    public var defaultUnstableWordCount: Int {
        switch self {
        case .fast: 1
        case .balanced: 2
        case .calm: 3
        }
    }

    public var defaultCommitDelay: TimeInterval {
        switch self {
        case .fast: 0.25
        case .balanced: 0.4
        case .calm: 0.6
        }
    }

    public var defaultMinimumHold: TimeInterval {
        switch self {
        case .fast: 0.7
        case .balanced: 0.95
        case .calm: 1.2
        }
    }
}

public struct CaptionDisplayConfiguration: Equatable, Codable, Sendable {
    public var mode: CaptionDisplayMode
    public var stability: CaptionStabilityLevel
    public var commitDelay: TimeInterval
    public var unstableWordCount: Int
    public var minimumHold: TimeInterval
    public var maximumLatency: TimeInterval

    public init(
        mode: CaptionDisplayMode = .calmBlocks,
        stability: CaptionStabilityLevel = .calm,
        commitDelay: TimeInterval? = nil,
        unstableWordCount: Int? = nil,
        minimumHold: TimeInterval? = nil,
        maximumLatency: TimeInterval = 3.0
    ) {
        self.mode = mode
        self.stability = stability
        self.commitDelay = max(0.1, min(2.5, commitDelay ?? stability.defaultCommitDelay))
        self.unstableWordCount = max(0, min(8, unstableWordCount ?? stability.defaultUnstableWordCount))
        self.minimumHold = max(0.4, min(5.0, minimumHold ?? stability.defaultMinimumHold))
        self.maximumLatency = max(self.commitDelay, min(8.0, maximumLatency))
    }
}

public struct TranscriptSnapshot: Equatable, Sendable {
    public var text: String
    public var createdAt: Date
    public var isFinal: Bool
    public var words: [RecognizedWord]

    public init(
        text: String,
        createdAt: Date = Date(),
        isFinal: Bool,
        words: [RecognizedWord] = []
    ) {
        self.text = text
        self.createdAt = createdAt
        self.isFinal = isFinal
        self.words = words
    }
}

public struct StableCaptionPhrase: Equatable, Sendable {
    public var text: String
    public var committedAt: Date
    public var isFinal: Bool

    public init(text: String, committedAt: Date, isFinal: Bool) {
        self.text = text
        self.committedAt = committedAt
        self.isFinal = isFinal
    }
}

public struct CaptionCue: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceText: String
    public let displayText: String
    public let createdAt: Date
    public let startsAt: Date
    public let minimumEndsAt: Date
    public let maximumEndsAt: Date
    public let mode: CaptionDisplayMode

    public init(
        id: UUID = UUID(),
        sourceText: String,
        displayText: String,
        createdAt: Date,
        startsAt: Date,
        minimumEndsAt: Date,
        maximumEndsAt: Date,
        mode: CaptionDisplayMode
    ) {
        self.id = id
        self.sourceText = sourceText
        self.displayText = displayText
        self.createdAt = createdAt
        self.startsAt = startsAt
        self.minimumEndsAt = minimumEndsAt
        self.maximumEndsAt = maximumEndsAt
        self.mode = mode
    }
}

public struct CaptionStabilityEngine: Sendable {
    private var previousTokens: [CaptionToken] = []
    private var committedTokenCount = 0
    private static let confidenceThreshold: Float = 0.7

    public init() {}

    public mutating func reset() {
        previousTokens = []
        committedTokenCount = 0
    }

    public mutating func ingest(
        _ snapshot: TranscriptSnapshot,
        configuration: CaptionDisplayConfiguration
    ) -> [StableCaptionPhrase] {
        let tokens = CaptionToken.tokenize(snapshot.text)
        guard !tokens.isEmpty else {
            previousTokens = []
            committedTokenCount = 0
            return []
        }

        if snapshot.isFinal {
            defer { reset() }
            guard committedTokenCount < tokens.count else {
                return []
            }

            return [
                StableCaptionPhrase(
                    text: tokens[committedTokenCount...].map(\.text).joined(separator: " "),
                    committedAt: snapshot.createdAt,
                    isFinal: true
                )
            ]
        }

        let publishableCount = computePublishableCount(
            tokens: tokens,
            words: snapshot.words,
            configuration: configuration
        )

        previousTokens = tokens

        // If the stable prefix shrank (e.g. new utterance after flush), reset the committed pointer.
        if publishableCount < committedTokenCount {
            committedTokenCount = publishableCount
        }

        guard publishableCount > committedTokenCount else {
            return []
        }

        let phrase = tokens[committedTokenCount..<publishableCount]
            .map(\.text)
            .joined(separator: " ")
        committedTokenCount = publishableCount

        return [
            StableCaptionPhrase(
                text: phrase,
                committedAt: snapshot.createdAt,
                isFinal: false
            )
        ]
    }

    public mutating func flushPending(
        committedAt: Date = Date(),
        isFinal: Bool = false
    ) -> [StableCaptionPhrase] {
        guard committedTokenCount < previousTokens.count else {
            if isFinal {
                reset()
            }
            return []
        }

        let phrase = previousTokens[committedTokenCount...]
            .map(\.text)
            .joined(separator: " ")
        committedTokenCount = previousTokens.count

        if isFinal {
            reset()
        }

        return [
            StableCaptionPhrase(
                text: phrase,
                committedAt: committedAt,
                isFinal: isFinal
            )
        ]
    }

    private func computePublishableCount(
        tokens: [CaptionToken],
        words: [RecognizedWord],
        configuration: CaptionDisplayConfiguration
    ) -> Int {
        let trailingHold = max(0, tokens.count - configuration.unstableWordCount)

        // No word-level confidences available → keep the prior prefix-agreement rule.
        if words.isEmpty || words.count != tokens.count {
            guard !previousTokens.isEmpty else {
                return committedTokenCount
            }
            let commonPrefix = commonPrefixCount(previousTokens, tokens)
            if commonPrefix < committedTokenCount {
                // prefix changed under us; reset committed pointer
                return commonPrefix
            }
            return min(commonPrefix, trailingHold)
        }

        // Word confidences available: commit a word as soon as
        //   - it is within the trailing-hold horizon, AND
        //   - it has probability ≥ threshold OR it agreed with the same position in previousTokens.
        let priorPrefix = commonPrefixCount(previousTokens, tokens)

        var publishable = committedTokenCount
        let horizon = trailingHold
        while publishable < horizon {
            let word = words[publishable]
            let confident = word.probability >= Self.confidenceThreshold
            let agreedWithPrior = publishable < priorPrefix
            if confident || agreedWithPrior {
                publishable += 1
            } else {
                break
            }
        }
        return publishable
    }

    private func commonPrefixCount(_ left: [CaptionToken], _ right: [CaptionToken]) -> Int {
        var count = 0
        for (leftToken, rightToken) in zip(left, right) {
            guard leftToken.normalized == rightToken.normalized else {
                break
            }
            count += 1
        }
        return count
    }
}

public struct CaptionDisplayScheduler: Sendable {
    private var pendingSourceParts: [String] = []
    private var pendingDisplayParts: [String] = []
    private var pendingSince: Date?
    private var currentCue: CaptionCue?

    public init() {}

    public var pendingDisplayText: String {
        normalize(pendingDisplayParts.joined(separator: " "))
    }

    public var hasPendingCaption: Bool {
        !pendingDisplayText.isEmpty
    }

    public func estimatedLatencyText(now: Date = Date()) -> String {
        guard let pendingSince else {
            return "0.0s"
        }
        return String(format: "%.1fs", max(0, now.timeIntervalSince(pendingSince)))
    }

    public mutating func reset() {
        pendingSourceParts = []
        pendingDisplayParts = []
        pendingSince = nil
        currentCue = nil
    }

    public mutating func enqueue(
        sourceText: String,
        displayText: String,
        now: Date = Date()
    ) {
        let source = normalize(sourceText)
        let display = normalize(displayText)
        guard !source.isEmpty, !display.isEmpty else {
            return
        }

        if pendingSince == nil {
            pendingSince = now
        }
        pendingSourceParts.append(source)
        pendingDisplayParts.append(display)
    }

    public mutating func nextCueIfDue(
        now: Date = Date(),
        configuration: CaptionDisplayConfiguration,
        force: Bool = false
    ) -> CaptionCue? {
        let source = normalize(pendingSourceParts.joined(separator: " "))
        let display = normalize(pendingDisplayParts.joined(separator: " "))
        guard !source.isEmpty, !display.isEmpty, let pendingSince else {
            return nil
        }

        let pendingAge = now.timeIntervalSince(pendingSince)
        let currentAge = currentCue.map { now.timeIntervalSince($0.startsAt) } ?? .infinity
        let pendingReady = force ||
            pendingAge >= configuration.commitDelay ||
            pendingAge >= configuration.maximumLatency
        let currentReady = currentCue == nil ||
            currentAge >= configuration.minimumHold ||
            currentCue.map { now >= $0.maximumEndsAt } == true

        guard pendingReady, currentReady else {
            return nil
        }

        let cue = CaptionCue(
            sourceText: source,
            displayText: display,
            createdAt: pendingSince,
            startsAt: now,
            minimumEndsAt: now.addingTimeInterval(configuration.minimumHold),
            maximumEndsAt: now.addingTimeInterval(max(configuration.minimumHold, configuration.maximumLatency)),
            mode: configuration.mode
        )

        currentCue = cue
        pendingSourceParts = []
        pendingDisplayParts = []
        self.pendingSince = nil
        return cue
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CaptionToken: Equatable, Sendable {
    var text: String
    var normalized: String

    static func tokenize(_ text: String) -> [CaptionToken] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .compactMap { rawToken in
                let text = String(rawToken)
                let normalized = text
                    .trimmingCharacters(in: .punctuationCharacters)
                    .lowercased()
                guard !normalized.isEmpty else {
                    return nil
                }
                return CaptionToken(text: text, normalized: normalized)
            }
    }
}
