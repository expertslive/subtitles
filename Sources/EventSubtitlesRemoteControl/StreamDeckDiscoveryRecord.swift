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
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.timestampString(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)

        var operationError: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: recordURL,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                operationError = error
            }
        }
        if let operationError {
            throw operationError
        }
        if let coordinationError {
            throw coordinationError
        }
    }

    public func read() throws -> StreamDeckDiscoveryRecord? {
        try Self.read(from: recordURL)
    }

    public func removeIfOwned(by processID: Int32) throws {
        var operationError: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: recordURL,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                guard let record = try Self.read(from: coordinatedURL),
                      record.processID == processID
                else {
                    return
                }
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                operationError = error
            }
        }
        if let operationError {
            throw operationError
        }
        if let coordinationError {
            throw coordinationError
        }
    }

    private static func read(from url: URL) throws -> StreamDeckDiscoveryRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = Self.date(from: value) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO-8601 date.")
                )
            }
            return date
        }
        return try decoder.decode(StreamDeckDiscoveryRecord.self, from: data)
    }

    private static func timestampString(from date: Date) -> String {
        let wholeSeconds = floor(date.timeIntervalSinceReferenceDate)
        let fraction = date.timeIntervalSinceReferenceDate - wholeSeconds
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let base = formatter.string(from: Date(timeIntervalSinceReferenceDate: wholeSeconds))
        guard fraction != 0 else {
            return base
        }

        let rawFraction = String(format: "%.17f", locale: Locale(identifier: "en_US_POSIX"), fraction)
        let digits = String(rawFraction.dropFirst(2)).replacingOccurrences(
            of: "0+$",
            with: "",
            options: .regularExpression
        )
        return base.replacingOccurrences(of: "Z", with: ".\(digits)Z")
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        guard let decimalPoint = value.lastIndex(of: ".") else {
            return formatter.date(from: value)
        }
        guard value.hasSuffix("Z") else {
            return nil
        }

        let fractionStart = value.index(after: decimalPoint)
        let fractionEnd = value.index(before: value.endIndex)
        guard fractionStart < fractionEnd else {
            return nil
        }
        let fractionalDigits = value[fractionStart..<fractionEnd]
        guard fractionalDigits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            return nil
        }

        let wholeSecondValue = String(value[..<decimalPoint]) + "Z"
        let fractionalValue = "0." + fractionalDigits
        guard let wholeSecondDate = formatter.date(from: wholeSecondValue),
              let fraction = TimeInterval(fractionalValue),
              fraction >= 0,
              fraction < 1
        else {
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: wholeSecondDate.timeIntervalSinceReferenceDate + fraction)
    }
}
