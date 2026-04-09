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
func donationTrackingIgnoresInitializeListsAndFailures() async throws {
    let runtimeStateStoreURL = temporaryRuntimeStateDatabaseURL()
    let runtimeStateStore = BearRuntimeStateStore(databaseURL: runtimeStateStoreURL)

    try await withUsageTrackingClient(runtimeStateStore: runtimeStateStore) { client in
        _ = try await client.listTools()
        _ = try await client.listResources()

        let failed = try await client.callTool(
            name: "bear_find_notes_by_tag",
            arguments: [
                "operations": .array([
                    .object([:]),
                ]),
            ]
        )

        #expect(failed.isError == true)

        let snapshot = try await runtimeStateStore.loadDonationPromptSnapshot()
        #expect(snapshot.totalSuccessfulOperationCount == 0)
        #expect(snapshot.isPromptEligible == false)
    }
}

@Test(.timeLimit(.minutes(1)))
func donationTrackingCountsSuccessfulOperationsInsideBatches() async throws {
    let runtimeStateStoreURL = temporaryRuntimeStateDatabaseURL()
    let runtimeStateStore = BearRuntimeStateStore(databaseURL: runtimeStateStoreURL)

    try await withUsageTrackingClient(runtimeStateStore: runtimeStateStore) { client in
        let result = try await client.callTool(
            name: "bear_find_notes_by_inbox_tags",
            arguments: [
                "operations": .array([
                    .object([
                        "id": .string("first"),
                    ]),
                    .object([
                        "id": .string("second"),
                        "location": .string("archive"),
                    ]),
                ]),
            ]
        )

        #expect(result.isError != true, "Tool error: \(result.content)")

        let snapshot = try await runtimeStateStore.loadDonationPromptSnapshot()
        #expect(snapshot.totalSuccessfulOperationCount == 2)
        #expect(snapshot.isPromptEligible == false)
    }
}

private func withUsageTrackingClient<T: Sendable>(
    runtimeStateStore: BearRuntimeStateStore,
    _ operation: @Sendable (Client) async throws -> T
) async throws -> T {
    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: false,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30
    )
    let service = BearService(
        configuration: configuration,
        readStore: UsageTrackingReadStore(),
        writeTransport: UsageTrackingWriteTransport(),
        logger: Logger(label: "UrsusMCPServerUsageTrackingTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(
        service: service,
        configuration: configuration,
        runtimeStateStore: runtimeStateStore
    ).makeServer()
    let client = Client(name: "BearMCPUsageTrackingClient", version: "1.0")

    do {
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)
        let value = try await operation(client)
        await server.stop()
        await client.disconnect()
        try? clientToServerRead.close()
        try? clientToServerWrite.close()
        try? serverToClientRead.close()
        try? serverToClientWrite.close()
        return value
    } catch {
        await server.stop()
        await client.disconnect()
        try? clientToServerRead.close()
        try? clientToServerWrite.close()
        try? serverToClientRead.close()
        try? serverToClientWrite.close()
        throw error
    }
}

private struct UsageTrackingReadStore: BearReadStore {
    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch {
        DiscoveryNoteBatch(notes: [], hasMore: false)
    }

    func note(id: String) throws -> BearNote? { nil }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func notes(titled title: String, location: BearNoteLocation) throws -> [BearNote] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private actor UsageTrackingWriteTransport: BearWriteTransport {
    func resolveSelectedNoteID(token: String) async throws -> String { "note-1" }

    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: "created-note", title: request.title, status: "created", modifiedAt: nil)
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

private func temporaryRuntimeStateDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("runtime-state.sqlite", isDirectory: false)
}
