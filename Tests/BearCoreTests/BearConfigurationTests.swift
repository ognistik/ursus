import BearCore
import Foundation
import Testing

private final class InMemorySelectedNoteTokenStore: BearSelectedNoteTokenStore, @unchecked Sendable {
    var storedToken: String?
    var readError: Error?

    init(storedToken: String? = nil, readError: Error? = nil) {
        self.storedToken = storedToken
        self.readError = readError
    }

    func readToken() throws -> String? {
        if let readError {
            throw readError
        }
        return storedToken
    }

    func saveToken(_ token: String) throws {
        storedToken = token
    }

    func removeToken() throws {
        storedToken = nil
    }
}

@Test
func configurationDecodesTokenKeyAndNormalizesWhitespace() throws {
    let data = Data(
        """
        {
          "token" : "  secret-token  "
        }
        """.utf8
    )

    let configuration = try JSONDecoder().decode(BearConfiguration.self, from: data)

    #expect(configuration.token == "secret-token")
}

@Test
func configurationIgnoresLegacyAPITokenKey() throws {
    let data = Data(
        """
        {
          "apiToken" : "secret-token"
        }
        """.utf8
    )

    let configuration = try JSONDecoder().decode(BearConfiguration.self, from: data)

    #expect(configuration.token == nil)
}

@Test
func configurationEncodingIncludesNullTokenPlaceholder() throws {
    let data = try BearJSON.makeEncoder().encode(BearConfiguration.default)
    let text = try #require(String(data: data, encoding: .utf8))

    #expect(text.contains("\"selectedNoteTokenStoredInKeychain\" : false"))
    #expect(text.contains("\"token\" : null"))
}

@Test
func selectedNoteTokenConfiguredHintUsesLegacyTokenOrKeychainMetadata() {
    let configToken = BearConfiguration.default.updatingToken("legacy-token")
    let keychainHint = BearConfiguration.default.updatingSelectedNoteTokenStorage(storedInKeychain: true)

    #expect(BearSelectedNoteTokenResolver.configuredHint(configuration: .default) == false)
    #expect(BearSelectedNoteTokenResolver.configuredHint(configuration: configToken) == true)
    #expect(BearSelectedNoteTokenResolver.configuredHint(configuration: keychainHint) == true)
}

@Test
func selectedNoteTokenResolverPrefersKeychainOverLegacyConfig() throws {
    let configuration = BearConfiguration.default.updatingToken("legacy-token")
    let tokenStore = InMemorySelectedNoteTokenStore(storedToken: "keychain-token")

    let resolved = try BearSelectedNoteTokenResolver.resolve(
        configuration: configuration,
        tokenStore: tokenStore
    )

    #expect(resolved?.value == "keychain-token")
    #expect(resolved?.source == .keychain)
}

@Test
func selectedNoteTokenResolverFallsBackToLegacyConfigWhenKeychainIsEmpty() throws {
    let configuration = BearConfiguration.default.updatingToken("legacy-token")
    let tokenStore = InMemorySelectedNoteTokenStore()

    let resolved = try BearSelectedNoteTokenResolver.resolve(
        configuration: configuration,
        tokenStore: tokenStore
    )
    let status = BearSelectedNoteTokenResolver.status(
        configuration: configuration,
        tokenStore: tokenStore
    )

    #expect(resolved?.value == "legacy-token")
    #expect(resolved?.source == .legacyConfig)
    #expect(status.keychainTokenPresent == false)
    #expect(status.legacyConfigTokenPresent == true)
    #expect(status.effectiveSource == .legacyConfig)
}

@Test
func selectedNoteTokenStatusKeepsLegacyFallbackWhenKeychainReadFails() {
    let configuration = BearConfiguration.default.updatingToken("legacy-token")
    let tokenStore = InMemorySelectedNoteTokenStore(
        readError: BearError.configuration("Keychain locked")
    )

    let status = BearSelectedNoteTokenResolver.status(
        configuration: configuration,
        tokenStore: tokenStore
    )

    #expect(status.isConfigured)
    #expect(status.effectiveSource == .legacyConfig)
    #expect(status.keychainAccessError == "Keychain locked")
}

@Test
func selectedNoteTokenStatusCanUseConfigHintWithoutReadingKeychain() {
    let configuration = BearConfiguration.default.updatingSelectedNoteTokenStorage(storedInKeychain: true)
    let tokenStore = InMemorySelectedNoteTokenStore(
        readError: BearError.configuration("Keychain should not be touched")
    )

    let status = BearSelectedNoteTokenResolver.status(
        configuration: configuration,
        tokenStore: tokenStore,
        allowSecureRead: false
    )

    #expect(status.isConfigured)
    #expect(status.keychainTokenPresent)
    #expect(status.effectiveSource == .keychain)
    #expect(status.keychainAccessError == nil)
    #expect(status.keychainStatusDerivedFromHint)
}
