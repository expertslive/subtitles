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

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private actor CommandRecorder {
    private var requests: [StreamDeckCommandRequest] = []

    func append(_ request: StreamDeckCommandRequest) {
        requests.append(request)
    }

    func values() -> [StreamDeckCommandRequest] {
        requests
    }
}

private actor StatusCounter {
    private var count = 0

    func nextSnapshot() -> StreamDeckStatusSnapshot {
        count += 1
        return testStatusSnapshot(segmentCount: count)
    }
}

private actor DiagnosticsRecorder {
    private var messages: [String] = []

    func append(_ message: String) {
        messages.append(message)
    }

    func values() -> [String] {
        messages
    }
}

private actor CommandDelayController {
    private var delayedCommandIDs: Set<String>

    init(delayedCommandIDs: Set<String>) {
        self.delayedCommandIDs = delayedCommandIDs
    }

    func result(for request: StreamDeckCommandRequest) async -> StreamDeckCommandResult {
        if delayedCommandIDs.contains(request.id) {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return StreamDeckCommandResult(id: request.id, accepted: true)
    }
}

private enum WebSocketUpgradeResult: Equatable {
    case upgraded
    case rejected(statusLine: String)
}

private final class TestWebSocketClient: @unchecked Sendable {
    private var socketFD: Int32 = -1

    func connect(port: Int, path: String = "/streamdeck/v1") async throws {
        let result = try await connectForUpgradeResult(port: port, path: path)
        guard result == .upgraded else {
            throw TestFailure("websocket upgrade failed")
        }
    }

    func connectForUpgradeResult(port: Int, path: String = "/streamdeck/v1") async throws -> WebSocketUpgradeResult {
        socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw TestFailure("failed to create socket")
        }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            throw TestFailure("failed to connect socket")
        }

        let request = "GET \(path) HTTP/1.1\r\n" +
            "Host: 127.0.0.1:\(port)\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" +
            "Sec-WebSocket-Version: 13\r\n" +
            "\r\n"
        try writeAll(Array(request.utf8))
        let response = try readHTTPResponse()
        guard let statusLine = response.components(separatedBy: "\r\n").first else {
            throw TestFailure("websocket upgrade response had no status line")
        }
        if statusLine.contains(" 101 ") {
            return .upgraded
        }
        Darwin.close(socketFD)
        socketFD = -1
        return .rejected(statusLine: statusLine)
    }

    func send(_ message: StreamDeckIncomingMessage) async throws {
        let data = try JSONEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TestFailure("encoded message was not UTF-8")
        }
        try await sendRawText(text)
    }

    func send(_ messages: [StreamDeckIncomingMessage]) async throws {
        for message in messages {
            try await send(message)
        }
    }

    func sendRawText(_ text: String) async throws {
        guard socketFD >= 0 else {
            throw TestFailure("websocket is not connected")
        }
        let payload = Array(text.utf8)
        guard payload.count < 126 else {
            throw TestFailure("test websocket payload too large")
        }
        let mask: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        let maskedPayload = payload.enumerated().map { index, byte in
            byte ^ mask[index % mask.count]
        }
        try writeAll([0x81, 0x80 | UInt8(payload.count)] + mask + maskedPayload)
    }

    func sendMaskedPing(payload: [UInt8]) throws {
        guard payload.count < 126 else {
            throw TestFailure("test ping payload too large")
        }
        let mask: [UInt8] = [0x05, 0x06, 0x07, 0x08]
        let maskedPayload = payload.enumerated().map { index, byte in
            byte ^ mask[index % mask.count]
        }
        try writeAll([0x89, 0x80 | UInt8(payload.count)] + mask + maskedPayload)
    }

    func sendFragmentedText(_ firstFragment: String, _ secondFragment: String) throws {
        let mask: [UInt8] = [0x09, 0x0A, 0x0B, 0x0C]
        try writeMaskedFrame(firstByte: 0x01, payload: Array(firstFragment.utf8), mask: mask)
        try writeMaskedFrame(firstByte: 0x80, payload: Array(secondFragment.utf8), mask: mask)
    }

    func receivePongPayload() throws -> [UInt8] {
        while true {
            let opcode = try readFrameOpcode()
            if opcode == 0xA {
                return Array(lastFramePayload)
            }
            if opcode == 0x8 {
                throw TestFailure("websocket closed before pong frame")
            }
        }
    }

    func receiveMessage(timeoutNanoseconds: UInt64 = 2_000_000_000) async throws -> StreamDeckOutgoingMessage {
        let text = try readTextFrame()
        return try JSONDecoder().decode(StreamDeckOutgoingMessage.self, from: Data(text.utf8))
    }

    func waitForClose(timeoutNanoseconds: UInt64 = 2_000_000_000) async throws {
        while true {
            do {
                let opcode = try readFrameOpcode()
                if opcode == 0x8 {
                    return
                }
            } catch {
                throw TestFailure("timed out waiting for websocket close")
            }
        }
    }

    func close() async {
        if socketFD >= 0 {
            try? writeAll([0x88, 0x80, 0x01, 0x02, 0x03, 0x04])
            Darwin.close(socketFD)
            socketFD = -1
        }
    }

    private func readHTTPResponse() throws -> String {
        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        while true {
            let count = Darwin.read(socketFD, &byte, 1)
            guard count == 1 else {
                throw TestFailure("failed reading websocket handshake")
            }
            bytes.append(byte)
            if bytes.suffix(4) == [13, 10, 13, 10] {
                break
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func readTextFrame() throws -> String {
        while true {
            let opcode = try readFrameOpcode()
            if opcode == 0x1 {
                guard let text = String(data: lastFramePayload, encoding: .utf8) else {
                    throw TestFailure("received non-UTF8 websocket text")
                }
                return text
            }
            if opcode == 0x8 {
                throw TestFailure("websocket closed before text frame")
            }
            if opcode != 0x9 && opcode != 0xA {
                throw TestFailure("expected text websocket frame, got opcode \(opcode)")
            }
        }
    }

    private var lastFramePayload: Data = Data()

    @discardableResult
    private func readFrameOpcode() throws -> UInt8 {
        let header = try readExact(2)
        let opcode = header[0] & 0x0f
        let isMasked = (header[1] & 0x80) != 0
        var length = Int(header[1] & 0x7f)
        if length == 126 {
            let extended = try readExact(2)
            length = Int(extended[0]) << 8 | Int(extended[1])
        } else if length == 127 {
            let extended = try readExact(8)
            length = extended.reduce(0) { ($0 << 8) | Int($1) }
        }
        let mask = isMasked ? try readExact(4) : []
        var payload = try readExact(length)
        if isMasked {
            payload = payload.enumerated().map { index, byte in
                byte ^ mask[index % mask.count]
            }
        }
        lastFramePayload = Data(payload)
        return opcode
    }

    private func readExact(_ count: Int) throws -> [UInt8] {
        guard count > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let readCount = bytes.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(socketFD, rawBuffer.baseAddress!.advanced(by: offset), count - offset)
            }
            guard readCount > 0 else {
                throw TestFailure("socket closed while reading")
            }
            offset += readCount
        }
        return bytes
    }

    private func writeAll(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { rawBuffer in
                Darwin.write(socketFD, rawBuffer.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
            guard written > 0 else {
                throw TestFailure("socket write failed")
            }
            offset += written
        }
    }

    private func writeMaskedFrame(firstByte: UInt8, payload: [UInt8], mask: [UInt8]) throws {
        guard payload.count < 126 else {
            throw TestFailure("test websocket payload too large")
        }
        let maskedPayload = payload.enumerated().map { index, byte in
            byte ^ mask[index % mask.count]
        }
        try writeAll([firstByte, 0x80 | UInt8(payload.count)] + mask + maskedPayload)
    }
}

private func temporaryDiscoveryStore() -> (URL, StreamDeckDiscoveryStore) {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("EventSubtitlesRemoteControlUnitTests-\(UUID().uuidString)", isDirectory: true)
    return (rootURL, StreamDeckDiscoveryStore(directoryURL: rootURL))
}

private func testStatusSnapshot(segmentCount: Int = 0) -> StreamDeckStatusSnapshot {
    StreamDeckStatusSnapshot(
        sessionState: .running,
        elapsedText: "00:00:\(String(format: "%02d", segmentCount))",
        displayState: .filled,
        outputState: .live,
        captionState: .active,
        audioState: .healthy,
        errorSummary: nil,
        displayedSegmentCount: segmentCount
    )
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

private func testServerPublishesDynamicLoopbackDiscoveryAndRemovesOwnedRecordOnStop() async throws {
    let (rootURL, store) = temporaryDiscoveryStore()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let server = StreamDeckControlServer(
        discoveryStore: store,
        commandHandler: { request in StreamDeckCommandResult(id: request.id, accepted: true) },
        statusProvider: { testStatusSnapshot() }
    )
    try await server.start()

    let record = try store.read()
    expect(record?.host == "127.0.0.1", "server discovery should publish loopback host")
    expect((record?.port ?? 0) > 0, "server discovery should publish a dynamic bound port")
    expect(record?.protocolVersion == streamDeckProtocolVersion, "server discovery should publish current protocol version")
    expect(record?.processID == ProcessInfo.processInfo.processIdentifier, "server discovery should publish current process ID")

    try await server.stop()
    expect(try store.read() == nil, "server stop should remove its owned discovery record")
}

private func testServerHelloCommandResultAndStatusFlow() async throws {
    let (rootURL, store) = temporaryDiscoveryStore()
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let handledCommands = CommandRecorder()
    let statusCounter = StatusCounter()
    let diagnostics = DiagnosticsRecorder()

    let server = StreamDeckControlServer(
        discoveryStore: store,
        commandHandler: { request in
            await handledCommands.append(request)
            return StreamDeckCommandResult(id: request.id, accepted: true)
        },
        statusProvider: {
            await statusCounter.nextSnapshot()
        },
        diagnostics: { message in
            Task { await diagnostics.append(message) }
        }
    )
    try await server.start()

    guard let port = try store.read()?.port else {
        expect(false, "server should publish a discovery port before client connection")
        return
    }
    let client = TestWebSocketClient()
    try await client.connect(port: port)
    defer { Task { await client.close() } }

    try await client.send(.hello(StreamDeckHello(pluginVersion: "test-plugin")))
    let helloStatus: StreamDeckOutgoingMessage
    do {
        helloStatus = try await client.receiveMessage()
    } catch {
        fputs("Diagnostics: \(await diagnostics.values())\n", stderr)
        throw error
    }
    expect(
        helloStatus == .status(StreamDeckStatusMessage(status: testStatusSnapshot(segmentCount: 1))),
        "server should send complete status after hello"
    )

    let request = StreamDeckCommandRequest(id: "command-1", command: .panicBlank)
    try await client.send(.command(request))
    let result = try await client.receiveMessage()
    let status = try await client.receiveMessage()
    expect(result == .commandResult(StreamDeckCommandResult(id: "command-1", accepted: true)), "server should return command result")
    expect(status == .status(StreamDeckStatusMessage(status: testStatusSnapshot(segmentCount: 2))), "server should send fresh status after command")
    let handledCommandValues = await handledCommands.values()
    expect(handledCommandValues == [request], "server should pass valid commands to the command handler")
    try await server.stop()
}

private func testServerProcessesBackToBackHelloAndCommandInOrder() async throws {
    let (rootURL, store) = temporaryDiscoveryStore()
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let statusCounter = StatusCounter()
    let server = StreamDeckControlServer(
        discoveryStore: store,
        commandHandler: { request in StreamDeckCommandResult(id: request.id, accepted: true) },
        statusProvider: { await statusCounter.nextSnapshot() }
    )
    try await server.start()

    guard let port = try store.read()?.port else {
        expect(false, "server should publish a discovery port before back-to-back test")
        return
    }
    let client = TestWebSocketClient()
    try await client.connect(port: port)
    defer { Task { await client.close() } }

    try await client.send([
        .hello(StreamDeckHello(pluginVersion: "test-plugin")),
        .command(StreamDeckCommandRequest(id: "back-to-back", command: .panicBlank))
    ])

    let helloStatus = try await client.receiveMessage()
    let result = try await client.receiveMessage()
    let commandStatus = try await client.receiveMessage()
    expect(
        helloStatus == .status(StreamDeckStatusMessage(status: testStatusSnapshot(segmentCount: 1))),
        "back-to-back hello and command should first receive the hello status"
    )
    expect(
        result == .commandResult(StreamDeckCommandResult(id: "back-to-back", accepted: true)),
        "back-to-back hello and command should then receive command result"
    )
    expect(
        commandStatus == .status(StreamDeckStatusMessage(status: testStatusSnapshot(segmentCount: 2))),
        "back-to-back hello and command should finally receive fresh command status"
    )
    try await server.stop()
}

private func testServerPreservesMultipleCommandResultStatusOrderWhenHandlersSuspend() async throws {
    let (rootURL, store) = temporaryDiscoveryStore()
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let statusCounter = StatusCounter()
    let delays = CommandDelayController(delayedCommandIDs: ["slow"])
    let server = StreamDeckControlServer(
        discoveryStore: store,
        commandHandler: { request in await delays.result(for: request) },
        statusProvider: { await statusCounter.nextSnapshot() }
    )
    try await server.start()

    guard let port = try store.read()?.port else {
        expect(false, "server should publish a discovery port before command ordering test")
        return
    }
    let client = TestWebSocketClient()
    try await client.connect(port: port)
    defer { Task { await client.close() } }
    try await client.send(.hello(StreamDeckHello(pluginVersion: "test-plugin")))
    _ = try await client.receiveMessage()

    try await client.send([
        .command(StreamDeckCommandRequest(id: "slow", command: .panicBlank)),
        .command(StreamDeckCommandRequest(id: "fast", command: .clearCaptions))
    ])

    let slowResult = try await client.receiveMessage()
    let slowStatus = try await client.receiveMessage()
    let fastResult = try await client.receiveMessage()
    let fastStatus = try await client.receiveMessage()
    expect(
        slowResult == .commandResult(StreamDeckCommandResult(id: "slow", accepted: true)),
        "first command result should be sent before later command result even if its handler suspends"
    )
    expect(
        slowStatus == .status(StreamDeckStatusMessage(status: testStatusSnapshot(segmentCount: 2))),
        "first command status should be sent before later command result"
    )
    expect(
        fastResult == .commandResult(StreamDeckCommandResult(id: "fast", accepted: true)),
        "second command result should follow first command status"
    )
    expect(
        fastStatus == .status(StreamDeckStatusMessage(status: testStatusSnapshot(segmentCount: 3))),
        "second command should receive its fresh status last"
    )
    try await server.stop()
}

private func testServerRejectsWrongPathOrProtocol() async throws {
    let (rootURL, store) = temporaryDiscoveryStore()
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let server = StreamDeckControlServer(
        discoveryStore: store,
        commandHandler: { request in StreamDeckCommandResult(id: request.id, accepted: true) },
        statusProvider: { testStatusSnapshot() }
    )
    try await server.start()

    guard let port = try store.read()?.port else {
        expect(false, "server should publish a discovery port before rejection tests")
        return
    }

    let wrongPathResult = try await TestWebSocketClient().connectForUpgradeResult(port: port, path: "/wrong")
    guard case .rejected(let statusLine) = wrongPathResult else {
        expect(false, "server should reject websocket upgrades on the wrong path")
        return
    }
    expect(statusLine.contains(" 400 ") || statusLine.contains(" 404 "), "wrong-path upgrade should receive a non-101 HTTP rejection")

    let wrongProtocolClient = TestWebSocketClient()
    try await wrongProtocolClient.connect(port: port)
    defer { Task { await wrongProtocolClient.close() } }
    try await wrongProtocolClient.send(.hello(StreamDeckHello(protocolVersion: streamDeckProtocolVersion + 1, pluginVersion: "test")))
    try await wrongProtocolClient.waitForClose()
    try await server.stop()
}

private func testServerRepliesToMaskedPingWithUnmaskedPongPayload() async throws {
    let (rootURL, store) = temporaryDiscoveryStore()
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let server = StreamDeckControlServer(
        discoveryStore: store,
        commandHandler: { request in StreamDeckCommandResult(id: request.id, accepted: true) },
        statusProvider: { testStatusSnapshot() }
    )
    try await server.start()

    guard let port = try store.read()?.port else {
        expect(false, "server should publish a discovery port before ping test")
        return
    }
    let client = TestWebSocketClient()
    try await client.connect(port: port)
    defer { Task { await client.close() } }

    let payload: [UInt8] = Array("ping-payload".utf8)
    try client.sendMaskedPing(payload: payload)
    expect(try client.receivePongPayload() == payload, "masked ping should receive an unmasked pong payload")
    try await server.stop()
}

private func testServerRejectsFragmentedTextFramesForV1() async throws {
    let (rootURL, store) = temporaryDiscoveryStore()
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let diagnostics = DiagnosticsRecorder()
    let server = StreamDeckControlServer(
        discoveryStore: store,
        commandHandler: { request in StreamDeckCommandResult(id: request.id, accepted: true) },
        statusProvider: { testStatusSnapshot() },
        diagnostics: { message in Task { await diagnostics.append(message) } }
    )
    try await server.start()

    guard let port = try store.read()?.port else {
        expect(false, "server should publish a discovery port before fragmentation test")
        return
    }
    let client = TestWebSocketClient()
    try await client.connect(port: port)
    defer { Task { await client.close() } }
    try client.sendFragmentedText(#"{"type":"hello","#, #""protocolVersion":1,"pluginVersion":"test"}"#)
    try await client.waitForClose()
    let diagnosticValues = await diagnostics.values()
    expect(
        diagnosticValues.contains("streamdeck.websocket.reject.fragmented_frame"),
        "v1 fragmented text frames should be explicitly rejected with a safe diagnostic"
    )
    try await server.stop()
}

private func testConcurrentStartAndStopConvergesAndRemovesDiscovery() async throws {
    let (rootURL, store) = temporaryDiscoveryStore()
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let diagnostics = DiagnosticsRecorder()
    let server = StreamDeckControlServer(
        discoveryStore: store,
        commandHandler: { request in StreamDeckCommandResult(id: request.id, accepted: true) },
        statusProvider: { testStatusSnapshot() },
        diagnostics: { message in Task { await diagnostics.append(message) } }
    )

    async let firstStart: Void = server.start()
    async let secondStart: Void = server.start()
    _ = try await (firstStart, secondStart)
    try await server.stop()

    let starts = await diagnostics.values().filter { $0 == "streamdeck.server.started" }
    expect(starts.count == 1, "concurrent start calls should create exactly one listener")
    expect(try store.read() == nil, "stop after concurrent start should remove owned discovery")
}

private func testStopWhileStartIsInFlightConvergesWithoutOwnedDiscovery() async throws {
    let (rootURL, store) = temporaryDiscoveryStore()
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let server = StreamDeckControlServer(
        discoveryStore: store,
        commandHandler: { request in StreamDeckCommandResult(id: request.id, accepted: true) },
        statusProvider: { testStatusSnapshot() }
    )

    async let startResult: Void = server.start()
    async let stopResult: Void = server.stop()
    do {
        _ = try await (startResult, stopResult)
    } catch {
        // The start side may observe the stop race, but cleanup still must converge.
    }
    try await server.stop()
    expect(try store.read() == nil, "stop racing an in-flight start should not leave owned discovery")
}

private func testPublishStatusBroadcastsToEstablishedClient() async throws {
    let (rootURL, store) = temporaryDiscoveryStore()
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let statusCounter = StatusCounter()
    let server = StreamDeckControlServer(
        discoveryStore: store,
        commandHandler: { request in StreamDeckCommandResult(id: request.id, accepted: true) },
        statusProvider: {
            await statusCounter.nextSnapshot()
        }
    )
    try await server.start()

    guard let port = try store.read()?.port else {
        expect(false, "server should publish a discovery port before broadcast test")
        return
    }
    let client = TestWebSocketClient()
    try await client.connect(port: port)
    defer { Task { await client.close() } }
    try await client.send(.hello(StreamDeckHello(pluginVersion: "test-plugin")))
    _ = try await client.receiveMessage()

    await server.publishStatus()

    let broadcast = try await client.receiveMessage()
    expect(
        broadcast == .status(StreamDeckStatusMessage(status: testStatusSnapshot(segmentCount: 2))),
        "publishStatus should broadcast a fresh complete status to handshaken clients"
    )
    try await server.stop()
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
    try await testServerPublishesDynamicLoopbackDiscoveryAndRemovesOwnedRecordOnStop()
    try await testServerHelloCommandResultAndStatusFlow()
    try await testServerProcessesBackToBackHelloAndCommandInOrder()
    try await testServerPreservesMultipleCommandResultStatusOrderWhenHandlersSuspend()
    try await testServerRejectsWrongPathOrProtocol()
    try await testServerRepliesToMaskedPingWithUnmaskedPongPayload()
    try await testServerRejectsFragmentedTextFramesForV1()
    try await testConcurrentStartAndStopConvergesAndRemovesDiscovery()
    try await testStopWhileStartIsInFlightConvergesWithoutOwnedDiscovery()
    try await testPublishStatusBroadcastsToEstablishedClient()
    print("PASS: Stream Deck remote control protocol")
} catch {
    fputs("FAIL: Stream Deck remote control protocol: \(error)\n", stderr)
    exit(1)
}
