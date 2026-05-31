import Foundation

public enum UpdateCheckMode: Equatable, Sendable {
    case launch
    case manual

    public var timeout: TimeInterval {
        switch self {
        case .launch:
            return 3
        case .manual:
            return 5
        }
    }
}

public enum UpdateCheckFailureReason: Error, Equatable, Sendable {
    case networkUnavailable
    case noStableReleaseFound
    case httpStatus(Int)
    case invalidRemoteVersion
    case invalidLocalVersion

    public var displayText: String {
        switch self {
        case .networkUnavailable:
            return "Network unavailable or GitHub could not be reached."
        case .noStableReleaseFound:
            return "No stable release was found."
        case let .httpStatus(status):
            return "GitHub returned HTTP \(status)."
        case .invalidRemoteVersion:
            return "Release VERSION was not parseable."
        case .invalidLocalVersion:
            return "Installed app version was not parseable."
        }
    }
}

public enum AppUpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(currentVersion: String, latestVersion: String)
    case failed(currentVersion: String, reason: UpdateCheckFailureReason)
}

public enum AppUpdateConstants {
    public static let latestVersionURL = URL(
        string: "https://github.com/expertslive/subtitles/releases/latest/download/VERSION"
    )!
    public static let latestReleaseURL = URL(string: "https://github.com/expertslive/subtitles/releases/latest")!
    public static let installCommand =
        "curl -fsSL https://github.com/expertslive/subtitles/releases/latest/download/install.sh | bash"
}

public protocol VersionTextFetching: Sendable {
    func fetchVersionText(from url: URL, timeout: TimeInterval) async -> Result<String, UpdateCheckFailureReason>
}

public struct URLSessionVersionTextFetcher: VersionTextFetching {
    public init() {}

    public func fetchVersionText(from url: URL, timeout: TimeInterval) async -> Result<String, UpdateCheckFailureReason> {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.networkUnavailable)
            }
            guard httpResponse.statusCode != 404 else {
                return .failure(.noStableReleaseFound)
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                return .failure(.httpStatus(httpResponse.statusCode))
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(.invalidRemoteVersion)
            }
            return .success(text)
        } catch {
            return .failure(.networkUnavailable)
        }
    }
}

public struct UpdateChecker: Sendable {
    private let fetcher: VersionTextFetching

    public init(fetcher: VersionTextFetching = URLSessionVersionTextFetcher()) {
        self.fetcher = fetcher
    }

    public func check(
        currentVersionText: String,
        mode: UpdateCheckMode,
        latestVersionURL: URL = AppUpdateConstants.latestVersionURL
    ) async -> AppUpdateStatus {
        let normalizedCurrent = Self.normalizedVersionText(currentVersionText)
        guard let current = SemanticVersion(normalizedCurrent) else {
            return .failed(
                currentVersion: normalizedCurrent.isEmpty ? currentVersionText : normalizedCurrent,
                reason: .invalidLocalVersion
            )
        }

        let result = await fetcher.fetchVersionText(from: latestVersionURL, timeout: mode.timeout)
        switch result {
        case let .failure(reason):
            if mode == .launch {
                return .idle
            }
            return .failed(currentVersion: current.stringValue, reason: reason)

        case let .success(text):
            let normalizedLatest = Self.normalizedVersionText(text)
            guard let latest = SemanticVersion(normalizedLatest) else {
                if mode == .launch {
                    return .idle
                }
                return .failed(currentVersion: current.stringValue, reason: .invalidRemoteVersion)
            }

            if latest > current {
                return .available(currentVersion: current.stringValue, latestVersion: latest.stringValue)
            }
            return .upToDate(currentVersion: current.stringValue)
        }
    }

    public static func normalizedVersionText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
