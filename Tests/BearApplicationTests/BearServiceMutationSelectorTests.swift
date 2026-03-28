import BearApplication
import BearCore
import Foundation
import Logging
import Testing

private final class EmptySelectedNoteTokenStore: BearSelectedNoteTokenStore, @unchecked Sendable {
    func readToken() throws -> String? { nil }
    func saveToken(_ token: String) throws {}
    func removeToken() throws {}
}

@Test
func replaceContentResolvesExactCaseInsensitiveTitleSelector() async throws {
    let note = makeMutationSelectorNote(id: "note-1", title: "Inbox", body: "Line 1")
    let transport = MutationSelectorRecordingWriteTransport()
    let service = BearService(
        configuration: makeMutationSelectorConfiguration(),
        readStore: MutationSelectorReadStore(noteByID: ["note-1": note], notesByTitle: ["inbox": [note]]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceMutationSelectorTests")
    )

    _ = try await service.replaceContent([
        ReplaceContentRequest(
            noteID: " inbox ",
            kind: .body,
            oldString: nil,
            occurrence: nil,
            newString: "Updated",
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.noteID == "note-1")
    #expect(replaceCall.fullText == "# Inbox\n\nUpdated")
}

@Test
func replaceContentTitleCanAddTitleToTitlelessNote() async throws {
    let note = makeMutationSelectorNote(
        id: "note-1",
        title: "",
        body: "Line 1",
        rawText: "Line 1"
    )
    let transport = MutationSelectorRecordingWriteTransport()
    let service = BearService(
        configuration: makeMutationSelectorConfiguration(),
        readStore: MutationSelectorReadStore(noteByID: ["note-1": note], notesByTitle: [:]),
        writeTransport: transport,
        tokenStore: EmptySelectedNoteTokenStore(),
        logger: Logger(label: "BearServiceMutationSelectorTests")
    )

    _ = try await service.replaceContent([
        ReplaceContentRequest(
            noteID: "note-1",
            kind: .title,
            oldString: nil,
            occurrence: nil,
            newString: "Inbox",
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == "# Inbox\n\nLine 1")
}

@Test
func addFilesOpenNotesAndArchiveResolveTitleSelectors() async throws {
    let note = makeMutationSelectorNote(id: "note-1", title: "Inbox", body: "Line 1")
    let transport = MutationSelectorRecordingWriteTransport()
    let service = BearService(
        configuration: makeMutationSelectorConfiguration(),
        readStore: MutationSelectorReadStore(noteByID: ["note-1": note], notesByTitle: ["inbox": [note]]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceMutationSelectorTests")
    )

    _ = try await service.addFiles([
        AddFileRequest(
            noteID: "Inbox",
            filePath: "/tmp/file.txt",
            position: .bottom,
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])
    _ = try await service.openNotes([
        OpenNoteRequest(noteID: "INBOX", presentation: BearPresentationOptions(openNote: true))
    ])
    _ = try await service.archiveNotes(["inbox"])

    let addFileRequest = try #require(await transport.addFileRequests.first)
    let openRequest = try #require(await transport.openRequests.first)
    let archivedNoteID = try #require(await transport.archivedNoteIDs.first)
    #expect(addFileRequest.noteID == "note-1")
    #expect(openRequest.noteID == "note-1")
    #expect(archivedNoteID == "note-1")
}

@Test
func mutationSelectorsPreferExactIDOverSameNamedTitle() async throws {
    let exactIDMatch = makeMutationSelectorNote(id: "shared-selector", title: "Exact ID", body: "Body")
    let titleOnlyMatch = makeMutationSelectorNote(id: "title-only", title: "shared-selector", body: "Other")
    let transport = MutationSelectorRecordingWriteTransport()
    let service = BearService(
        configuration: makeMutationSelectorConfiguration(),
        readStore: MutationSelectorReadStore(
            noteByID: ["shared-selector": exactIDMatch],
            notesByTitle: ["shared-selector": [titleOnlyMatch]]
        ),
        writeTransport: transport,
        logger: Logger(label: "BearServiceMutationSelectorTests")
    )

    _ = try await service.openNotes([
        OpenNoteRequest(noteID: "shared-selector", presentation: BearPresentationOptions(openNote: true))
    ])

    let openRequest = try #require(await transport.openRequests.first)
    #expect(openRequest.noteID == "shared-selector")
}

@Test
func mutationSelectorsRejectAmbiguousTitleMatches() async throws {
    let first = makeMutationSelectorNote(id: "note-1", title: "Inbox", body: "Body")
    let second = makeMutationSelectorNote(id: "note-2", title: "Inbox", body: "Other", archived: true)
    let transport = MutationSelectorRecordingWriteTransport()
    let service = BearService(
        configuration: makeMutationSelectorConfiguration(),
        readStore: MutationSelectorReadStore(
            noteByID: [:],
            notesByTitle: ["inbox": [first, second]]
        ),
        writeTransport: transport,
        logger: Logger(label: "BearServiceMutationSelectorTests")
    )

    do {
        _ = try await service.openNotes([
            OpenNoteRequest(noteID: "Inbox", presentation: BearPresentationOptions(openNote: true))
        ])
        Issue.record("Expected ambiguous selector error.")
    } catch let error as BearError {
        guard case .ambiguous(let message) = error else {
            Issue.record("Expected ambiguous selector error, got \(error).")
            return
        }
        #expect(message.contains("matched 2 notes"))
    }

    #expect(await transport.openRequests.isEmpty)
}

@Test
func resolveNoteTargetsResolvesSelectedNoteOnlyOncePerBatch() async throws {
    let note = makeMutationSelectorNote(id: "note-1", title: "Inbox", body: "Body")
    let transport = MutationSelectorRecordingWriteTransport(selectedNoteID: "selected-note")
    let service = BearService(
        configuration: makeMutationSelectorConfiguration(token: "secret-token"),
        readStore: MutationSelectorReadStore(noteByID: ["note-1": note], notesByTitle: ["inbox": [note]]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceMutationSelectorTests")
    )

    let resolved = try await service.resolveNoteTargets([
        .selected,
        .selector("Inbox"),
        .selected,
    ])

    #expect(resolved == ["selected-note", "Inbox", "selected-note"])
    #expect(await transport.selectedNoteResolutionCount == 1)
}

@Test
func resolveSelectedNoteIDRequiresConfiguredToken() async {
    let note = makeMutationSelectorNote(id: "note-1", title: "Inbox", body: "Body")
    let transport = MutationSelectorRecordingWriteTransport()
    let service = BearService(
        configuration: makeMutationSelectorConfiguration(),
        readStore: MutationSelectorReadStore(noteByID: ["note-1": note], notesByTitle: [:]),
        writeTransport: transport,
        tokenStore: EmptySelectedNoteTokenStore(),
        logger: Logger(label: "BearServiceMutationSelectorTests")
    )

    do {
        _ = try await service.resolveSelectedNoteID()
        Issue.record("Expected missing-token error.")
    } catch let error as BearError {
        guard case .invalidInput(let message) = error else {
            Issue.record("Expected invalid-input error, got \(error).")
            return
        }
        #expect(message.contains("configured Bear API token"))
    } catch {
        Issue.record("Expected BearError.invalidInput, got \(error).")
    }
}

private func makeMutationSelectorConfiguration(token: String? = nil) -> BearConfiguration {
    BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        activeTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        openNoteInEditModeByDefault: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsActiveTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        maxDiscoveryLimit: 100,
        defaultSnippetLength: 280,
        maxSnippetLength: 1_000,
        backupRetentionDays: 30,
        token: token
    )
}

private func makeMutationSelectorNote(
    id: String,
    title: String,
    body: String,
    rawText: String? = nil,
    archived: Bool = false
) -> BearNote {
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
    let modifiedAt = Date(timeIntervalSince1970: 1_710_000_500)

    return BearNote(
        ref: NoteRef(identifier: id),
        revision: NoteRevision(version: 3, createdAt: createdAt, modifiedAt: modifiedAt),
        title: title,
        body: body,
        rawText: rawText ?? BearText.composeRawText(title: title, body: body),
        tags: ["0-inbox"],
        archived: archived,
        trashed: false,
        encrypted: false
    )
}

private final class MutationSelectorReadStore: @unchecked Sendable, BearReadStore {
    private let noteByID: [String: BearNote]
    private let notesByTitle: [String: [BearNote]]

    init(noteByID: [String: BearNote], notesByTitle: [String: [BearNote]]) {
        self.noteByID = noteByID
        self.notesByTitle = notesByTitle
    }

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func note(id: String) throws -> BearNote? { noteByID[id] }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }

    func notes(titled title: String, location: BearNoteLocation) throws -> [BearNote] {
        let matches = notesByTitle[title.lowercased()] ?? []
        return matches.filter { note in
            switch location {
            case .notes:
                return note.archived == false && note.trashed == false
            case .archive:
                return note.archived && note.trashed == false
            }
        }
    }
}

private actor MutationSelectorRecordingWriteTransport: BearWriteTransport {
    struct ReplaceCall: Sendable {
        let noteID: String
        let fullText: String
    }

    private(set) var replaceCalls: [ReplaceCall] = []
    private(set) var addFileRequests: [AddFileRequest] = []
    private(set) var openRequests: [OpenNoteRequest] = []
    private(set) var archivedNoteIDs: [String] = []
    private(set) var selectedNoteResolutionCount = 0
    private let selectedNoteID: String

    init(selectedNoteID: String = "selected-note") {
        self.selectedNoteID = selectedNoteID
    }

    func resolveSelectedNoteID(token _: String) async throws -> String {
        selectedNoteResolutionCount += 1
        return selectedNoteID
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
        addFileRequests.append(request)
        return MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func open(_ request: OpenNoteRequest) async throws -> MutationReceipt {
        openRequests.append(request)
        return MutationReceipt(noteID: request.noteID, title: nil, status: "opened", modifiedAt: nil)
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
        archivedNoteIDs.append(noteID)
        return MutationReceipt(noteID: noteID, title: nil, status: "archived", modifiedAt: nil)
    }
}
