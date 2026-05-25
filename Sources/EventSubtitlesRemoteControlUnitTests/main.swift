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

do {
    try testPanicBlankCommandMessageRoundTrips()
    try testNilErrorSummaryEncodesAsExplicitNull()
    print("PASS: Stream Deck remote control protocol")
} catch {
    fputs("FAIL: Stream Deck remote control protocol: \(error)\n", stderr)
    exit(1)
}
