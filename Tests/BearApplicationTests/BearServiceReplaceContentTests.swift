import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func replaceContentBodyPreservesTemplateWrapper() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nLine 1",
        tags: ["0-inbox"]
    )
    let transport = ReplaceContentRecordingWriteTransport()
    let service = BearService(
        configuration: makeReplaceContentConfiguration(templateManagementEnabled: true),
        readStore: ReplaceContentReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceReplaceContentTests")
    )

    try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        _ = try await service.replaceContent([
            ReplaceContentRequest(
                noteID: "note-1",
                kind: .body,
                oldString: nil,
                occurrence: nil,
                newString: "Line 2",
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == "# Inbox\n\n---\n#0-inbox\n---\nLine 2")
}

@Test
func replaceContentTitleRerendersTemplateWithNewTitle() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Meta: Inbox\n---\nLine 1",
        tags: ["0-inbox"]
    )
    let transport = ReplaceContentRecordingWriteTransport()
    let service = BearService(
        configuration: makeReplaceContentConfiguration(templateManagementEnabled: true),
        readStore: ReplaceContentReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceReplaceContentTests")
    )

    try await withTemporaryNoteTemplate("Meta: {{title}}\n---\n{{content}}\n") {
        _ = try await service.replaceContent([
            ReplaceContentRequest(
                noteID: "note-1",
                kind: .title,
                oldString: nil,
                occurrence: nil,
                newString: "Projects",
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == "# Projects\n\nMeta: Projects\n---\nLine 1")
}

@Test
func replaceContentEmptyTemplatedBodyPreservesExistingSingleNewlineTitleSeparator() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nLine 1",
        rawText: "# Inbox\n---\n#0-inbox\n---\nLine 1",
        tags: ["0-inbox"]
    )
    let transport = ReplaceContentRecordingWriteTransport()
    let service = BearService(
        configuration: makeReplaceContentConfiguration(templateManagementEnabled: true),
        readStore: ReplaceContentReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceReplaceContentTests")
    )

    try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        _ = try await service.replaceContent([
            ReplaceContentRequest(
                noteID: "note-1",
                kind: .body,
                oldString: nil,
                occurrence: nil,
                newString: "",
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == "# Inbox\n---\n#0-inbox\n---")
}

@Test
func replaceContentStringTouchesEditableContentButNotTitle() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Heading\nInbox",
        rawText: "# Inbox\n\nHeading\nInbox",
        tags: ["0-inbox"]
    )
    let transport = ReplaceContentRecordingWriteTransport()
    let service = BearService(
        configuration: makeReplaceContentConfiguration(templateManagementEnabled: false),
        readStore: ReplaceContentReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceReplaceContentTests")
    )

    _ = try await service.replaceContent([
        ReplaceContentRequest(
            noteID: "note-1",
            kind: .string,
            oldString: "Inbox",
            occurrence: .one,
            newString: "Archive",
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == "# Inbox\n\nHeading\nArchive")
}

@Test
func replaceContentStringRejectsMissingOccurrence() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: ["0-inbox"]
    )
    let service = BearService(
        configuration: makeReplaceContentConfiguration(templateManagementEnabled: false),
        readStore: ReplaceContentReadStore(noteByID: ["note-1": note]),
        writeTransport: ReplaceContentRecordingWriteTransport(),
        logger: Logger(label: "BearServiceReplaceContentTests")
    )

    await #expect(throws: BearError.self) {
        _ = try await service.replaceContent([
            ReplaceContentRequest(
                noteID: "note-1",
                kind: .string,
                oldString: "Line",
                occurrence: nil,
                newString: "Item",
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }
}

@Test
func replaceContentTitleRejectsOldString() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: ["0-inbox"]
    )
    let service = BearService(
        configuration: makeReplaceContentConfiguration(templateManagementEnabled: false),
        readStore: ReplaceContentReadStore(noteByID: ["note-1": note]),
        writeTransport: ReplaceContentRecordingWriteTransport(),
        logger: Logger(label: "BearServiceReplaceContentTests")
    )

    await #expect(throws: BearError.self) {
        _ = try await service.replaceContent([
            ReplaceContentRequest(
                noteID: "note-1",
                kind: .title,
                oldString: "Inbox",
                occurrence: nil,
                newString: "Projects",
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }
}

private func makeReplaceContentConfiguration(templateManagementEnabled: Bool) -> BearConfiguration {
    BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: templateManagementEnabled,
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

private func makeReplaceContentSourceNote(
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

private final class ReplaceContentReadStore: @unchecked Sendable, BearReadStore {
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

private actor ReplaceContentRecordingWriteTransport: BearWriteTransport {
    struct ReplaceCall: Sendable {
        let noteID: String
        let fullText: String
    }

    private(set) var replaceCalls: [ReplaceCall] = []

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
        replaceCalls.append(ReplaceCall(noteID: noteID, fullText: fullText))
        return MutationReceipt(noteID: noteID, title: nil, status: "updated", modifiedAt: nil)
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
