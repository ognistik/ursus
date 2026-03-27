import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func addTagsUsesTemplateTagSlotAndSkipsImplicitParentTag() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox #parent/subtag\n---\nLine 1",
        tags: ["0-inbox", "parent", "parent/subtag"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.addTags([
            NoteTagsRequest(
                noteID: "note-1",
                tags: ["parent", "client work"],
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == "# Inbox\n\n---\n#0-inbox #parent/subtag #client work#\n---\nLine 1")
    #expect(receipt.addedTags == ["client work"])
    #expect(receipt.removedTags.isEmpty)
    #expect(receipt.skippedTags == ["parent"])
}

@Test
func removeTagsUsesTemplateTagSlotAndDoesNotTreatImplicitParentAsLiteral() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox #parent/subtag\n---\nLine 1",
        tags: ["0-inbox", "parent", "parent/subtag"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.removeTags([
            NoteTagsRequest(
                noteID: "note-1",
                tags: ["parent", "parent/subtag"],
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == "# Inbox\n\n---\n#0-inbox\n---\nLine 1")
    #expect(receipt.addedTags.isEmpty)
    #expect(receipt.removedTags == ["parent/subtag"])
    #expect(receipt.skippedTags == ["parent"])
}

@Test
func removeTagsFromRawBodyRemovesLiteralTokensAndCleansWhitespace() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Testing #old-tag and #keep-tag in body",
        tags: ["old-tag", "keep-tag"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(templateManagementEnabled: false),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await service.removeTags([
        NoteTagsRequest(
            noteID: "note-1",
            tags: ["old-tag"],
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == "# Inbox\n\nTesting and #keep-tag in body")
    #expect(receipt.removedTags == ["old-tag"])
    #expect(receipt.skippedTags.isEmpty)
}

@Test
func addTagsToRawBodyAppendsCanonicalTagLineWhenNoTagClusterExists() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: []
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(templateManagementEnabled: false),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await service.addTags([
        NoteTagsRequest(
            noteID: "note-1",
            tags: ["deep work", "project-x"],
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == "# Inbox\n\nLine 1\n#deep work# #project-x")
    #expect(receipt.addedTags == ["deep work", "project-x"])
    #expect(receipt.skippedTags.isEmpty)
}

@Test
func removeTagsHandlesLiveStyleNonTemplateBodyFromBearDB() async throws {
    let rawText = """
    # No Template

    This note doesn’t follow the template

    #0-inbox #another tag# #codex-live/raw-added #codex live raw spaced#
    ---
    """
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "No Template",
        body: """
        This note doesn’t follow the template

        #0-inbox #another tag# #codex-live/raw-added #codex live raw spaced#
        ---
        """,
        rawText: rawText,
        tags: ["0-inbox", "another tag", "codex-live/raw-added", "codex live raw spaced", "codex-live"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await service.removeTags([
        NoteTagsRequest(
            noteID: "note-1",
            tags: ["codex-live", "codex-live/raw-added"],
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == """
    # No Template

    This note doesn’t follow the template

    #0-inbox #another tag# #codex live raw spaced#
    ---
    """)
    #expect(receipt.removedTags == ["codex-live/raw-added"])
    #expect(receipt.skippedTags == ["codex-live"])
}

@Test
func removeTagsHandlesLiveStyleTemplateBodyFromBearDB() async throws {
    let rawText = """
    # Codex Live Template 2026-03-26 16-48

    ---
    #0-inbox #codex-live-parent/subtag #codex live spaced# #codex-live-renamed #codex-live-extra
    ---
    Template live test body.
    """
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Codex Live Template 2026-03-26 16-48",
        body: """
        ---
        #0-inbox #codex-live-parent/subtag #codex live spaced# #codex-live-renamed #codex-live-extra
        ---
        Template live test body.
        """,
        rawText: rawText,
        tags: ["0-inbox", "codex-live-parent/subtag", "codex-live-parent", "codex live spaced", "codex-live-renamed", "codex-live-extra"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.removeTags([
            NoteTagsRequest(
                noteID: "note-1",
                tags: ["codex-live-parent", "codex-live-parent/subtag"],
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == """
    # Codex Live Template 2026-03-26 16-48

    ---
    #0-inbox #codex live spaced# #codex-live-renamed #codex-live-extra
    ---
    Template live test body.
    """)
    #expect(receipt.removedTags == ["codex-live-parent/subtag"])
    #expect(receipt.skippedTags == ["codex-live-parent"])
}

private func makeNoteTagConfiguration(templateManagementEnabled: Bool = true) -> BearConfiguration {
    BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        activeTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: templateManagementEnabled,
        openNoteInEditModeByDefault: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsActiveTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        maxDiscoveryLimit: 100,
        defaultSnippetLength: 280,
        maxSnippetLength: 1_000,
        backupRetentionDays: 30
    )
}

private func makeNoteTagSourceNote(
    id: String,
    title: String,
    body: String,
    rawText: String? = nil,
    tags: [String]
) -> BearNote {
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
    let modifiedAt = Date(timeIntervalSince1970: 1_710_000_500)

    return BearNote(
        ref: NoteRef(identifier: id),
        revision: NoteRevision(version: 3, createdAt: createdAt, modifiedAt: modifiedAt),
        title: title,
        body: body,
        rawText: rawText ?? BearText.composeRawText(title: title, body: body),
        tags: tags,
        archived: false,
        trashed: false,
        encrypted: false
    )
}

private final class NoteTagReadStore: @unchecked Sendable, BearReadStore {
    private let noteByID: [String: BearNote]

    init(noteByID: [String: BearNote]) {
        self.noteByID = noteByID
    }

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func note(id: String) throws -> BearNote? { noteByID[id] }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private actor NoteTagRecordingWriteTransport: BearWriteTransport {
    struct ReplaceCall: Sendable {
        let noteID: String
        let fullText: String
    }

    private(set) var replaceCalls: [ReplaceCall] = []

    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: "created", title: request.title, status: "created", modifiedAt: nil)
    }

    func insertText(_ request: InsertTextRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func replaceAll(noteID: String, fullText: String, presentation: BearPresentationOptions) async throws -> MutationReceipt {
        replaceCalls.append(ReplaceCall(noteID: noteID, fullText: fullText))
        return MutationReceipt(noteID: noteID, title: "Inbox", status: "updated", modifiedAt: nil)
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
