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
                expectedVersion: note.revision.version,
                presentation: BearPresentationOptions()
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == "# Inbox\n\n---\n#0-inbox\n---\nLine 2")
}

@Test
func replaceContentBodyRequiresExpectedVersion() async throws {
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

    let receipts = try await service.replaceContent([
        ReplaceContentRequest(
            noteID: "note-1",
            kind: .body,
            oldString: nil,
            occurrence: nil,
            newString: "Line 2",
            presentation: BearPresentationOptions()
        ),
    ])

    let receipt = try #require(receipts.first)
    #expect(receipt.status == "invalid")
    #expect(receipt.conflict?.reason == "missing_expected_version")
    #expect(receipt.conflict?.resolution == .readNoteAgain)
}

@Test
func replaceContentBodyRejectsStaleExpectedVersion() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: ["0-inbox"]
    )
    let noteContextStore = BearNoteReadContextStore()
    noteContextStore.remember(noteID: "note-1", version: note.revision.version - 1, content: "Line 0")
    let service = BearService(
        configuration: makeReplaceContentConfiguration(templateManagementEnabled: false),
        readStore: ReplaceContentReadStore(noteByID: ["note-1": note]),
        writeTransport: ReplaceContentRecordingWriteTransport(),
        noteContextStore: noteContextStore,
        logger: Logger(label: "BearServiceReplaceContentTests")
    )

    let receipts = try await service.replaceContent([
        ReplaceContentRequest(
            noteID: "note-1",
            kind: .body,
            oldString: nil,
            occurrence: nil,
            newString: "Line 2",
            expectedVersion: note.revision.version - 1,
            presentation: BearPresentationOptions()
        ),
    ])

    let receipt = try #require(receipts.first)
    #expect(receipt.status == "conflict")
    #expect(receipt.conflict?.reason == "version_mismatch")
    #expect(receipt.conflict?.resolution == .retryWithConflictToken)
    #expect(receipt.conflict?.conflictToken != nil)
    #expect(receipt.conflict?.hunks.isEmpty == false)
}

@Test
func replaceContentStringIgnoresExpectedVersion() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
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
            oldString: "Line 1",
            occurrence: .one,
            newString: "Line 2",
            expectedVersion: note.revision.version,
            presentation: BearPresentationOptions()
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == "# Inbox\n\nLine 2")
}

@Test
func replaceContentTitleIgnoresExpectedVersion() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
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
            kind: .title,
            oldString: nil,
            occurrence: nil,
            newString: "Projects",
            expectedVersion: note.revision.version,
            presentation: BearPresentationOptions()
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == "# Projects\n\nLine 1")
}

@Test
func replaceContentBodyRejectsStaleExpectedVersionWithoutLeakingCurrentVersion() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: ["0-inbox"]
    )
    let noteContextStore = BearNoteReadContextStore()
    noteContextStore.remember(noteID: "note-1", version: note.revision.version - 1, content: "Line 0")
    let service = BearService(
        configuration: makeReplaceContentConfiguration(templateManagementEnabled: false),
        readStore: ReplaceContentReadStore(noteByID: ["note-1": note]),
        writeTransport: ReplaceContentRecordingWriteTransport(),
        noteContextStore: noteContextStore,
        logger: Logger(label: "BearServiceReplaceContentTests")
    )

    let receipts = try await service.replaceContent([
        ReplaceContentRequest(
            noteID: "note-1",
            kind: .body,
            oldString: nil,
            occurrence: nil,
            newString: "Line 2",
            expectedVersion: note.revision.version - 1,
            presentation: BearPresentationOptions()
        ),
    ])

    let receipt = try #require(receipts.first)
    let conflict = try #require(receipt.conflict)
    #expect(conflict.message.contains("current Bear note `version`") == false)
    #expect(conflict.message.contains("version 3") == false)
    #expect(conflict.hunks.allSatisfy { hunk in
        (hunk.previousExcerpt?.contains("version 3") ?? false) == false &&
            (hunk.currentExcerpt?.contains("version 3") ?? false) == false
    })
}

@Test
func replaceContentBodyAcceptsSingleRetryConflictTokenForSameRequestedBody() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Current line",
        tags: ["0-inbox"]
    )
    let noteContextStore = BearNoteReadContextStore()
    noteContextStore.remember(noteID: "note-1", version: note.revision.version - 1, content: "Previous line")
    let transport = ReplaceContentRecordingWriteTransport()
    let service = BearService(
        configuration: makeReplaceContentConfiguration(templateManagementEnabled: false),
        readStore: ReplaceContentReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        noteContextStore: noteContextStore,
        logger: Logger(label: "BearServiceReplaceContentTests")
    )

    let conflictReceipts = try await service.replaceContent([
        ReplaceContentRequest(
            noteID: "note-1",
            kind: .body,
            oldString: nil,
            occurrence: nil,
            newString: "Replacement body",
            expectedVersion: note.revision.version - 1,
            presentation: BearPresentationOptions()
        ),
    ])

    let conflictToken = try #require(conflictReceipts.first?.conflict?.conflictToken)
    let retryReceipts = try await service.replaceContent([
        ReplaceContentRequest(
            noteID: "note-1",
            kind: .body,
            oldString: nil,
            occurrence: nil,
            newString: "Replacement body",
            conflictToken: conflictToken,
            presentation: BearPresentationOptions()
        ),
    ])

    #expect(retryReceipts.first?.status == "updated")
    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == "# Inbox\n\nReplacement body")
}

@Test
func replaceContentBodyRejectsTooLargeConflictSummaryWithoutToken() async throws {
    let previousLines = (1 ... 250).map { "Old line \($0)" }.joined(separator: "\n")
    let currentLines = (1 ... 250).map { "Current line \($0)" }.joined(separator: "\n")
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: currentLines,
        tags: ["0-inbox"]
    )
    let noteContextStore = BearNoteReadContextStore()
    noteContextStore.remember(noteID: "note-1", version: note.revision.version - 1, content: previousLines)
    let service = BearService(
        configuration: makeReplaceContentConfiguration(templateManagementEnabled: false),
        readStore: ReplaceContentReadStore(noteByID: ["note-1": note]),
        writeTransport: ReplaceContentRecordingWriteTransport(),
        noteContextStore: noteContextStore,
        logger: Logger(label: "BearServiceReplaceContentTests")
    )

    let receipts = try await service.replaceContent([
        ReplaceContentRequest(
            noteID: "note-1",
            kind: .body,
            oldString: nil,
            occurrence: nil,
            newString: "Replacement body",
            expectedVersion: note.revision.version - 1,
            presentation: BearPresentationOptions()
        ),
    ])

    let conflict = try #require(receipts.first?.conflict)
    #expect(conflict.resolution == .readNoteAgain)
    #expect(conflict.diffTooLarge == true)
    #expect(conflict.truncated == true)
    #expect(conflict.conflictToken == nil)
}

@Test
func replaceContentBodyTreatsLiteralEllipsisAsSmallConflictNotTruncation() async throws {
    let note = makeReplaceContentSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Alpha line\nBeta line\nGamma line\n\nAnother line\nPlease edit this note...",
        tags: ["0-inbox"]
    )
    let noteContextStore = BearNoteReadContextStore()
    noteContextStore.remember(
        noteID: "note-1",
        version: note.revision.version - 1,
        content: "Alpha line\nBeta line\nGamma line\n\nPlease edit this note before the next tool call."
    )
    let service = BearService(
        configuration: makeReplaceContentConfiguration(templateManagementEnabled: false),
        readStore: ReplaceContentReadStore(noteByID: ["note-1": note]),
        writeTransport: ReplaceContentRecordingWriteTransport(),
        noteContextStore: noteContextStore,
        logger: Logger(label: "BearServiceReplaceContentTests")
    )

    let receipts = try await service.replaceContent([
        ReplaceContentRequest(
            noteID: "note-1",
            kind: .body,
            oldString: nil,
            occurrence: nil,
            newString: "Replacement body",
            expectedVersion: note.revision.version - 1,
            presentation: BearPresentationOptions()
        ),
    ])

    let conflict = try #require(receipts.first?.conflict)
    #expect(conflict.resolution == .retryWithConflictToken)
    #expect(conflict.diffTooLarge == false)
    #expect(conflict.truncated == false)
    #expect(conflict.conflictToken != nil)
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
                presentation: BearPresentationOptions()
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
                expectedVersion: note.revision.version,
                presentation: BearPresentationOptions()
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
            presentation: BearPresentationOptions()
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
                presentation: BearPresentationOptions()
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
                presentation: BearPresentationOptions()
            ),
        ])
    }
}

private func makeReplaceContentConfiguration(templateManagementEnabled: Bool) -> BearConfiguration {
    BearConfiguration(
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
