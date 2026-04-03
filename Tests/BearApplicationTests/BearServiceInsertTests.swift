import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func insertTextUsesReplaceAllWhenNoteMatchesCurrentTemplateAtBottom() async throws {
    let note = makeInsertSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nLine 1",
        tags: ["0-inbox"]
    )
    let transport = InsertRecordingWriteTransport()
    let service = BearService(
        configuration: makeInsertConfiguration(templateManagementEnabled: true),
        readStore: InsertReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceInsertTests")
    )

    try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        _ = try await service.insertText([
            InsertTextRequest(
                noteID: "note-1",
                text: "Line 2",
                position: .bottom,
                presentation: BearPresentationOptions()
            ),
        ])
    }

    #expect(await transport.insertRequests.isEmpty)
    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.noteID == "note-1")
    #expect(replaceCall.fullText == "# Inbox\n\n---\n#0-inbox\n---\nLine 1\nLine 2")
}

@Test
func insertTextUsesReplaceAllWhenNoteMatchesCurrentTemplateAtTop() async throws {
    let note = makeInsertSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nLine 1",
        tags: ["0-inbox"]
    )
    let transport = InsertRecordingWriteTransport()
    let service = BearService(
        configuration: makeInsertConfiguration(templateManagementEnabled: true),
        readStore: InsertReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceInsertTests")
    )

    try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        _ = try await service.insertText([
            InsertTextRequest(
                noteID: "note-1",
                text: "Line 0",
                position: .top,
                presentation: BearPresentationOptions()
            ),
        ])
    }

    #expect(await transport.insertRequests.isEmpty)
    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == "# Inbox\n\n---\n#0-inbox\n---\nLine 0\nLine 1")
}

@Test
func insertTextFallsBackToDirectInsertWhenNoteDoesNotMatchCurrentTemplate() async throws {
    let note = makeInsertSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Custom header\n\nLine 1",
        tags: ["0-inbox"]
    )
    let transport = InsertRecordingWriteTransport()
    let service = BearService(
        configuration: makeInsertConfiguration(templateManagementEnabled: true),
        readStore: InsertReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceInsertTests")
    )

    try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        _ = try await service.insertText([
            InsertTextRequest(
                noteID: "note-1",
                text: "Line 2",
                position: .bottom,
                presentation: BearPresentationOptions()
            ),
        ])
    }

    let insertRequest = try #require(await transport.insertRequests.first)
    #expect(insertRequest.noteID == "note-1")
    #expect(insertRequest.text == "Line 2")
    #expect(insertRequest.position == .bottom)
    #expect(await transport.replaceCalls.isEmpty)
}

@Test
func insertTextFallsBackToDirectInsertWhenTemplateManagementIsDisabled() async throws {
    let note = makeInsertSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nLine 1",
        tags: ["0-inbox"]
    )
    let transport = InsertRecordingWriteTransport()
    let service = BearService(
        configuration: makeInsertConfiguration(templateManagementEnabled: false),
        readStore: InsertReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceInsertTests")
    )

    try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        _ = try await service.insertText([
            InsertTextRequest(
                noteID: "note-1",
                text: "Line 2",
                position: .bottom,
                presentation: BearPresentationOptions()
            ),
        ])
    }

    let insertRequest = try #require(await transport.insertRequests.first)
    #expect(insertRequest.noteID == "note-1")
    #expect(await transport.replaceCalls.isEmpty)
}

@Test
func insertTextUsesReplaceAllForRelativeHeadingTargetOnPlainNote() async throws {
    let note = makeInsertSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "## Tasks\nLine 1",
        tags: ["0-inbox"]
    )
    let transport = InsertRecordingWriteTransport()
    let service = BearService(
        configuration: makeInsertConfiguration(templateManagementEnabled: false),
        readStore: InsertReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceInsertTests")
    )

    _ = try await service.insertText([
        InsertTextRequest(
            noteID: "note-1",
            text: "Line 2",
            target: RelativeTextTarget(text: "Tasks", targetKind: .heading, placement: .after),
            presentation: BearPresentationOptions()
        ),
    ])

    #expect(await transport.insertRequests.isEmpty)
    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == "# Inbox\n\n## Tasks\nLine 2\nLine 1")
}

@Test
func insertTextRejectsAmbiguousRelativeStringTargetBeforeWriting() async throws {
    let note = makeInsertSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1\n\nLine 1",
        tags: ["0-inbox"]
    )
    let transport = InsertRecordingWriteTransport()
    let service = BearService(
        configuration: makeInsertConfiguration(templateManagementEnabled: false),
        readStore: InsertReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceInsertTests")
    )

    await #expect(throws: BearError.self) {
        _ = try await service.insertText([
            InsertTextRequest(
                noteID: "note-1",
                text: "Inserted",
                target: RelativeTextTarget(text: "Line 1", placement: .after),
                presentation: BearPresentationOptions()
            ),
        ])
    }

    #expect(await transport.insertRequests.isEmpty)
    #expect(await transport.replaceCalls.isEmpty)
}

private func makeInsertConfiguration(templateManagementEnabled: Bool) -> BearConfiguration {
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
        defaultSnippetLength: 280,
        backupRetentionDays: 30
    )
}

private func makeInsertSourceNote(
    id: String,
    title: String,
    body: String,
    tags: [String]
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
        archived: false,
        trashed: false,
        encrypted: false
    )
}

private final class InsertReadStore: @unchecked Sendable, BearReadStore {
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

private actor InsertRecordingWriteTransport: BearWriteTransport {
    struct ReplaceCall: Sendable {
        let noteID: String
        let fullText: String
        let presentation: BearPresentationOptions
    }

    private(set) var insertRequests: [InsertTextRequest] = []
    private(set) var replaceCalls: [ReplaceCall] = []

    func resolveSelectedNoteID(token _: String) async throws -> String {
        "selected-note"
    }

    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: "created", title: request.title, status: "created", modifiedAt: nil)
    }

    func insertText(_ request: InsertTextRequest) async throws -> MutationReceipt {
        insertRequests.append(request)
        return MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func replaceAll(noteID: String, fullText: String, presentation: BearPresentationOptions) async throws -> MutationReceipt {
        replaceCalls.append(ReplaceCall(noteID: noteID, fullText: fullText, presentation: presentation))
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
