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
        relevanceBucket: 4,
        lastModifiedAt: Date(timeIntervalSince1970: 1_710_000_500),
        lastNoteID: "note-123"
    )

    let token = try DiscoveryCursorCoder.encode(cursor)
    let decoded = try DiscoveryCursorCoder.decode(token)

    #expect(decoded == cursor)
    #expect(!token.contains("="))
    #expect(!token.contains("+"))
    #expect(!token.contains("/"))
}

@Test
func discoveryCursorCoderDecodesLegacyVerboseToken() throws {
    let legacyToken = "eyJmaWx0ZXJLZXkiOiIzLXJlc291cmNlcy93b3JrZmxvd3MiLCJraW5kIjoibm90ZXNfYnlfdGFnIiwibGFzdE1vZGlmaWVkQXQiOiIyMDI2LTAyLTI3VDE5OjA2OjAxWiIsImxhc3ROb3RlSUQiOiJCODQ2RDMzQy1DODhELTQzQ0EtQjQ1MS1BQ0JEOEUwN0NBQkUiLCJsb2NhdGlvbiI6Im5vdGVzIiwidmVyc2lvbiI6MX0="
    let cursor = try DiscoveryCursorCoder.decode(legacyToken)

    #expect(cursor.version == 1)
    #expect(cursor.kind == .notesByTag)
    #expect(cursor.location == .notes)
    #expect(cursor.relevanceBucket == 0)
    #expect(cursor.filterKey == "3-resources/workflows")
    #expect(cursor.lastNoteID == "B846D33C-C88D-43CA-B451-ACBD8E07CABE")
}

@Test
func backupCursorCoderRoundTripsFilterScopedCursor() throws {
    let cursor = BackupListCursor(
        noteID: "note-123",
        filterKey: "captured-at-range",
        lastCapturedAt: Date(timeIntervalSince1970: 1_710_000_500),
        lastSnapshotID: "snapshot-123"
    )

    let token = try BackupListCursorCoder.encode(cursor)
    let decoded = try BackupListCursorCoder.decode(token)

    #expect(decoded == cursor)
    #expect(!token.contains("="))
    #expect(!token.contains("+"))
    #expect(!token.contains("/"))
}
