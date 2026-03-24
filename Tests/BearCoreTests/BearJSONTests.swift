import BearCore
import Foundation
import Testing

@Test
func encoderDoesNotEscapeForwardSlashes() throws {
    struct Payload: Encodable {
        let url: String
    }

    let data = try BearJSON.makeEncoder().encode(Payload(url: "bear://x-callback-url/open-note?id=123"))
    let text = try #require(String(data: data, encoding: .utf8))

    #expect(text.contains("\"url\" : \"bear://x-callback-url/open-note?id=123\""))
    #expect(!text.contains("\\/"))
}
