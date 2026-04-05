import BearCore
import Foundation
import Testing

@Test
func configurationIgnoresSelectedNoteTokenKey() throws {
    let data = Data(
        """
        {
          "token" : "  secret-token  "
        }
        """.utf8
    )

    let configuration = try JSONDecoder().decode(BearConfiguration.self, from: data)

    #expect(configuration == .default)
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

    #expect(configuration == .default)
}

@Test
func configurationEncodingOmitsLegacyTokenField() throws {
    let data = try BearJSON.makeEncoder().encode(BearConfiguration.default)
    let text = try #require(String(data: data, encoding: .utf8))

    #expect(text.contains("\"disabledTools\" : ["))
    #expect(text.contains("\"runtimeConfigurationGeneration\" : 0"))
    #expect(!text.contains("\"token\""))
}

@Test
func configurationDecodesAndNormalizesDisabledTools() throws {
    let data = Data(
        """
        {
          "disabledTools" : [
            "bear_add_tags",
            "bear_find_notes",
            "bear_add_tags"
          ]
        }
        """.utf8
    )

    let configuration = try JSONDecoder().decode(BearConfiguration.self, from: data)

    #expect(configuration.disabledTools == [.addTags, .findNotes])
    #expect(configuration.isToolEnabled(.getNotes))
    #expect(!configuration.isToolEnabled(.addTags))
}

@Test
func selectedNoteTokenResolverUsesTokenStore() throws {
    let tokenStore = InMemoryBearTokenStore(token: "keychain-token")

    #expect(BearSelectedNoteTokenResolver.configured(tokenStore: InMemoryBearTokenStore()) == false)
    #expect(BearSelectedNoteTokenResolver.configured(tokenStore: tokenStore) == true)

    let resolved = try BearSelectedNoteTokenResolver.resolve(tokenStore: tokenStore)
    let status = BearSelectedNoteTokenResolver.status(tokenStore: tokenStore)

    #expect(resolved?.value == "keychain-token")
    #expect(resolved?.source == .keychain)
    #expect(status.tokenPresent)
    #expect(status.effectiveSource == .keychain)
    #expect(status.accessErrorDescription == nil)
}

@Test
func keychainTokenStoreRoundTripsWhenExplicitlyEnabled() throws {
    guard ProcessInfo.processInfo.environment["URSUS_RUN_KEYCHAIN_TESTS"] == "1" else {
        return
    }

    let store = BearKeychainTokenStore(
        service: "com.aft.ursus.tests.\(UUID().uuidString)",
        account: "selected-note-api-token"
    )
    defer {
        try? store.deleteToken()
    }

    try store.saveToken("integration-token")
    #expect(try store.hasToken())
    #expect(try store.readToken() == "integration-token")

    try store.deleteToken()
    #expect(try store.readToken() == nil)
}
