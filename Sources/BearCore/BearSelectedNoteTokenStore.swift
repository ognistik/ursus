import Foundation
import Security

public protocol BearTokenStore: Sendable {
    func readToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
    func hasToken() throws -> Bool
}

public extension BearTokenStore {
    func hasToken() throws -> Bool {
        try readToken() != nil
    }
}

public struct BearKeychainTokenStore: BearTokenStore, Hashable, Sendable {
    public static let selectedNoteDefault = BearKeychainTokenStore(
        service: "com.aft.ursus.bear-token",
        account: "selected-note-api-token"
    )

    public let service: String
    public let account: String
    public let label: String

    public init(
        service: String,
        account: String,
        label: String = "Ursus Bear Token"
    ) {
        self.service = service
        self.account = account
        self.label = label
    }

    public func readToken() throws -> String? {
        var query = itemQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw BearError.configuration("Stored Bear token could not be decoded from macOS Keychain.")
            }

            guard let token = String(data: data, encoding: .utf8) else {
                throw BearError.configuration("Stored Bear token is not valid UTF-8 text.")
            }

            return Self.normalizedToken(token)
        case errSecItemNotFound:
            return nil
        default:
            throw keychainError("read", status: status)
        }
    }

    public func saveToken(_ token: String) throws {
        guard let normalizedToken = Self.normalizedToken(token) else {
            throw BearError.invalidInput("Bear API token cannot be empty.")
        }

        let tokenData = Data(normalizedToken.utf8)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: tokenData,
            kSecAttrLabel as String: label,
        ]

        let updateStatus = SecItemUpdate(itemQuery() as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = itemQuery()
            addQuery[kSecValueData as String] = tokenData
            addQuery[kSecAttrLabel as String] = label
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw keychainError("save", status: addStatus)
            }
        default:
            throw keychainError("save", status: updateStatus)
        }
    }

    public func deleteToken() throws {
        let status = SecItemDelete(itemQuery() as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw keychainError("delete", status: status)
        }
    }

    private func itemQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func keychainError(_ operation: String, status: OSStatus) -> BearError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return BearError.configuration("Failed to \(operation) the Bear API token in macOS Keychain. \(message)")
    }

    private static func normalizedToken(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum BearSelectedNoteTokenSource: String, Codable, Hashable, Sendable {
    case keychain
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
    public let accessErrorDescription: String?

    public init(
        tokenPresent: Bool,
        effectiveSource: BearSelectedNoteTokenSource?,
        accessErrorDescription: String? = nil
    ) {
        self.tokenPresent = tokenPresent
        self.effectiveSource = effectiveSource
        self.accessErrorDescription = accessErrorDescription
    }

    public var isConfigured: Bool {
        effectiveSource != nil
    }
}

public enum BearSelectedNoteTokenResolver {
    public static func configured(
        tokenStore: any BearTokenStore = BearKeychainTokenStore.selectedNoteDefault
    ) -> Bool {
        (try? tokenStore.hasToken()) ?? false
    }

    public static func resolve(
        tokenStore: any BearTokenStore = BearKeychainTokenStore.selectedNoteDefault
    ) throws -> BearResolvedSelectedNoteToken? {
        guard let token = try tokenStore.readToken() else {
            return nil
        }

        return BearResolvedSelectedNoteToken(value: token, source: .keychain)
    }

    public static func status(
        tokenStore: any BearTokenStore = BearKeychainTokenStore.selectedNoteDefault
    ) -> BearSelectedNoteTokenStatus {
        do {
            let resolved = try resolve(tokenStore: tokenStore)
            return BearSelectedNoteTokenStatus(
                tokenPresent: resolved != nil,
                effectiveSource: resolved?.source
            )
        } catch {
            return BearSelectedNoteTokenStatus(
                tokenPresent: false,
                effectiveSource: nil,
                accessErrorDescription: localizedMessage(for: error)
            )
        }
    }

    private static func localizedMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }
}
