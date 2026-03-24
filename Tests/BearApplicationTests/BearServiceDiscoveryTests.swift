import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func getActiveNotesUsesTemplateContentForSnippets() async throws {
    let note = makeNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nAlpha beta gamma delta epsilon",
        tags: ["0-inbox"],
        archived: false
    )
    let readStore = DiscoveryReadStore(tagNotes: [note])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(activeTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let summaries = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try service.getActiveNotes(location: .notes, limit: nil, snippetLength: 22)
    }

    let summary = try #require(summaries.first)
    #expect(summaries.count == 1)
    #expect(summary.noteID == "note-1")
    #expect(summary.snippet == "Alpha beta gamma delta…")
    #expect(summary.createdAt == note.revision.createdAt)
    #expect(summary.modifiedAt == note.revision.modifiedAt)
    #expect(readStore.lastTagQuery?.tags == ["0-inbox"])
    #expect(readStore.lastTagQuery?.location == .notes)
    #expect(readStore.lastTagQuery?.limit == 20)
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
    let readStore = DiscoveryReadStore(searchNotes: [note])
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

    let summaries = try service.searchNotes(
        query: "three",
        location: .archive,
        limit: 500,
        snippetLength: 50
    )

    let summary = try #require(summaries.first)
    #expect(summary.snippet == "One two three four…")
    #expect(readStore.lastSearchQuery?.location == .archive)
    #expect(readStore.lastSearchQuery?.limit == 25)
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
    let readStore = DiscoveryReadStore(tagNotes: [note])
    let service = BearService(
        configuration: makeDiscoveryConfiguration(activeTags: ["0-inbox"]),
        readStore: readStore,
        writeTransport: SilentWriteTransport(),
        logger: Logger(label: "BearServiceDiscoveryTests")
    )

    let summaries = try service.getNotesByTag(
        tags: ["project"],
        location: .archive,
        limit: 1,
        snippetLength: 18
    )

    let summary = try #require(summaries.first)
    #expect(summaries.count == 1)
    #expect(summary.noteID == "tag-1")
    #expect(summary.archived)
    #expect(readStore.lastTagQuery?.tags == ["project"])
    #expect(readStore.lastTagQuery?.location == .archive)
    #expect(readStore.lastTagQuery?.limit == 1)
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
        createRequestTagsMode: .append,
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
    archived: Bool
) -> BearNote {
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
    let modifiedAt = Date(timeIntervalSince1970: 1_710_000_500)

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
    struct TagQuery: Equatable {
        let tags: [String]
        let location: BearNoteLocation
        let limit: Int
    }

    private let searchResults: [BearNote]
    private let tagResults: [BearNote]

    var lastSearchQuery: NoteSearchQuery?
    var lastTagQuery: TagQuery?

    init(searchNotes: [BearNote] = [], tagNotes: [BearNote] = []) {
        self.searchResults = searchNotes
        self.tagResults = tagNotes
    }

    func searchNotes(_ query: NoteSearchQuery) throws -> [BearNote] {
        lastSearchQuery = query
        return searchResults
    }

    func note(id: String) throws -> BearNote? { nil }

    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }

    func notes(matchingAnyTags tags: [String], location: BearNoteLocation, limit: Int) throws -> [BearNote] {
        lastTagQuery = TagQuery(tags: tags, location: location, limit: limit)
        return tagResults
    }

    func listTags() throws -> [TagSummary] { [] }

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

    func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        MutationReceipt(noteID: noteID, title: nil, status: "archived", modifiedAt: nil)
    }
}
