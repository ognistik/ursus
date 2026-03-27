import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func createNotesMergesActiveTagsStripsDuplicateTitleAndRendersSingleTemplate() async throws {
    let transport = RecordingWriteTransport()
    let configuration = BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        activeTags: ["0-inbox", "#Daily", "#deep work#"],
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
        backupRetentionDays: 30
    )
    let service = BearService(
        configuration: configuration,
        readStore: EmptyReadStore(),
        writeTransport: transport,
        logger: Logger(label: "BearServiceCreateTests")
    )

    try await withTemporaryNoteTemplate("{{content}}\n\n{{tags}}\n") {
        _ = try await service.createNotes([
            CreateNoteRequest(
                title: "Sample Note",
                content: "# Sample Note\n\nBody line",
                tags: ["project-x", "#daily", "deep work"],
                useOnlyRequestTags: nil,
                presentation: BearPresentationOptions(openNote: true, newWindow: true, showWindow: true, edit: true)
            ),
        ])
    }

    let captured = try #require(await transport.createdRequests.first)
    #expect(captured.title == "Sample Note")
    #expect(captured.content == "Body line\n\n#0-inbox #Daily #deep work# #project-x")
    #expect(captured.tags == ["0-inbox", "Daily", "deep work", "project-x"])
}

@Test
func createNotesCanReplaceActiveTagsWithExplicitRequestTags() async throws {
    let transport = RecordingWriteTransport()
    let configuration = BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        activeTags: ["0-inbox", "daily"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        openNoteInEditModeByDefault: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsActiveTagsByDefault: true,
        tagsMergeMode: .replace,
        defaultDiscoveryLimit: 20,
        maxDiscoveryLimit: 100,
        defaultSnippetLength: 280,
        maxSnippetLength: 1_000,
        backupRetentionDays: 30
    )
    let service = BearService(
        configuration: configuration,
        readStore: EmptyReadStore(),
        writeTransport: transport,
        logger: Logger(label: "BearServiceCreateTests")
    )

    try await withTemporaryNoteTemplate("{{content}}\n\n{{tags}}\n") {
        _ = try await service.createNotes([
            CreateNoteRequest(
                title: "Sample Note",
                content: "Body line",
                tags: ["project-x"],
                useOnlyRequestTags: nil,
                presentation: BearPresentationOptions(openNote: true, newWindow: true, showWindow: true, edit: true)
            ),
        ])
    }

    let captured = try #require(await transport.createdRequests.first)
    #expect(captured.content == "Body line\n\n#project-x")
    #expect(captured.tags == ["project-x"])
}

@Test
func createNotesCanUseOnlyRequestTagsPerRequest() async throws {
    let transport = RecordingWriteTransport()
    let configuration = BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        activeTags: ["0-inbox", "daily"],
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
        backupRetentionDays: 30
    )
    let service = BearService(
        configuration: configuration,
        readStore: EmptyReadStore(),
        writeTransport: transport,
        logger: Logger(label: "BearServiceCreateTests")
    )

    try await withTemporaryNoteTemplate("{{content}}\n\n{{tags}}\n") {
        _ = try await service.createNotes([
            CreateNoteRequest(
                title: "Sample Note",
                content: "Body line",
                tags: ["project-x"],
                useOnlyRequestTags: true,
                presentation: BearPresentationOptions(openNote: true, newWindow: true, showWindow: true, edit: true)
            ),
        ])
    }

    let captured = try #require(await transport.createdRequests.first)
    #expect(captured.content == "Body line\n\n#project-x")
    #expect(captured.tags == ["project-x"])
    #expect(captured.useOnlyRequestTags == true)
}

@Test
func createNotesCanExplicitlyAppendActiveTagsPerRequest() async throws {
    let transport = RecordingWriteTransport()
    let configuration = BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        activeTags: ["0-inbox", "daily"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        openNoteInEditModeByDefault: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsActiveTagsByDefault: true,
        tagsMergeMode: .replace,
        defaultDiscoveryLimit: 20,
        maxDiscoveryLimit: 100,
        defaultSnippetLength: 280,
        maxSnippetLength: 1_000,
        backupRetentionDays: 30
    )
    let service = BearService(
        configuration: configuration,
        readStore: EmptyReadStore(),
        writeTransport: transport,
        logger: Logger(label: "BearServiceCreateTests")
    )

    try await withTemporaryNoteTemplate("{{content}}\n\n{{tags}}\n") {
        _ = try await service.createNotes([
            CreateNoteRequest(
                title: "Sample Note",
                content: "Body line",
                tags: ["project-x"],
                useOnlyRequestTags: false,
                presentation: BearPresentationOptions(openNote: true, newWindow: true, showWindow: true, edit: true)
            ),
        ])
    }

    let captured = try #require(await transport.createdRequests.first)
    #expect(captured.content == "Body line\n\n#0-inbox #daily #project-x")
    #expect(captured.tags == ["0-inbox", "daily", "project-x"])
    #expect(captured.useOnlyRequestTags == false)
}

private struct EmptyReadStore: BearReadStore {
    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func note(id: String) throws -> BearNote? { nil }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private actor RecordingWriteTransport: BearWriteTransport {
    private(set) var createdRequests: [CreateNoteRequest] = []
    private(set) var openedTags: [OpenTagRequest] = []
    private(set) var renamedTags: [RenameTagRequest] = []

    func resolveSelectedNoteID(token _: String) async throws -> String {
        "selected-note"
    }

    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        createdRequests.append(request)
        return MutationReceipt(noteID: "created", title: request.title, status: "created", modifiedAt: nil)
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
        openedTags.append(request)
        return TagMutationReceipt(tag: request.tag, newTag: nil, status: "opened")
    }

    func renameTag(_ request: RenameTagRequest) async throws -> TagMutationReceipt {
        renamedTags.append(request)
        return TagMutationReceipt(tag: request.name, newTag: request.newName, status: "renamed")
    }

    func deleteTag(_ request: DeleteTagRequest) async throws -> TagMutationReceipt {
        TagMutationReceipt(tag: request.name, newTag: nil, status: "deleted")
    }

    func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        MutationReceipt(noteID: noteID, title: nil, status: "archived", modifiedAt: nil)
    }
}
