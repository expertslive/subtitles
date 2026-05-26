import Darwin
import EventSubtitlesRemoteControl
import Foundation

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    do {
        guard try condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    } catch {
        fputs("FAIL: \(message): \(error)\n", stderr)
        exit(1)
    }
}

private func testPanicBlankCommandMessageRoundTrips() throws {
    let input = StreamDeckIncomingMessage.command(
        StreamDeckCommandRequest(id: "panic-1", command: .panicBlank)
    )
    let encoded = try JSONEncoder().encode(input)
    let decoded = try JSONDecoder().decode(StreamDeckIncomingMessage.self, from: encoded)

    expect(decoded == input, "panicBlank command message should round trip through JSON")
}

private func testHelloMessageRoundTripsWithDefaultProtocolVersion() throws {
    let input = StreamDeckIncomingMessage.hello(
        StreamDeckHello(pluginVersion: "1.0.0")
    )
    let encoded = try JSONEncoder().encode(input)
    let decoded = try JSONDecoder().decode(StreamDeckIncomingMessage.self, from: encoded)

    expect(decoded == input, "hello message should round trip through JSON")
}

private func testAcceptedCommandResultRoundTrips() throws {
    let input = StreamDeckOutgoingMessage.commandResult(
        StreamDeckCommandResult(id: "accepted-1", accepted: true)
    )
    let encoded = try JSONEncoder().encode(input)
    let decoded = try JSONDecoder().decode(StreamDeckOutgoingMessage.self, from: encoded)

    expect(decoded == input, "accepted command result should round trip through JSON")
}

private func testRejectedCommandResultRoundTrips() throws {
    let input = StreamDeckOutgoingMessage.commandResult(
        StreamDeckCommandResult(id: "rejected-1", accepted: false, reason: .invalidState)
    )
    let encoded = try JSONEncoder().encode(input)
    let decoded = try JSONDecoder().decode(StreamDeckOutgoingMessage.self, from: encoded)

    expect(decoded == input, "rejected command result should round trip through JSON")
}

private func testNilErrorSummaryEncodesAsExplicitNull() throws {
    let status = StreamDeckStatusSnapshot(
        sessionState: .running,
        elapsedText: "00:01:42",
        displayState: .filled,
        outputState: .live,
        captionState: .active,
        audioState: .healthy,
        errorSummary: nil,
        displayedSegmentCount: 12
    )
    let output = StreamDeckOutgoingMessage.status(
        StreamDeckStatusMessage(protocolVersion: streamDeckProtocolVersion, status: status)
    )
    let data = try JSONEncoder().encode(output)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let serializedStatus = object["status"] as? [String: Any]
    else {
        expect(false, "status message JSON should contain a status object")
        return
    }

    expect(serializedStatus.keys.contains("errorSummary"), "status JSON should include errorSummary")
    expect(serializedStatus["errorSummary"] is NSNull, "nil errorSummary should serialize as JSON null")
}

private func testStatusMessageRoundTrips() throws {
    let input = StreamDeckOutgoingMessage.status(
        StreamDeckStatusMessage(
            status: StreamDeckStatusSnapshot(
                sessionState: .error,
                elapsedText: "00:01:42",
                displayState: .window,
                outputState: .blanked,
                captionState: .idle,
                audioState: .warning,
                errorSummary: "Audio source unavailable",
                displayedSegmentCount: 12
            )
        )
    )
    let encoded = try JSONEncoder().encode(input)
    let decoded = try JSONDecoder().decode(StreamDeckOutgoingMessage.self, from: encoded)

    expect(decoded == input, "status message should round trip through JSON")
}

private func testProtocolDefaultsAreAppliedByConvenienceInitializers() {
    let snapshot = StreamDeckStatusSnapshot(
        sessionState: .stopped,
        elapsedText: "00:00:00",
        displayState: .hidden,
        outputState: .live,
        captionState: .clear,
        audioState: .unknown,
        errorSummary: nil,
        displayedSegmentCount: 0
    )
    let hello = StreamDeckHello(pluginVersion: "1.0.0")
    let result = StreamDeckCommandResult(id: "ok", accepted: true)
    let statusMessage = StreamDeckStatusMessage(status: snapshot)

    expect(hello.protocolVersion == streamDeckProtocolVersion, "hello should use current protocol version by default")
    expect(result.reason == nil, "accepted command result should default to no rejection reason")
    expect(
        statusMessage.protocolVersion == streamDeckProtocolVersion,
        "status message should use current protocol version by default"
    )
}

private func testDiscoveryRecordRoundTripsAndCreatesIntermediateDirectory() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("EventSubtitlesRemoteControlUnitTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let directoryURL = rootURL.appendingPathComponent("nested/discovery", isDirectory: true)
    let store = StreamDeckDiscoveryStore(directoryURL: directoryURL)
    let record = StreamDeckDiscoveryRecord(
        host: "127.0.0.1",
        port: 43123,
        protocolVersion: 7,
        processID: 4_242,
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000.123456)
    )

    expect(!FileManager.default.fileExists(atPath: directoryURL.path), "discovery directory should begin absent")

    try store.write(record)

    expect(FileManager.default.fileExists(atPath: store.recordURL.path), "writing discovery should create nested directory and file")
    expect(try store.read() == record, "discovery record should round trip through JSON")
}

private func testDiscoveryRecordURLIsDeterministic() {
    let directoryURL = URL(fileURLWithPath: "/tmp/discovery-location", isDirectory: true)
    let store = StreamDeckDiscoveryStore(directoryURL: directoryURL)

    expect(
        store.recordURL == directoryURL.appendingPathComponent("streamdeck-control.json"),
        "discovery record should use the streamdeck-control.json filename"
    )
}

private func testDiscoveryRecordWritesSortedFractionalISO8601JSON() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("EventSubtitlesRemoteControlUnitTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = StreamDeckDiscoveryStore(directoryURL: rootURL)
    try store.write(
        StreamDeckDiscoveryRecord(
            host: "127.0.0.1",
            port: 43123,
            protocolVersion: 1,
            processID: 4_242,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000.125)
        )
    )
    let json = try String(contentsOf: store.recordURL, encoding: .utf8)

    expect(
        json == #"{"generatedAt":"2023-11-14T22:13:20.125Z","host":"127.0.0.1","port":43123,"processID":4242,"protocolVersion":1}"#,
        "discovery record should use sorted keys and fractional ISO-8601 timestamps"
    )
}

private func testDiscoveryRecordReadsWholeSecondISO8601JSON() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("EventSubtitlesRemoteControlUnitTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = StreamDeckDiscoveryStore(directoryURL: rootURL)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try Data(
        #"{"generatedAt":"2023-11-14T22:13:20Z","host":"127.0.0.1","port":43123,"processID":4242,"protocolVersion":1}"#.utf8
    ).write(to: store.recordURL)

    expect(
        try store.read()?.generatedAt == Date(timeIntervalSince1970: 1_700_000_000),
        "discovery store should read previously written whole-second ISO-8601 timestamps"
    )
}

private func testDiscoveryRecordExactlyRoundTripsContemporaryReferenceDate() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("EventSubtitlesRemoteControlUnitTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = StreamDeckDiscoveryStore(directoryURL: rootURL)
    let record = StreamDeckDiscoveryRecord(
        host: "localhost",
        port: 9_999,
        processID: 101,
        generatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.123456.nextUp)
    )

    try store.write(record)

    expect(
        try store.read() == record,
        "discovery record should exactly round trip a contemporary reference-date timestamp"
    )
}

private func testDiscoveryRecordExactlyRoundTripsImmediatelyBeforeWholeSecond() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("EventSubtitlesRemoteControlUnitTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = StreamDeckDiscoveryStore(directoryURL: rootURL)
    let record = StreamDeckDiscoveryRecord(
        host: "localhost",
        port: 9_999,
        processID: 101,
        generatedAt: Date(timeIntervalSinceReferenceDate: 1.0.nextDown)
    )

    try store.write(record)
    let json = try String(contentsOf: store.recordURL, encoding: .utf8)

    expect(!json.contains(".Z\""), "discovery timestamp should not emit an empty fraction")
    expect(
        try store.read() == record,
        "discovery record should exactly round trip immediately below a whole-second boundary"
    )
}

private func testDiscoveryRecordEncodesTinyFractionWithoutExponentNotation() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("EventSubtitlesRemoteControlUnitTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = StreamDeckDiscoveryStore(directoryURL: rootURL)
    let record = StreamDeckDiscoveryRecord(
        host: "localhost",
        port: 9_999,
        processID: 101,
        generatedAt: Date(timeIntervalSinceReferenceDate: .leastNonzeroMagnitude)
    )

    try store.write(record)
    let data = try Data(contentsOf: store.recordURL)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let timestamp = object?["generatedAt"] as? String

    expect(timestamp?.contains("e") == false, "discovery timestamp fractions should not use exponent notation")
    expect(try store.read() == record, "discovery record should exactly round trip a tiny fractional timestamp")
}

private func testDiscoveryRecordRejectsNonDecimalFraction() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("EventSubtitlesRemoteControlUnitTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = StreamDeckDiscoveryStore(directoryURL: rootURL)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try Data(
        #"{"generatedAt":"2023-11-14T22:13:20.1e3Z","host":"127.0.0.1","port":43123,"processID":4242,"protocolVersion":1}"#.utf8
    ).write(to: store.recordURL)

    do {
        _ = try store.read()
        expect(false, "non-decimal discovery timestamp fractions should fail decoding")
    } catch {
        // Expected: fractional timestamps only permit decimal digits.
    }
}

private func testDiscoveryRecordRemovalRequiresMatchingProcessID() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("EventSubtitlesRemoteControlUnitTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = StreamDeckDiscoveryStore(directoryURL: rootURL)
    let record = StreamDeckDiscoveryRecord(
        host: "localhost",
        port: 9_999,
        processID: 101,
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try store.write(record)

    try store.removeIfOwned(by: 202)
    expect(try store.read() == record, "a different process ID should not remove the discovery record")

    try store.removeIfOwned(by: 101)
    expect(try store.read() == nil, "the owning process ID should remove the discovery record")
}

private func testDiscoveryRecordUsesCurrentProtocolVersionByDefault() {
    let record = StreamDeckDiscoveryRecord(host: "localhost", port: 9_999, processID: 101)

    expect(
        record.protocolVersion == streamDeckProtocolVersion,
        "discovery record should use current protocol version by default"
    )
}

private func testMalformedDiscoveryRecordThrowsWhenRead() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("EventSubtitlesRemoteControlUnitTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = StreamDeckDiscoveryStore(directoryURL: rootURL)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try Data("{ malformed json".utf8).write(to: store.recordURL)

    do {
        _ = try store.read()
        expect(false, "malformed discovery JSON should throw during read")
    } catch {
        // Expected: an existing malformed record is not equivalent to an absent record.
    }
}

private func testCaptionStatusProjection() {
    let now = Date(timeIntervalSinceReferenceDate: 100)

    expect(
        StreamDeckStatusPolicy.captionActiveDuration == 2,
        "caption status should use a two-second active duration"
    )
    expect(
        StreamDeckStatusPolicy.captionState(text: "", lastActivityAt: now, now: now) == .clear,
        "empty captions should project as clear"
    )
    expect(
        StreamDeckStatusPolicy.captionState(
            text: "New caption",
            lastActivityAt: now.addingTimeInterval(-1.999),
            now: now
        ) == .active,
        "non-empty captions updated less than two seconds ago should project as active"
    )
    expect(
        StreamDeckStatusPolicy.captionState(text: "Caption", lastActivityAt: nil, now: now) == .idle,
        "non-empty captions without activity timestamps should project as idle"
    )
    expect(
        StreamDeckStatusPolicy.captionState(
            text: "Caption",
            lastActivityAt: now.addingTimeInterval(-2),
            now: now
        ) == .idle,
        "captions at the exact two-second boundary should project as idle"
    )
}

private func testAudioStatusProjection() {
    let now = Date(timeIntervalSinceReferenceDate: 100)
    let pastGrace = now.addingTimeInterval(-11)

    expect(StreamDeckStatusPolicy.audioSignalThreshold == 0.05, "audio status should use the v1 signal threshold")
    expect(StreamDeckStatusPolicy.audioGraceDuration == 10, "audio status should use a ten-second grace duration")
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: false,
            isSelectedInputAvailable: false,
            hasAudioFailure: false,
            audioLevel: 1,
            lastAudibleInputAt: now,
            sessionStartedAt: pastGrace,
            now: now
        ) == .warning,
        "a running session without audio input should project as warning"
    )
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: false,
            isSelectedInputAvailable: true,
            hasAudioFailure: true,
            audioLevel: 1,
            lastAudibleInputAt: now,
            sessionStartedAt: pastGrace,
            now: now
        ) == .warning,
        "a typed audio failure should project as warning"
    )
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: false,
            isDemo: false,
            isSelectedInputAvailable: true,
            hasAudioFailure: false,
            audioLevel: 1,
            lastAudibleInputAt: now,
            sessionStartedAt: pastGrace,
            now: now
        ) == .unknown,
        "stopped sessions should project audio state as unknown"
    )
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: true,
            isSelectedInputAvailable: true,
            hasAudioFailure: false,
            audioLevel: 1,
            lastAudibleInputAt: now,
            sessionStartedAt: pastGrace,
            now: now
        ) == .unknown,
        "demo sessions should project audio state as unknown"
    )
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: false,
            isSelectedInputAvailable: true,
            hasAudioFailure: false,
            audioLevel: 0,
            lastAudibleInputAt: nil,
            sessionStartedAt: now.addingTimeInterval(-9),
            now: now
        ) == .unknown,
        "a real session within its initial grace period should project as unknown without signal"
    )
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: false,
            isSelectedInputAvailable: true,
            hasAudioFailure: false,
            audioLevel: 0,
            lastAudibleInputAt: now.addingTimeInterval(-3),
            sessionStartedAt: now.addingTimeInterval(-2),
            now: now
        ) == .unknown,
        "audible input before the current session started should not make its initial grace healthy"
    )
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: false,
            isSelectedInputAvailable: true,
            hasAudioFailure: false,
            audioLevel: 0,
            lastAudibleInputAt: nil,
            sessionStartedAt: now.addingTimeInterval(-10),
            now: now
        ) == .silent,
        "a real session at the exact ten-second grace boundary should project as silent without signal"
    )
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: false,
            isSelectedInputAvailable: true,
            hasAudioFailure: false,
            audioLevel: 0.051,
            lastAudibleInputAt: nil,
            sessionStartedAt: pastGrace,
            now: now
        ) == .healthy,
        "a current level above the threshold should project as healthy"
    )
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: false,
            isSelectedInputAvailable: true,
            hasAudioFailure: false,
            audioLevel: 0.05,
            lastAudibleInputAt: nil,
            sessionStartedAt: pastGrace,
            now: now
        ) == .silent,
        "a current level at the exact threshold should not count as signal"
    )
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: false,
            isSelectedInputAvailable: true,
            hasAudioFailure: false,
            audioLevel: 0,
            lastAudibleInputAt: now.addingTimeInterval(-9.999),
            sessionStartedAt: pastGrace,
            now: now
        ) == .healthy,
        "audible input less than ten seconds ago should project as healthy"
    )
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: false,
            isSelectedInputAvailable: true,
            hasAudioFailure: false,
            audioLevel: 0,
            lastAudibleInputAt: nil,
            sessionStartedAt: pastGrace,
            now: now
        ) == .silent,
        "a real running session past grace with no signal should project as silent"
    )
    let nonAudioErrorMessage = "Translation failed for selected language"
    expect(StreamDeckStatusPolicy.errorSummary(nonAudioErrorMessage) != nil, "non-audio errors should remain displayable")
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: false,
            isSelectedInputAvailable: true,
            hasAudioFailure: false,
            audioLevel: 0,
            lastAudibleInputAt: nil,
            sessionStartedAt: pastGrace,
            now: now
        ) == .silent,
        "a displayable non-audio error without a typed audio failure should not project as warning"
    )
    expect(
        StreamDeckStatusPolicy.audioState(
            isRunning: true,
            isDemo: false,
            isSelectedInputAvailable: true,
            hasAudioFailure: false,
            audioLevel: 0,
            lastAudibleInputAt: now.addingTimeInterval(-10),
            sessionStartedAt: pastGrace,
            now: now
        ) == .silent,
        "audible input at the exact ten-second boundary should not count as recent"
    )
}

private func testErrorSummaryProjection() {
    expect(StreamDeckStatusPolicy.errorSummary(nil) == nil, "nil error summaries should remain nil")
    expect(StreamDeckStatusPolicy.errorSummary(" \n\t ") == nil, "whitespace-only error summaries should be omitted")
    expect(
        StreamDeckStatusPolicy.errorSummary("  Audio\t capture \n\n failed\t Try   another input  ") ==
            "Audio capture failed Try another input",
        "error summaries should collapse whitespace runs and trim whitespace"
    )
    let longMessage = String(repeating: "x", count: 121)
    expect(
        StreamDeckStatusPolicy.errorSummary(longMessage) == String(repeating: "x", count: 120),
        "error summaries should be capped to 120 characters"
    )
}

private func rejectsDecode(
    _ json: String,
    _ message: String,
    requireDataCorrupted: Bool = false
) -> Bool {
    do {
        _ = try JSONDecoder().decode(StreamDeckOutgoingMessage.self, from: Data(json.utf8))
        fputs("FAIL: \(message)\n", stderr)
        return false
    } catch let error as DecodingError {
        if requireDataCorrupted {
            guard case .dataCorrupted = error else {
                fputs("FAIL: \(message) with dataCorrupted, got \(error)\n", stderr)
                return false
            }
        }
        return true
    } catch {
        fputs("FAIL: \(message) with a decoding error, got \(error)\n", stderr)
        return false
    }
}

private func testStatusMessageRejectsMissingErrorSummary() -> Bool {
    rejectsDecode(
        """
        {"type":"status","protocolVersion":1,"status":{"sessionState":"running","elapsedText":"00:00:01","displayState":"filled","outputState":"live","captionState":"active","audioState":"healthy","displayedSegmentCount":1}}
        """,
        "status message without errorSummary should fail decoding"
    )
}

private func testAcceptedCommandResultRejectsReason() -> Bool {
    rejectsDecode(
        """
        {"type":"commandResult","id":"bad-accepted","accepted":true,"reason":"invalidState"}
        """,
        "accepted command result with reason should fail decoding",
        requireDataCorrupted: true
    )
}

private func testRejectedCommandResultRequiresReason() -> Bool {
    rejectsDecode(
        """
        {"type":"commandResult","id":"bad-rejected","accepted":false}
        """,
        "rejected command result without reason should fail decoding",
        requireDataCorrupted: true
    )
}

do {
    try testPanicBlankCommandMessageRoundTrips()
    try testHelloMessageRoundTripsWithDefaultProtocolVersion()
    try testAcceptedCommandResultRoundTrips()
    try testRejectedCommandResultRoundTrips()
    try testNilErrorSummaryEncodesAsExplicitNull()
    try testStatusMessageRoundTrips()
    testProtocolDefaultsAreAppliedByConvenienceInitializers()
    try testDiscoveryRecordRoundTripsAndCreatesIntermediateDirectory()
    testDiscoveryRecordURLIsDeterministic()
    try testDiscoveryRecordWritesSortedFractionalISO8601JSON()
    try testDiscoveryRecordReadsWholeSecondISO8601JSON()
    try testDiscoveryRecordExactlyRoundTripsContemporaryReferenceDate()
    try testDiscoveryRecordExactlyRoundTripsImmediatelyBeforeWholeSecond()
    try testDiscoveryRecordEncodesTinyFractionWithoutExponentNotation()
    try testDiscoveryRecordRejectsNonDecimalFraction()
    try testDiscoveryRecordRemovalRequiresMatchingProcessID()
    testDiscoveryRecordUsesCurrentProtocolVersionByDefault()
    try testMalformedDiscoveryRecordThrowsWhenRead()
    testCaptionStatusProjection()
    testAudioStatusProjection()
    testErrorSummaryProjection()
    var negativeTestsPassed = true
    negativeTestsPassed = testStatusMessageRejectsMissingErrorSummary() && negativeTestsPassed
    negativeTestsPassed = testAcceptedCommandResultRejectsReason() && negativeTestsPassed
    negativeTestsPassed = testRejectedCommandResultRequiresReason() && negativeTestsPassed
    guard negativeTestsPassed else {
        exit(1)
    }
    print("PASS: Stream Deck remote control protocol")
} catch {
    fputs("FAIL: Stream Deck remote control protocol: \(error)\n", stderr)
    exit(1)
}
