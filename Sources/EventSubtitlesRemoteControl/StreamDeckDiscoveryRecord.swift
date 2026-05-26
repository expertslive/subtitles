import Foundation

public struct StreamDeckDiscoveryRecord: Codable, Equatable, Sendable {
    public let host: String
    public let port: Int
    public let protocolVersion: Int
    public let processID: Int32
    public let generatedAt: Date

    public init(
        host: String,
        port: Int,
        protocolVersion: Int = streamDeckProtocolVersion,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        generatedAt: Date = Date()
    ) {
        self.host = host
        self.port = port
        self.protocolVersion = protocolVersion
        self.processID = processID
        self.generatedAt = generatedAt
    }
}

public struct StreamDeckDiscoveryStore: Sendable {
    public let directoryURL: URL

    public init(
        directoryURL: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EventSubtitles", isDirectory: true)
    ) {
        self.directoryURL = directoryURL
    }

    public var recordURL: URL {
        directoryURL.appendingPathComponent("streamdeck-control.json")
    }

    public func write(_ record: StreamDeckDiscoveryRecord) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: recordURL, options: .atomic)
    }

    public func read() throws -> StreamDeckDiscoveryRecord? {
        guard FileManager.default.fileExists(atPath: recordURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: recordURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StreamDeckDiscoveryRecord.self, from: data)
    }

    public func removeIfOwned(by processID: Int32) throws {
        guard let record = try read(), record.processID == processID else {
            return
        }

        try FileManager.default.removeItem(at: recordURL)
    }
}
