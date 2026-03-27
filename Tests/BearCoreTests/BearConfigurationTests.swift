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
func configurationEncodingIncludesNullTokenPlaceholder() throws {
    let data = try BearJSON.makeEncoder().encode(BearConfiguration.default)
    let text = try #require(String(data: data, encoding: .utf8))

    #expect(text.contains("\"token\" : null"))
}
