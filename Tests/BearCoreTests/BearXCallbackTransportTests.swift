import BearCore
import BearXCallback
import Foundation
import GRDB
import Testing

@Test
func createRetriesThroughTransientSQLiteLockDuringReceiptPolling() async throws {
    let transport = BearXCallbackTransport(
        readStore: LockThenCreateReadStore(),
        urlOpener: { _ in }
    )

    let receipt = try await transport.create(
        CreateNoteRequest(
            title: "Locked Create",
            content: "Body",
            tags: [],
            presentation: BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: false)
        )
    )

    #expect(receipt.status == "created")
    #expect(receipt.noteID == "created-note")
}

private final class LockThenCreateReadStore: @unchecked Sendable, BearReadStore {
    private var didThrowLock = false

    func searchNotes(_ query: NoteSearchQuery) throws -> DiscoveryNoteBatch {
        DiscoveryNoteBatch(notes: [], hasMore: false)
    }
    func note(id: String) throws -> BearNote? { nil }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func notes(matchingAnyTags query: TagNotesQuery) throws -> DiscoveryNoteBatch {
        DiscoveryNoteBatch(notes: [], hasMore: false)
    }
    func listTags() throws -> [TagSummary] { [] }

    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] {
        if !didThrowLock {
            didThrowLock = true
            throw DatabaseError(resultCode: .SQLITE_BUSY, message: "database is locked")
        }

        return [
            BearNote(
                ref: NoteRef(identifier: "created-note"),
                revision: NoteRevision(version: 1, createdAt: Date(), modifiedAt: Date()),
                title: title,
                body: "Body",
                rawText: BearText.composeRawText(title: title, body: "Body"),
                tags: [],
                archived: false,
                trashed: false,
                encrypted: false
            ),
        ]
    }
}
