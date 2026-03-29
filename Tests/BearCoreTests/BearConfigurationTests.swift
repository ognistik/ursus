import BearCore
import Foundation
import Testing

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
func configurationEncodingOmitsMissingLegacyTokenField() throws {
    let data = try BearJSON.makeEncoder().encode(BearConfiguration.default)
    let text = try #require(String(data: data, encoding: .utf8))

    #expect(text.contains("\"disabledTools\" : ["))
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
func selectedNoteTokenResolverUsesConfigOnly() {
    let configuration = BearConfiguration.default.updatingToken("legacy-token")

    #expect(BearSelectedNoteTokenResolver.configured(configuration: .default) == false)
    #expect(BearSelectedNoteTokenResolver.configured(configuration: configuration) == true)

    let resolved = BearSelectedNoteTokenResolver.resolve(configuration: configuration)
    let status = BearSelectedNoteTokenResolver.status(configuration: configuration)

    #expect(resolved?.value == "legacy-token")
    #expect(resolved?.source == .config)
    #expect(status.tokenPresent)
    #expect(status.effectiveSource == .config)
}
