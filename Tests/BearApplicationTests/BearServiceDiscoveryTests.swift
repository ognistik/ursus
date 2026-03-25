import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func getNotesByActiveTagsUsesTemplateContentForSnippets() async throws {
    let note = makeNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nAlpha beta gamma delta epsilon",
        tags: ["0-inbox"],
        archived: false
    )
    let readStore = DiscoveryReadStore(tagBatches: [
        DiscoveryNoteBatch(notes: [note], hasMore: false),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(activeTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let page = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try service.getNotesByActiveTags(location: .notes, limit: nil, snippetLength: 22, cursor: nil)
    }

    let summary = try #require(page.items.first)
    #expect(page.items.count == 1)
    #expect(summary.noteID == "note-1")
    #expect(summary.snippet == "Alpha beta gamma delta…")
    #expect(summary.createdAt == note.revision.createdAt)
    #expect(summary.modifiedAt == note.revision.modifiedAt)
    #expect(page.page.limit == 20)
    #expect(page.page.returned == 1)
    #expect(page.page.hasMore == false)
    #expect(page.page.nextCursor == nil)
    #expect(readStore.lastTagQuery?.tags == ["0-inbox"])
    #expect(readStore.lastTagQuery?.location == .notes)
    #expect(readStore.lastTagQuery?.paging.limit == 20)
}

@Test
func getNotesByActiveTagsNormalizesWrappedTagsBeforeQuerying() throws {
    let readStore = DiscoveryReadStore()
    let service = BearService(
        configuration: makeDiscoveryConfiguration(activeTags: ["#deep work#", " #focus mode# "]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    _ = try service.getNotesByActiveTags(location: .notes, limit: 5, snippetLength: 50, cursor: nil)

    #expect(readStore.lastTagQuery?.tags == ["deep work", "focus mode"])
}

@Test
func searchNotesClampsConfiguredDiscoveryOverrides() throws {
    let note = makeNote(
        id: "archive-1",
        title: "Archived",
        body: "One two three four five six",
        tags: ["project"],
        archived: true
    )
    let readStore = DiscoveryReadStore(searchBatches: [
        DiscoveryNoteBatch(notes: [note], hasMore: false),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(
            activeTags: ["0-inbox"],
            defaultDiscoveryLimit: 7,
            maxDiscoveryLimit: 25,
            defaultSnippetLength: 12,
            maxSnippetLength: 18
        ),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let page = try service.searchNotes(
        query: "three",
        location: .archive,
        limit: 500,
        snippetLength: 50,
        cursor: nil
    )

    let summary = try #require(page.items.first)
    #expect(summary.snippet == "One two three four…")
    #expect(page.page.limit == 25)
    #expect(readStore.lastSearchQuery?.location == .archive)
    #expect(readStore.lastSearchQuery?.paging.limit == 25)
}

@Test
func getNotesByTagReturnsSummariesAndRespectsExplicitLimit() throws {
    let note = makeNote(
        id: "tag-1",
        title: "Project",
        body: "Body text with enough words to truncate cleanly",
        tags: ["project"],
        archived: true
    )
    let readStore = DiscoveryReadStore(tagBatches: [
        DiscoveryNoteBatch(notes: [note], hasMore: false),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(activeTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let page = try service.getNotesByTag(
        tags: ["#project#"],
        location: .archive,
        limit: 1,
        snippetLength: 18,
        cursor: nil
    )

    let summary = try #require(page.items.first)
    #expect(page.items.count == 1)
    #expect(summary.noteID == "tag-1")
    #expect(summary.archived)
    #expect(readStore.lastTagQuery?.tags == ["project"])
    #expect(readStore.lastTagQuery?.location == .archive)
    #expect(readStore.lastTagQuery?.paging.limit == 1)
}

@Test
func searchNotesReturnsNextCursorAndAcceptsContinuation() throws {
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
    let readStore = DiscoveryReadStore(searchBatches: [
        DiscoveryNoteBatch(notes: [first], hasMore: true),
        DiscoveryNoteBatch(notes: [second], hasMore: false),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(activeTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let firstPage = try service.searchNotes(
        query: "page",
        location: .notes,
        limit: 1,
        snippetLength: 50,
        cursor: nil
    )
    let token = try #require(firstPage.page.nextCursor)
    let cursor = try DiscoveryCursorCoder.decode(token)

    #expect(firstPage.page.hasMore)
    #expect(firstPage.page.returned == 1)
    #expect(cursor.kind == .searchNotes)
    #expect(cursor.location == .notes)
    #expect(cursor.lastNoteID == "note-2")

    let secondPage = try service.searchNotes(
        query: "page",
        location: .notes,
        limit: 1,
        snippetLength: 50,
        cursor: token
    )

    #expect(secondPage.items.count == 1)
    #expect(secondPage.items.first?.noteID == "note-1")
    #expect(secondPage.page.hasMore == false)
    #expect(secondPage.page.nextCursor == nil)
    #expect(readStore.searchQueries.count == 2)
    #expect(readStore.searchQueries.last?.paging.cursor?.lastNoteID == "note-2")
}

@Test
func searchNotesRejectsMismatchedCursor() throws {
    let note = makeNote(
        id: "note-1",
        title: "Alpha",
        body: "Alpha body",
        tags: [],
        archived: false
    )
    let readStore = DiscoveryReadStore(searchBatches: [
        DiscoveryNoteBatch(notes: [note], hasMore: true),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(activeTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let firstPage = try service.searchNotes(
        query: "alpha",
        location: .notes,
        limit: 1,
        snippetLength: 50,
        cursor: nil
    )
    let token = try #require(firstPage.page.nextCursor)

    var didThrow = false
    do {
        _ = try service.searchNotes(
            query: "beta",
            location: .notes,
            limit: 1,
            snippetLength: 50,
            cursor: token
        )
    } catch {
        didThrow = true
        let description = (error as? LocalizedError)?.errorDescription
        #expect(description == "Discovery cursor does not match this request.")
    }

    #expect(didThrow)
}

@Test
func listTagsDefaultsToNotesWithoutFilters() throws {
    let readStore = DiscoveryReadStore(listTagsResults: [
        TagSummary(name: "projects", identifier: "tag-1", noteCount: 2),
    ])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(activeTags: ["0-inbox"]),
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
        configuration: makeDiscoveryConfiguration(activeTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    _ = try service.listTags(
        location: .archive,
        query: "  Work  ",
        underTag: " #projects/workflows/# "
    )

    #expect(readStore.lastListTagsQuery?.location == .archive)
    #expect(readStore.lastListTagsQuery?.query == "Work")
    #expect(readStore.lastListTagsQuery?.underTag == "projects/workflows")
}

private func makeDiscoveryConfiguration(
    activeTags: [String],
    defaultDiscoveryLimit: Int = 20,
    maxDiscoveryLimit: Int = 100,
    defaultSnippetLength: Int = 280,
    maxSnippetLength: Int = 1_000
) -> BearConfiguration {
    BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        activeTags: activeTags,
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        openNoteInEditModeByDefault: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsActiveTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: defaultDiscoveryLimit,
        maxDiscoveryLimit: maxDiscoveryLimit,
        defaultSnippetLength: defaultSnippetLength,
        maxSnippetLength: maxSnippetLength
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
    private let searchBatches: [DiscoveryNoteBatch]
    private let tagBatches: [DiscoveryNoteBatch]
    private let listTagsResults: [TagSummary]

    private(set) var searchQueries: [NoteSearchQuery] = []
    private(set) var tagQueries: [TagNotesQuery] = []
    private(set) var listTagQueries: [ListTagsQuery] = []

    private var nextSearchBatchIndex = 0
    private var nextTagBatchIndex = 0

    var lastSearchQuery: NoteSearchQuery? { searchQueries.last }
    var lastTagQuery: TagNotesQuery? { tagQueries.last }
    var lastListTagsQuery: ListTagsQuery? { listTagQueries.last }

    init(
        searchBatches: [DiscoveryNoteBatch] = [],
        tagBatches: [DiscoveryNoteBatch] = [],
        listTagsResults: [TagSummary] = []
    ) {
        self.searchBatches = searchBatches
        self.tagBatches = tagBatches
        self.listTagsResults = listTagsResults
    }

    func searchNotes(_ query: NoteSearchQuery) throws -> DiscoveryNoteBatch {
        searchQueries.append(query)
        guard nextSearchBatchIndex < searchBatches.count else {
            return DiscoveryNoteBatch(notes: [], hasMore: false)
        }

        defer { nextSearchBatchIndex += 1 }
        return searchBatches[nextSearchBatchIndex]
    }

    func note(id: String) throws -> BearNote? { nil }

    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }

    func notes(matchingAnyTags query: TagNotesQuery) throws -> DiscoveryNoteBatch {
        tagQueries.append(query)
        guard nextTagBatchIndex < tagBatches.count else {
            return DiscoveryNoteBatch(notes: [], hasMore: false)
        }

        defer { nextTagBatchIndex += 1 }
        return tagBatches[nextTagBatchIndex]
    }

    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] {
        listTagQueries.append(query)
        return listTagsResults
    }

    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private struct SilentWriteTransport: BearWriteTransport {
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

    func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        MutationReceipt(noteID: noteID, title: nil, status: "archived", modifiedAt: nil)
    }
}
