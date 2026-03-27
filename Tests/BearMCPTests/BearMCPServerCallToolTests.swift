@testable import BearMCP
import BearApplication
import BearCore
import Foundation
import Logging
import MCP
import Testing

#if canImport(System)
    import System
#else
    @preconcurrency import SystemPackage
#endif

@Test(.timeLimit(.minutes(1)))
func bearReplaceContentAcceptsEmptyNewStringForStringReplacement() async throws {
    let note = BearNote(
        ref: NoteRef(identifier: "note-1"),
        revision: NoteRevision(
            version: 3,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_710_000_500)
        ),
        title: "Test Note",
        body: "Body with #test and #keep",
        rawText: "# Test Note\n\nBody with #test and #keep",
        tags: ["test", "keep"],
        archived: false,
        trashed: false,
        encrypted: false
    )
    let configuration = BearConfiguration(
        databasePath: "/tmp/bear.sqlite",
        activeTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: false,
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
    let writeTransport = MCPToolRecordingWriteTransport()
    let service = BearService(
        configuration: configuration,
        readStore: MCPToolReadStore(note: note),
        writeTransport: writeTransport,
        logger: Logger(label: "BearMCPServerCallToolTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await BearMCPServer(service: service, configuration: configuration).makeServer()
    let client = Client(name: "BearMCPTestClient", version: "1.0")

    do {
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)

        let result = try await client.callTool(
            name: "bear_replace_content",
            arguments: [
                "operations": .array([
                    .object([
                        "note": .string("Test Note"),
                        "kind": .string("string"),
                        "old_string": .string("#test"),
                        "new_string": .string(""),
                        "occurrence": .string("one"),
                    ]),
                ]),
            ]
        )

        #expect(result.isError != true)

        let replaceCall = try #require(await writeTransport.replaceCalls.first)
        #expect(replaceCall.noteID == "note-1")
        #expect(replaceCall.fullText == "# Test Note\n\nBody with  and #keep")
    } catch {
        await server.stop()
        await client.disconnect()
        try? clientToServerRead.close()
        try? clientToServerWrite.close()
        try? serverToClientRead.close()
        try? serverToClientWrite.close()
        throw error
    }

    await server.stop()
    await client.disconnect()
    try? clientToServerRead.close()
    try? clientToServerWrite.close()
    try? serverToClientRead.close()
    try? serverToClientWrite.close()
}

private struct MCPToolReadStore: BearReadStore {
    let note: BearNote

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func note(id: String) throws -> BearNote? { id == note.ref.identifier ? note : nil }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func notes(titled title: String, location: BearNoteLocation) throws -> [BearNote] {
        location == .notes && title.caseInsensitiveCompare(note.title) == .orderedSame ? [note] : []
    }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private actor MCPToolRecordingWriteTransport: BearWriteTransport {
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
