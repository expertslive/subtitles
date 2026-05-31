import Foundation

public struct SemanticVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init?(_ rawValue: String) {
        let normalized = Self.normalized(rawValue)
        guard !normalized.isEmpty else { return nil }

        let coreAndSuffix = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard coreAndSuffix.count == 1 || coreAndSuffix.count == 2 else { return nil }

        let coreParts = coreAndSuffix[0].split(separator: ".", omittingEmptySubsequences: false)
        guard coreParts.count == 3,
              let major = Self.parseNumericPart(coreParts[0]),
              let minor = Self.parseNumericPart(coreParts[1]),
              let patch = Self.parseNumericPart(coreParts[2]) else {
            return nil
        }

        let prerelease: String?
        if coreAndSuffix.count == 2 {
            let suffix = String(coreAndSuffix[1])
            guard Self.isValidPrerelease(suffix) else { return nil }
            prerelease = suffix
        } else {
            prerelease = nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public var stringValue: String {
        let core = "\(major).\(minor).\(patch)"
        if let prerelease {
            return "\(core)-\(prerelease)"
        }
        return core
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case let (.some(left), .some(right)):
            return comparePrerelease(left, right) == .orderedAscending
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseNumericPart(_ value: Substring) -> Int? {
        guard !value.isEmpty, value.allSatisfy(\.isNumber) else { return nil }
        return Int(value)
    }

    private static func isValidPrerelease(_ value: String) -> Bool {
        let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return false }
        return identifiers.allSatisfy { identifier in
            !identifier.isEmpty && identifier.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-"
            }
        }
    }

    private static func comparePrerelease(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftIdentifiers = lhs.split(separator: ".", omittingEmptySubsequences: false)
        let rightIdentifiers = rhs.split(separator: ".", omittingEmptySubsequences: false)

        for (left, right) in zip(leftIdentifiers, rightIdentifiers) {
            let comparison = comparePrereleaseIdentifier(left, right)
            if comparison != .orderedSame {
                return comparison
            }
        }

        if leftIdentifiers.count == rightIdentifiers.count {
            return .orderedSame
        }
        return leftIdentifiers.count < rightIdentifiers.count ? .orderedAscending : .orderedDescending
    }

    private static func comparePrereleaseIdentifier(_ lhs: Substring, _ rhs: Substring) -> ComparisonResult {
        let leftNumber = parseNumericPart(lhs)
        let rightNumber = parseNumericPart(rhs)

        switch (leftNumber, rightNumber) {
        case let (.some(left), .some(right)):
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case (.some, nil):
            return .orderedAscending
        case (nil, .some):
            return .orderedDescending
        case (nil, nil):
            if lhs == rhs { return .orderedSame }
            return String(lhs) < String(rhs) ? .orderedAscending : .orderedDescending
        }
    }
}
