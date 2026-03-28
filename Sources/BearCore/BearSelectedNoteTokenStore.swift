import Foundation
import Security

public protocol BearSelectedNoteTokenStore: Sendable {
    func readToken() throws -> String?
    func saveToken(_ token: String) throws
    func removeToken() throws
}

public enum BearSelectedNoteTokenSource: String, Codable, Hashable, Sendable {
    case keychain
    case legacyConfig
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
    public let keychainTokenPresent: Bool
    public let legacyConfigTokenPresent: Bool
    public let effectiveSource: BearSelectedNoteTokenSource?
    public let keychainAccessError: String?

    public init(
        keychainTokenPresent: Bool,
        legacyConfigTokenPresent: Bool,
        effectiveSource: BearSelectedNoteTokenSource?,
        keychainAccessError: String?
    ) {
        self.keychainTokenPresent = keychainTokenPresent
        self.legacyConfigTokenPresent = legacyConfigTokenPresent
        self.effectiveSource = effectiveSource
        self.keychainAccessError = keychainAccessError
    }

    public var isConfigured: Bool {
        effectiveSource != nil
    }
}

public final class BearKeychainSelectedNoteTokenStore: BearSelectedNoteTokenStore {
    public static let defaultService = "com.ognistik.bear-mcp"
    public static let defaultAccount = "selected-note-token"

    private let service: String
    private let account: String

    public init(
        service: String = defaultService,
        account: String = defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    public func readToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard
                let data = item as? Data,
                let token = Self.normalizedToken(String(data: data, encoding: .utf8))
            else {
                throw BearError.configuration("Bear token data in Keychain is unreadable.")
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw keychainError(status, action: "read")
        }
    }

    public func saveToken(_ token: String) throws {
        guard let normalized = Self.normalizedToken(token) else {
            throw BearError.invalidInput("Enter a Bear API token before saving.")
        }

        let data = Data(normalized.utf8)
        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw keychainError(addStatus, action: "save")
            }
        default:
            throw keychainError(updateStatus, action: "save")
        }
    }

    public func removeToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw keychainError(status, action: "remove")
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func keychainError(_ status: OSStatus, action: String) -> BearError {
        let fallbackMessage = "OSStatus \(status)"
        let systemMessage = SecCopyErrorMessageString(status, nil) as String? ?? fallbackMessage
        return .configuration("Failed to \(action) the Bear API token in Keychain: \(systemMessage)")
    }

    private static func normalizedToken(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum BearSelectedNoteTokenResolver {
    public static func configuredHint(configuration: BearConfiguration) -> Bool {
        normalizedToken(configuration.token) != nil || configuration.selectedNoteTokenStoredInKeychain
    }

    public static func resolve(
        configuration: BearConfiguration,
        tokenStore: any BearSelectedNoteTokenStore = BearKeychainSelectedNoteTokenStore()
    ) throws -> BearResolvedSelectedNoteToken? {
        if let token = try tokenStore.readToken() {
            return BearResolvedSelectedNoteToken(value: token, source: .keychain)
        }

        if let token = normalizedToken(configuration.token) {
            return BearResolvedSelectedNoteToken(value: token, source: .legacyConfig)
        }

        return nil
    }

    public static func status(
        configuration: BearConfiguration,
        tokenStore: any BearSelectedNoteTokenStore = BearKeychainSelectedNoteTokenStore()
    ) -> BearSelectedNoteTokenStatus {
        let legacyConfigTokenPresent = normalizedToken(configuration.token) != nil

        do {
            let keychainTokenPresent = try tokenStore.readToken() != nil
            let effectiveSource: BearSelectedNoteTokenSource? = if keychainTokenPresent {
                .keychain
            } else if legacyConfigTokenPresent {
                .legacyConfig
            } else {
                nil
            }

            return BearSelectedNoteTokenStatus(
                keychainTokenPresent: keychainTokenPresent,
                legacyConfigTokenPresent: legacyConfigTokenPresent,
                effectiveSource: effectiveSource,
                keychainAccessError: nil
            )
        } catch {
            let effectiveSource: BearSelectedNoteTokenSource? = legacyConfigTokenPresent ? .legacyConfig : nil
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)

            return BearSelectedNoteTokenStatus(
                keychainTokenPresent: false,
                legacyConfigTokenPresent: legacyConfigTokenPresent,
                effectiveSource: effectiveSource,
                keychainAccessError: message
            )
        }
    }

    private static func normalizedToken(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
