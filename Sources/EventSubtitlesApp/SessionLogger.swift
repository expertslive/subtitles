import Foundation
import os

/// Writes a per-session `app.log` plus emits to the unified system log.
/// Append-only, single serial queue — never blocks the caller.
final class SessionLogger: @unchecked Sendable {
    private let queue = DispatchQueue(label: "session.logger", qos: .utility)
    private let osLog = Logger(subsystem: "com.eventsubtitles.app", category: "session")
    private var handle: FileHandle?
    private var url: URL?

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func open(at directory: URL) {
        let fileURL = directory.appendingPathComponent("app.log")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let opened = try? FileHandle(forWritingTo: fileURL)
        queue.async { [weak self] in
            self?.handle = opened
            self?.url = fileURL
        }
    }

    func close() {
        queue.async { [weak self] in
            try? self?.handle?.close()
            self?.handle = nil
            self?.url = nil
        }
    }

    func info(_ message: String, file: String = #fileID, line: Int = #line) {
        write(level: "INFO", message: message, file: file, line: line)
        osLog.info("\(message, privacy: .public)")
    }

    func warn(_ message: String, file: String = #fileID, line: Int = #line) {
        write(level: "WARN", message: message, file: file, line: line)
        osLog.warning("\(message, privacy: .public)")
    }

    func error(_ message: String, file: String = #fileID, line: Int = #line) {
        write(level: "ERROR", message: message, file: file, line: line)
        osLog.error("\(message, privacy: .public)")
    }

    private func write(level: String, message: String, file: String, line: Int) {
        let stamp = Self.isoFormatter.string(from: Date())
        let entry = "\(stamp) [\(level)] \(file):\(line) \(message)\n"
        let data = Data(entry.utf8)
        queue.async { [weak self] in
            self?.handle?.write(data)
        }
    }
}
