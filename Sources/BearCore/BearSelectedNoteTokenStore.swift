import Foundation

public enum BearSelectedNoteTokenSource: String, Codable, Hashable, Sendable {
    case config
}

public struct BearResolvedSelectedNoteToken: Hashable, Sendable {
    public let value: String
    public let source: BearSelectedNoteTokenSource

    public init(value: String, source: BearSelectedNoteTokenSource) {
        self.value = value
        self.source = source
    }
}

public struct BearSelectedNoteTokenStatus: Hashable, Sendable {
    public let tokenPresent: Bool
    public let effectiveSource: BearSelectedNoteTokenSource?

    public init(tokenPresent: Bool, effectiveSource: BearSelectedNoteTokenSource?) {
        self.tokenPresent = tokenPresent
        self.effectiveSource = effectiveSource
    }

    public var isConfigured: Bool {
        effectiveSource != nil
    }
}

public enum BearSelectedNoteTokenResolver {
    public static func configured(configuration: BearConfiguration) -> Bool {
        normalizedToken(configuration.token) != nil
    }

    public static func resolve(configuration: BearConfiguration) -> BearResolvedSelectedNoteToken? {
        guard let token = normalizedToken(configuration.token) else {
            return nil
        }

        return BearResolvedSelectedNoteToken(value: token, source: .config)
    }

    public static func status(configuration: BearConfiguration) -> BearSelectedNoteTokenStatus {
        let resolved = resolve(configuration: configuration)
        return BearSelectedNoteTokenStatus(
            tokenPresent: resolved != nil,
            effectiveSource: resolved?.source
        )
    }

    private static func normalizedToken(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
