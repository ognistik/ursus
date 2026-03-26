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

@Test
func replaceAllTreatsModifiedNoteAsUpdatedEvenWhenVersionStaysTheSame() async throws {
    let readStore = MutableTransportReadStore(
        note: makeNote(
            id: "note-1",
            title: "Example",
            version: 3,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: "Before"
        )
    )
    let transport = BearXCallbackTransport(
        readStore: readStore,
        urlOpener: { _ in
            readStore.replaceRawText(
                noteID: "note-1",
                rawText: BearText.composeRawText(title: "Example", body: "After"),
                preserveVersion: true
            )
        }
    )

    let receipt = try await transport.replaceAll(
        noteID: "note-1",
        fullText: BearText.composeRawText(title: "Example", body: "After"),
        presentation: BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: false)
    )

    #expect(receipt.status == "updated")
}

@Test
func addFileTreatsAttachmentCountChangeAsUpdatedEvenWhenNoteMetadataStaysTheSame() async throws {
    let readStore = MutableTransportReadStore(
        note: makeNote(
            id: "note-1",
            title: "Example",
            version: 3,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: "Before"
        )
    )
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
    try "payload".write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let transport = BearXCallbackTransport(
        readStore: readStore,
        urlOpener: { _ in
            readStore.addAttachment(noteID: "note-1", filename: fileURL.lastPathComponent)
        }
    )

    let receipt = try await transport.addFile(
        AddFileRequest(
            noteID: "note-1",
            filePath: fileURL.path,
            position: .bottom,
            presentation: BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: false),
            expectedVersion: nil
        )
    )

    #expect(receipt.status == "updated")
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

private final class MutableTransportReadStore: @unchecked Sendable, BearReadStore {
    private let lock = NSLock()
    private var note: BearNote
    private var storedAttachments: [NoteAttachment]

    init(note: BearNote, attachments: [NoteAttachment] = []) {
        self.note = note
        self.storedAttachments = attachments
    }

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }

    func note(id: String) throws -> BearNote? {
        lock.lock()
        defer { lock.unlock() }
        return note.ref.identifier == id ? note : nil
    }

    func attachments(noteID: String) throws -> [NoteAttachment] {
        lock.lock()
        defer { lock.unlock() }
        guard note.ref.identifier == noteID else {
            return []
        }
        return storedAttachments
    }

    func replaceRawText(noteID: String, rawText: String, preserveVersion: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard note.ref.identifier == noteID else {
            return
        }

        note = BearNote(
            ref: note.ref,
            revision: NoteRevision(
                version: preserveVersion ? note.revision.version : note.revision.version + 1,
                createdAt: note.revision.createdAt,
                modifiedAt: note.revision.modifiedAt.addingTimeInterval(1)
            ),
            title: note.title,
            body: parseBody(rawText),
            rawText: rawText,
            tags: note.tags,
            archived: note.archived,
            trashed: note.trashed,
            encrypted: note.encrypted
        )
    }

    func addAttachment(noteID: String, filename: String) {
        lock.lock()
        defer { lock.unlock() }
        guard note.ref.identifier == noteID else {
            return
        }

        storedAttachments.append(
            NoteAttachment(
                attachmentID: UUID().uuidString,
                filename: filename,
                fileExtension: URL(fileURLWithPath: filename).pathExtension,
                searchText: nil
            )
        )
    }

    private func parseBody(_ rawText: String) -> String {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard let firstNewline = normalized.firstIndex(of: "\n") else {
            return ""
        }

        return String(normalized[normalized.index(after: firstNewline)...]).trimmingCharacters(in: .newlines)
    }
}

private actor ActivationRecordingOpener {
    private(set) var activations: [Bool] = []

    func record(url _: URL, activates: Bool) async throws {
        activations.append(activates)
    }
}

private func makeNote(
    id: String,
    title: String,
    archived: Bool = false,
    version: Int = 1,
    modifiedAt: Date = Date(),
    body: String = "Body"
) -> BearNote {
    BearNote(
        ref: NoteRef(identifier: id),
        revision: NoteRevision(version: version, createdAt: Date(), modifiedAt: modifiedAt),
        title: title,
        body: body,
        rawText: BearText.composeRawText(title: title, body: body),
        tags: [],
        archived: archived,
        trashed: false,
        encrypted: false
    )
}
