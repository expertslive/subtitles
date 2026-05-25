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
