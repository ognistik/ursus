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

@Test
func createActivatesBearOnlyWhenTheCreatedNoteWillOpen() async throws {
    let opener = ActivationRecordingOpener()
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: makeNote(id: "created-note", title: "Created"), tags: []),
        urlOpenerWithActivation: opener.record
    )

    _ = try await transport.create(
        CreateNoteRequest(
            title: "Closed",
            content: "Body",
            tags: [],
            presentation: BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: false)
        )
    )
    _ = try await transport.create(
        CreateNoteRequest(
            title: "Opened",
            content: "Body",
            tags: [],
            presentation: BearPresentationOptions(openNote: true, newWindow: false, showWindow: true, edit: false)
        )
    )

    #expect(await opener.activations == [false, true])
}

@Test
func openNoteActivatesBear() async throws {
    let opener = ActivationRecordingOpener()
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: makeNote(id: "note-1", title: "Opened"), tags: []),
        urlOpenerWithActivation: opener.record
    )

    _ = try await transport.open(
        OpenNoteRequest(
            noteID: "note-1",
            presentation: BearPresentationOptions(openNote: true, newWindow: false, showWindow: true, edit: false)
        )
    )

    #expect(await opener.activations == [true])
}

@Test
func openTagActivatesBear() async throws {
    let opener = ActivationRecordingOpener()
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: nil, tags: []),
        urlOpenerWithActivation: opener.record
    )

    _ = try await transport.openTag(OpenTagRequest(tag: "projects"))

    #expect(await opener.activations == [true])
}

@Test
func renameTagStaysBackgroundedEvenWhenShowWindowIsTrue() async throws {
    let opener = ActivationRecordingOpener()
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: nil, tags: [TagSummary(name: "done", identifier: nil, noteCount: 1)]),
        urlOpenerWithActivation: opener.record
    )

    _ = try await transport.renameTag(
        RenameTagRequest(name: "todo", newName: "done", showWindow: true)
    )

    #expect(await opener.activations == [false])
}

@Test
func archiveStaysBackgroundedEvenWhenShowWindowIsTrue() async throws {
    let opener = ActivationRecordingOpener()
    let transport = BearXCallbackTransport(
        readStore: StaticReadStore(note: makeNote(id: "note-1", title: "Archived", archived: true), tags: []),
        urlOpenerWithActivation: opener.record
    )

    _ = try await transport.archive(noteID: "note-1", showWindow: true)

    #expect(await opener.activations == [false])
}

private final class LockThenCreateReadStore: @unchecked Sendable, BearReadStore {
    private var didThrowLock = false

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func note(id: String) throws -> BearNote? { nil }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }

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

private struct StaticReadStore: BearReadStore {
    let note: BearNote?
    let tags: [TagSummary]

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }

    func note(id: String) throws -> BearNote? {
        guard note?.ref.identifier == id else {
            return nil
        }
        return note
    }

    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }

    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] {
        tags
    }

    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] {
        guard let note else {
            return []
        }
        return [note]
    }
}

private actor ActivationRecordingOpener {
    private(set) var activations: [Bool] = []

    func record(url _: URL, activates: Bool) async throws {
        activations.append(activates)
    }
}

private func makeNote(id: String, title: String, archived: Bool = false) -> BearNote {
    BearNote(
        ref: NoteRef(identifier: id),
        revision: NoteRevision(version: 1, createdAt: Date(), modifiedAt: Date()),
        title: title,
        body: "Body",
        rawText: BearText.composeRawText(title: title, body: "Body"),
        tags: [],
        archived: archived,
        trashed: false,
        encrypted: false
    )
}
