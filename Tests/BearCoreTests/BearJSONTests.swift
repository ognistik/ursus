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

@Test
func discoveryCursorCoderRoundTrips() throws {
    let cursor = DiscoveryCursor(
        kind: .notesByTag,
        location: .archive,
        filterKey: "project",
        lastModifiedAt: Date(timeIntervalSince1970: 1_710_000_500),
        lastNoteID: "note-123"
    )

    let token = try DiscoveryCursorCoder.encode(cursor)
    let decoded = try DiscoveryCursorCoder.decode(token)

    #expect(decoded == cursor)
}
