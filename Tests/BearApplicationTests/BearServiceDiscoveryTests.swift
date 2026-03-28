import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func findNotesByInboxTagsUsesTemplateContentForBodySnippetAndAttachmentSnippet() async throws {
    let note = makeNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nAlpha beta gamma delta epsilon",
        tags: ["0-inbox"],
        archived: false
    )
    let readStore = DiscoveryReadStore(
        findBatches: [DiscoveryNoteBatch(notes: [note], hasMore: false)],
        attachmentsByNoteID: [
            "note-1": [
                NoteAttachment(
                    attachmentID: "file-1",
                    filename: "scan.pdf",
                    fileExtension: "pdf",
                    searchText: "Invoice attachment OCR text"
                ),
            ],
        ]
    )
    let service = BearService(
        configuration: makeDiscoveryConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let batch = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try service.findNotesByInboxTags([
            FindNotesByInboxTagsOperation(location: .notes, snippetLength: 22),
        ])
    }

    let result = try #require(batch.results.first)
    let summary = try #require(result.items?.first)
    #expect(result.error == nil)
    #expect(summary.snippet == "Alpha beta gamma delta…")
    #expect(summary.attachmentSnippet == "Invoice attachment OCR…")
    #expect(summary.matchedFields == nil)
    #expect(readStore.lastFindQuery?.tagsAny == ["0-inbox"])
    #expect(readStore.lastFindQuery?.location == .notes)
    #expect(readStore.lastFindQuery?.paging.limit == 20)
}

@Test
func findNotesClampsConfiguredOverridesAndTracksMatchedFields() throws {
    let note = makeNote(
        id: "archive-1",
        title: "Archived",
        body: "One two three four five six",
        tags: ["project"],
        archived: true
    )
    let readStore = DiscoveryReadStore(findBatches: [
        DiscoveryNoteBatch(notes: [note], hasMore: false),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(
            inboxTags: ["0-inbox"],
            defaultDiscoveryLimit: 7,
            maxDiscoveryLimit: 25,
            defaultSnippetLength: 12,
            maxSnippetLength: 18
        ),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let batch = try service.findNotes([
        FindNotesOperation(text: "three", location: .archive, limit: 500, snippetLength: 50),
    ])

    let result = try #require(batch.results.first)
    let summary = try #require(result.items?.first)
    #expect(result.page?.limit == 25)
    #expect(summary.snippet == "One two three four…")
    #expect(summary.matchedFields == [.body])
    #expect(readStore.lastFindQuery?.location == .archive)
    #expect(readStore.lastFindQuery?.paging.limit == 25)
}

@Test
func findNotesByTagSupportsAllMatchAndNormalizesTags() throws {
    let note = makeNote(
        id: "tag-1",
        title: "Project",
        body: "Body text with enough words to truncate cleanly",
        tags: ["deep work", "project"],
        archived: true
    )
    let readStore = DiscoveryReadStore(findBatches: [
        DiscoveryNoteBatch(notes: [note], hasMore: false),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let batch = try service.findNotesByTag([
        FindNotesByTagOperation(
            tags: ["#deep work#", " #project# "],
            tagMatch: .all,
            location: .archive,
            limit: 1,
            snippetLength: 18
        ),
    ])

    let summary = try #require(batch.results.first?.items?.first)
    #expect(summary.noteID == "tag-1")
    #expect(summary.archived)
    #expect(readStore.lastFindQuery?.tagsAll == ["deep work", "project"])
    #expect(readStore.lastFindQuery?.location == .archive)
    #expect(readStore.lastFindQuery?.paging.limit == 1)
}

@Test
func findNotesReturnsNextCursorAndAcceptsContinuation() throws {
    let first = makeNote(
        id: "note-2",
        title: "Second",
        body: "Second page body",
        tags: [],
        archived: false,
        modifiedAt: Date(timeIntervalSince1970: 1_710_000_600)
    )
    let second = makeNote(
        id: "note-1",
        title: "First",
        body: "First page body",
        tags: [],
        archived: false,
        modifiedAt: Date(timeIntervalSince1970: 1_710_000_500)
    )
    let readStore = DiscoveryReadStore(findBatches: [
        DiscoveryNoteBatch(notes: [first], hasMore: true, relevanceBuckets: [2]),
        DiscoveryNoteBatch(notes: [second], hasMore: false),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let firstBatch = try service.findNotes([
        FindNotesOperation(id: "op-1", text: "page", limit: 1, snippetLength: 50),
    ])
    let token = try #require(firstBatch.results.first?.page?.nextCursor)
    let cursor = try DiscoveryCursorCoder.decode(token)

    #expect(firstBatch.results.first?.page?.hasMore == true)
    #expect(cursor.kind == .findNotes)
    #expect(cursor.location == .notes)
    #expect(cursor.relevanceBucket == 2)
    #expect(cursor.lastNoteID == "note-2")

    let secondBatch = try service.findNotes([
        FindNotesOperation(id: "op-1", text: "page", limit: 1, snippetLength: 50, cursor: token),
    ])

    #expect(secondBatch.results.first?.items?.first?.noteID == "note-1")
    #expect(secondBatch.results.first?.page?.hasMore == false)
    #expect(secondBatch.results.first?.page?.nextCursor == nil)
    #expect(readStore.findQueries.count == 2)
    #expect(readStore.findQueries.last?.paging.cursor?.relevanceBucket == 2)
    #expect(readStore.findQueries.last?.paging.cursor?.lastNoteID == "note-2")
}

@Test
func findNotesReturnsPerOperationErrorsWithoutFailingSiblings() throws {
    let note = makeNote(
        id: "note-1",
        title: "Alpha",
        body: "Alpha body",
        tags: [],
        archived: false
    )
    let readStore = DiscoveryReadStore(findBatches: [
        DiscoveryNoteBatch(notes: [note], hasMore: false),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let batch = try service.findNotes([
        FindNotesOperation(id: "bad"),
        FindNotesOperation(id: "good", text: "alpha"),
    ])

    #expect(batch.results.count == 2)
    #expect(batch.results[0].id == "bad")
    #expect(batch.results[0].error == "Each find operation must include at least one filter.")
    #expect(batch.results[1].id == "good")
    #expect(batch.results[1].error == nil)
    #expect(batch.results[1].items?.first?.noteID == "note-1")
    #expect(readStore.findQueries.count == 1)
}

@Test
func findNotesRejectsMismatchedCursorPerOperation() throws {
    let note = makeNote(
        id: "note-1",
        title: "Alpha",
        body: "Alpha body",
        tags: [],
        archived: false
    )
    let readStore = DiscoveryReadStore(findBatches: [
        DiscoveryNoteBatch(notes: [note], hasMore: true),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let firstBatch = try service.findNotes([
        FindNotesOperation(text: "alpha", limit: 1),
    ])
    let token = try #require(firstBatch.results.first?.page?.nextCursor)

    let secondBatch = try service.findNotes([
        FindNotesOperation(text: "beta", limit: 1, cursor: token),
    ])

    #expect(secondBatch.results.first?.error == "Discovery cursor does not match this request.")
}

@Test
func findNotesParsesDateFiltersAndDefaultsDateFieldToModifiedAt() throws {
    let readStore = DiscoveryReadStore(findBatches: [
        DiscoveryNoteBatch(notes: [], hasMore: false),
        DiscoveryNoteBatch(notes: [], hasMore: false),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    _ = try service.findNotes([
        FindNotesOperation(dateField: .createdAt, from: "2026-03-01", to: "2026-03-31"),
        FindNotesOperation(from: "last week"),
    ])

    #expect(readStore.findQueries.count == 2)
    #expect(readStore.findQueries[0].dateField == .createdAt)
    #expect(readStore.findQueries[0].from != nil)
    #expect(readStore.findQueries[0].to != nil)
    #expect(readStore.findQueries[1].dateField == .modifiedAt)
    #expect(readStore.findQueries[1].from != nil)
}

@Test
func findNotesAllowsPresenceOnlyFilters() throws {
    let note = makeNote(
        id: "note-1",
        title: "Filtered",
        body: "Body",
        tags: [],
        archived: false
    )
    let readStore = DiscoveryReadStore(findBatches: [
        DiscoveryNoteBatch(notes: [note], hasMore: false),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let batch = try service.findNotes([
        FindNotesOperation(
            hasAttachments: true,
            hasAttachmentSearchText: false,
            hasTags: false
        ),
    ])

    #expect(batch.results.first?.error == nil)
    #expect(batch.results.first?.items?.first?.noteID == "note-1")
    #expect(readStore.lastFindQuery?.hasAttachments == true)
    #expect(readStore.lastFindQuery?.hasAttachmentSearchText == false)
    #expect(readStore.lastFindQuery?.hasTags == false)
}

@Test
func findNotesRejectsFutureNaturalLanguageDateFilters() throws {
    let readStore = DiscoveryReadStore(findBatches: [])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let batch = try service.findNotes([
        FindNotesOperation(from: "next week"),
        FindNotesOperation(to: "tomorrow"),
    ])

    #expect(batch.results.count == 2)
    #expect(batch.results[0].error == "Could not parse date 'next week'.")
    #expect(batch.results[1].error == "Could not parse date 'tomorrow'.")
    #expect(readStore.findQueries.isEmpty)
}

@Test
func listTagsDefaultsToNotesWithoutFilters() throws {
    let readStore = DiscoveryReadStore(listTagsResults: [
        TagSummary(name: "projects", identifier: "tag-1", noteCount: 2),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let tags = try service.listTags()

    #expect(tags.map(\.name) == ["projects"])
    #expect(readStore.lastListTagsQuery?.location == .notes)
    #expect(readStore.lastListTagsQuery?.query == nil)
    #expect(readStore.lastListTagsQuery?.underTag == nil)
}

@Test
func listTagsNormalizesOptionalFiltersBeforeQuerying() throws {
    let readStore = DiscoveryReadStore()
    let service = BearService(
        configuration: makeDiscoveryConfiguration(inboxTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    _ = try service.listTags(
        location: .archive,
        query: "  #Work#  ",
        underTag: " #projects/workflows/# "
    )

    #expect(readStore.lastListTagsQuery?.location == .archive)
    #expect(readStore.lastListTagsQuery?.query == "Work")
    #expect(readStore.lastListTagsQuery?.underTag == "projects/workflows")
}

private func makeDiscoveryConfiguration(
    inboxTags: [String],
    defaultDiscoveryLimit: Int = 20,
    maxDiscoveryLimit: Int = 100,
    defaultSnippetLength: Int = 280,
    maxSnippetLength: Int = 1_000,
    backupRetentionDays: Int = 30
) -> BearConfiguration {
    BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        inboxTags: inboxTags,
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        openNoteInEditModeByDefault: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: defaultDiscoveryLimit,
        maxDiscoveryLimit: maxDiscoveryLimit,
        defaultSnippetLength: defaultSnippetLength,
        maxSnippetLength: maxSnippetLength,
        backupRetentionDays: backupRetentionDays
    )
}

private func makeNote(
    id: String,
    title: String,
    body: String,
    tags: [String],
    archived: Bool,
    modifiedAt: Date = Date(timeIntervalSince1970: 1_710_000_500)
) -> BearNote {
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)

    return BearNote(
        ref: NoteRef(identifier: id),
        revision: NoteRevision(version: 3, createdAt: createdAt, modifiedAt: modifiedAt),
        title: title,
        body: body,
        rawText: BearText.composeRawText(title: title, body: body),
        tags: tags,
        archived: archived,
        trashed: false,
        encrypted: false
    )
}

private final class DiscoveryReadStore: @unchecked Sendable, BearReadStore {
    private let findBatches: [DiscoveryNoteBatch]
    private let listTagsResults: [TagSummary]
    private let attachmentsByNoteID: [String: [NoteAttachment]]

    private(set) var findQueries: [FindNotesQuery] = []
    private(set) var listTagQueries: [ListTagsQuery] = []

    private var nextFindBatchIndex = 0

    var lastFindQuery: FindNotesQuery? { findQueries.last }
    var lastListTagsQuery: ListTagsQuery? { listTagQueries.last }

    init(
        findBatches: [DiscoveryNoteBatch] = [],
        listTagsResults: [TagSummary] = [],
        attachmentsByNoteID: [String: [NoteAttachment]] = [:]
    ) {
        self.findBatches = findBatches
        self.listTagsResults = listTagsResults
        self.attachmentsByNoteID = attachmentsByNoteID
    }

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch {
        findQueries.append(query)
        guard nextFindBatchIndex < findBatches.count else {
            return DiscoveryNoteBatch(notes: [], hasMore: false)
        }

        defer { nextFindBatchIndex += 1 }
        return findBatches[nextFindBatchIndex]
    }

    func note(id: String) throws -> BearNote? { nil }

    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }

    func attachments(noteID: String) throws -> [NoteAttachment] {
        attachmentsByNoteID[noteID] ?? []
    }

    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] {
        listTagQueries.append(query)
        return listTagsResults
    }

    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private struct SilentWriteTransport: BearWriteTransport {
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
