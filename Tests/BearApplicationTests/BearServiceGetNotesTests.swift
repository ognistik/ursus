import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func getNotesResolvesExactIDBeforeTitleAndDeduplicatesResults() throws {
    let exactIDMatch = makeFetchedSourceNote(
        id: "shared-selector",
        title: "Exact Match",
        body: "ID body",
        tags: ["0-inbox"],
        archived: false
    )
    let titleMatch = makeFetchedSourceNote(
        id: "title-only",
        title: "shared-selector",
        body: "Title body",
        tags: ["0-inbox"],
        archived: false
    )
    let readStore = GetNotesReadStore(
        noteByID: ["shared-selector": exactIDMatch],
        notesByTitleAndLocation: [
            .init(title: "Exact Match", location: .notes): [exactIDMatch],
            .init(title: "shared-selector", location: .notes): [titleMatch],
        ]
    )
    let service = BearService(
        configuration: makeGetNotesConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: GetNotesSilentWriteTransport(),
        logger: Logger(label: "BearServiceGetNotesTests")
    )

    let notes = try service.getNotes(selectors: ["shared-selector", "exact match"], location: .notes)

    #expect(notes.count == 1)
    #expect(notes.first?.noteID == "shared-selector")
    #expect(readStore.titleLookups == [
        .init(title: "exact match", location: .notes),
    ])
}

@Test
func getNotesUsesTemplateStrippedCanonicalContentAndOmitsAttachmentTextByDefault() async throws {
    let note = makeFetchedSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nLine 1\n\n[file.pdf](file.pdf)<!-- {\"embed\":\"true\"} -->",
        rawText: "# Inbox\r---\r#0-inbox\r---\rLine 1\r\r[file.pdf](file.pdf)<!-- {\"embed\":\"true\"} -->",
        tags: ["0-inbox"],
        archived: false
    )
    let readStore = GetNotesReadStore(
        noteByID: ["note-1": note],
        attachmentsByNoteID: [
            "note-1": [
                NoteAttachment(
                    attachmentID: "attachment-1",
                    filename: "file.pdf",
                    fileExtension: "pdf",
                    searchText: "Attachment OCR"
                ),
            ],
        ]
    )
    let service = BearService(
        configuration: makeGetNotesConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: GetNotesSilentWriteTransport(),
        logger: Logger(label: "BearServiceGetNotesTests")
    )

    let notes = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try service.getNotes(selectors: ["note-1"], location: .notes)
    }

    let fetched = try #require(notes.first)
    let payload = try encodedJSONObject(fetched)
    let attachmentPayload = try #require((payload["attachments"] as? [[String: Any]])?.first)
    #expect(fetched.content == "Line 1\n\n[file.pdf](file.pdf)<!-- {\"embed\":\"true\"} -->")
    #expect(fetched.attachments.count == 1)
    #expect(fetched.attachments.first?.attachmentID == "attachment-1")
    #expect(fetched.attachments.first?.searchText == nil)
    #expect(attachmentPayload["searchText"] == nil)
}

@Test
func getNotesIncludesAttachmentTextWhenExplicitlyRequested() async throws {
    let note = makeFetchedSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: ["0-inbox"],
        archived: false
    )
    let readStore = GetNotesReadStore(
        noteByID: ["note-1": note],
        attachmentsByNoteID: [
            "note-1": [
                NoteAttachment(
                    attachmentID: "attachment-1",
                    filename: "file.pdf",
                    fileExtension: "pdf",
                    searchText: "Attachment OCR"
                ),
            ],
        ]
    )
    let service = BearService(
        configuration: makeGetNotesConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: GetNotesSilentWriteTransport(),
        logger: Logger(label: "BearServiceGetNotesTests")
    )

    let notes = try service.getNotes(
        selectors: ["note-1"],
        location: .notes,
        includeAttachmentText: true
    )

    let fetched = try #require(notes.first)
    let payload = try encodedJSONObject(fetched)
    let attachmentPayload = try #require((payload["attachments"] as? [[String: Any]])?.first)
    #expect(fetched.attachments.first?.searchText == "Attachment OCR")
    #expect(attachmentPayload["searchText"] as? String == "Attachment OCR")
}

@Test
func getNotesStillMatchesTemplateWhenEffectiveTagsIncludeImplicitParentTags() async throws {
    let note = makeFetchedSourceNote(
        id: "note-implicit-parent",
        title: "Inbox",
        body: "---\n#0-inbox #parent/subtag\n---\nLine 1",
        tags: ["0-inbox", "parent", "parent/subtag"],
        archived: false
    )
    let readStore = GetNotesReadStore(noteByID: ["note-implicit-parent": note])
    let service = BearService(
        configuration: makeGetNotesConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: GetNotesSilentWriteTransport(),
        logger: Logger(label: "BearServiceGetNotesTests")
    )

    let notes = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try service.getNotes(selectors: ["note-implicit-parent"], location: .notes)
    }

    let fetched = try #require(notes.first)
    #expect(fetched.content == "Line 1")
    #expect(fetched.tags == ["0-inbox", "parent", "parent/subtag"])
}

@Test
func getNotesStillMatchesTemplateWhenTerminalContentIsEmpty() async throws {
    let note = makeFetchedSourceNote(
        id: "note-empty-content",
        title: "Inbox",
        body: "---\n#0-inbox\n---",
        rawText: "# Inbox\n---\n#0-inbox\n---",
        tags: ["0-inbox"],
        archived: false
    )
    let readStore = GetNotesReadStore(noteByID: ["note-empty-content": note])
    let service = BearService(
        configuration: makeGetNotesConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: GetNotesSilentWriteTransport(),
        logger: Logger(label: "BearServiceGetNotesTests")
    )

    let notes = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try service.getNotes(selectors: ["note-empty-content"], location: .notes)
    }

    let fetched = try #require(notes.first)
    #expect(fetched.content == "")
    #expect(fetched.tags == ["0-inbox"])
}

@Test
func getNotesReturnsEncryptedFlagOnlyForEncryptedNotes() throws {
    let note = makeFetchedSourceNote(
        id: "secret",
        title: "Secret",
        body: "hidden",
        tags: ["secure"],
        archived: false,
        encrypted: true
    )
    let readStore = GetNotesReadStore(
        noteByID: ["secret": note],
        attachmentsByNoteID: [
            "secret": [
                NoteAttachment(
                    attachmentID: "attachment-1",
                    filename: "ignored.pdf",
                    fileExtension: "pdf",
                    searchText: "Should not be returned"
                ),
            ],
        ]
    )
    let service = BearService(
        configuration: makeGetNotesConfiguration(inboxTags: []),
        readStore: readStore,
        writeTransport: GetNotesSilentWriteTransport(),
        logger: Logger(label: "BearServiceGetNotesTests")
    )

    let notes = try service.getNotes(selectors: ["secret"], location: .notes)

    let fetched = try #require(notes.first)
    #expect(fetched.content.isEmpty)
    #expect(fetched.attachments.isEmpty)
    #expect(fetched.encrypted == true)
}

@Test
func getNotesFiltersArchivedAndTrashedNotesByRequestedLocation() throws {
    let archived = makeFetchedSourceNote(
        id: "archived",
        title: "Archived",
        body: "Archive body",
        tags: [],
        archived: true
    )
    let trashed = makeFetchedSourceNote(
        id: "trashed",
        title: "Trashed",
        body: "Trash body",
        tags: [],
        archived: false,
        trashed: true
    )
    let readStore = GetNotesReadStore(
        noteByID: [
            "archived": archived,
            "trashed": trashed,
        ],
        notesByTitleAndLocation: [
            .init(title: "Archived", location: .archive): [archived],
        ]
    )
    let service = BearService(
        configuration: makeGetNotesConfiguration(inboxTags: []),
        readStore: readStore,
        writeTransport: GetNotesSilentWriteTransport(),
        logger: Logger(label: "BearServiceGetNotesTests")
    )

    let notes = try service.getNotes(selectors: ["archived", "trashed"], location: .notes)
    let archiveNotes = try service.getNotes(selectors: ["Archived"], location: .archive)

    #expect(notes.isEmpty)
    #expect(archiveNotes.count == 1)
    #expect(archiveNotes.first?.noteID == "archived")
}

@Test
func getNotesIgnoresUnmatchedAndEmptySelectors() throws {
    let note = makeFetchedSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Body",
        tags: ["0-inbox"],
        archived: false
    )
    let readStore = GetNotesReadStore(
        notesByTitleAndLocation: [
            .init(title: "Inbox", location: .notes): [note],
        ]
    )
    let service = BearService(
        configuration: makeGetNotesConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: GetNotesSilentWriteTransport(),
        logger: Logger(label: "BearServiceGetNotesTests")
    )

    let notes = try service.getNotes(selectors: ["  ", "missing", "Inbox"], location: .notes)

    #expect(notes.count == 1)
    #expect(notes.first?.noteID == "note-1")
}

private func makeGetNotesConfiguration(
    inboxTags: [String]
) -> BearConfiguration {
    BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        inboxTags: inboxTags,
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        maxDiscoveryLimit: 100,
        defaultSnippetLength: 280,
        maxSnippetLength: 1_000,
        backupRetentionDays: 30
    )
}

private func makeFetchedSourceNote(
    id: String,
    title: String,
    body: String,
    rawText: String? = nil,
    tags: [String],
    archived: Bool,
    trashed: Bool = false,
    encrypted: Bool = false,
    modifiedAt: Date = Date(timeIntervalSince1970: 1_710_000_500)
) -> BearNote {
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)

    return BearNote(
        ref: NoteRef(identifier: id),
        revision: NoteRevision(version: 3, createdAt: createdAt, modifiedAt: modifiedAt),
        title: title,
        body: body,
        rawText: rawText ?? BearText.composeRawText(title: title, body: body),
        tags: tags,
        archived: archived,
        trashed: trashed,
        encrypted: encrypted
    )
}

private final class GetNotesReadStore: @unchecked Sendable, BearReadStore {
    private let noteByID: [String: BearNote]
    private let notesByTitleAndLocation: [TitleLookupKey: [BearNote]]
    private let attachmentsByNoteID: [String: [NoteAttachment]]

    private(set) var titleLookups: [TitleLookupKey] = []

    init(
        noteByID: [String: BearNote] = [:],
        notesByTitleAndLocation: [TitleLookupKey: [BearNote]] = [:],
        attachmentsByNoteID: [String: [NoteAttachment]] = [:]
    ) {
        self.noteByID = noteByID
        self.notesByTitleAndLocation = notesByTitleAndLocation
        self.attachmentsByNoteID = attachmentsByNoteID
    }

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }

    func note(id: String) throws -> BearNote? {
        noteByID[id]
    }

    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }

    func notes(titled title: String, location: BearNoteLocation) throws -> [BearNote] {
        let key = TitleLookupKey(title: title, location: location)
        titleLookups.append(key)
        return notesByTitleAndLocation[key] ?? []
    }

    func attachments(noteID: String) throws -> [NoteAttachment] {
        attachmentsByNoteID[noteID] ?? []
    }

    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }

    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private struct TitleLookupKey: Hashable {
    let normalizedTitle: String
    let location: BearNoteLocation

    init(title: String, location: BearNoteLocation) {
        self.normalizedTitle = title.lowercased()
        self.location = location
    }
}

private func encodedJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private struct GetNotesSilentWriteTransport: BearWriteTransport {
    func resolveSelectedNoteID(token _: String) async throws -> String {
        "selected-note"
    }

    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: "created", title: request.title, status: "created", modifiedAt: nil)
    }

    func insertText(_ request: InsertTextRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func replaceAll(noteID: String, fullText: String, presentation: BearPresentationOptions) async throws -> MutationReceipt {
        MutationReceipt(noteID: noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func addFile(_ request: AddFileRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func open(_ request: OpenNoteRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "opened", modifiedAt: nil)
    }

    func openTag(_ request: OpenTagRequest) async throws -> TagMutationReceipt {
        TagMutationReceipt(tag: request.tag, newTag: nil, status: "opened")
    }

    func renameTag(_ request: RenameTagRequest) async throws -> TagMutationReceipt {
        TagMutationReceipt(tag: request.name, newTag: request.newName, status: "renamed")
    }

    func deleteTag(_ request: DeleteTagRequest) async throws -> TagMutationReceipt {
        TagMutationReceipt(tag: request.name, newTag: nil, status: "deleted")
    }

    func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        MutationReceipt(noteID: noteID, title: nil, status: "archived", modifiedAt: nil)
    }
}
