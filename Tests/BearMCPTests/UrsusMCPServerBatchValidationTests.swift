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
func batchedToolValidationMatrixNormalizesOperationsContract() async throws {
    let cases: [BatchValidationCase] = [
        .init(
            tool: "bear_find_notes_by_inbox_tags",
            invalidOperation: .object(["match": .string("nope")]),
            invalidError: "Invalid tag match mode 'nope'.",
            emptyOperationShouldSucceed: true,
            validOperation: .object(["location": .string("archive"), "match": .string("all")])
        ),
        .init(
            tool: "bear_find_notes_by_tag",
            invalidOperation: .object([:]),
            invalidError: "Missing required array argument 'tags'.",
            validOperation: .object(["tags": .array([.string("project-x")])])
        ),
        .init(
            tool: "bear_create_notes",
            invalidOperation: .object([:]),
            invalidError: "Missing required string argument 'title'.",
            validOperation: .object([
                "title": .string("Test Note"),
                "content": .string("Body"),
            ])
        ),
        .init(
            tool: "bear_rename_tags",
            invalidOperation: .object([:]),
            invalidError: "Missing required string argument 'name'.",
            validOperation: .object([
                "name": .string("old-tag"),
                "new_name": .string("new-tag"),
            ])
        ),
        .init(
            tool: "bear_delete_tags",
            invalidOperation: .object([:]),
            invalidError: "Missing required string argument 'name'.",
            validOperation: .object([
                "name": .string("old-tag"),
            ])
        ),
    ]

    try await withBatchValidationClient { client in
        for testCase in cases {
            try await assertToolError(
                client: client,
                tool: testCase.tool,
                arguments: [:],
                expectedError: "Missing required array argument 'operations'."
            )

            try await assertToolError(
                client: client,
                tool: testCase.tool,
                arguments: ["operations": .array([])],
                expectedError: "`operations` must contain at least one operation object."
            )

            if testCase.emptyOperationShouldSucceed {
                try await assertToolSuccess(
                    client: client,
                    tool: testCase.tool,
                    arguments: ["operations": .array([.object([:])])]
                )
            }

            try await assertToolError(
                client: client,
                tool: testCase.tool,
                arguments: ["operations": .array([testCase.invalidOperation])],
                expectedError: testCase.invalidError
            )

            try await assertToolSuccess(
                client: client,
                tool: testCase.tool,
                arguments: ["operations": .array([testCase.validOperation])]
            )
        }
    }
}

private struct BatchValidationCase {
    let tool: String
    let invalidOperation: Value
    let invalidError: String
    let emptyOperationShouldSucceed: Bool
    let validOperation: Value

    init(
        tool: String,
        invalidOperation: Value,
        invalidError: String,
        emptyOperationShouldSucceed: Bool = false,
        validOperation: Value
    ) {
        self.tool = tool
        self.invalidOperation = invalidOperation
        self.invalidError = invalidError
        self.emptyOperationShouldSucceed = emptyOperationShouldSucceed
        self.validOperation = validOperation
    }
}

private func withBatchValidationClient<T: Sendable>(
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
        readStore: BatchValidationReadStore(),
        writeTransport: BatchValidationWriteTransport(),
        logger: Logger(label: "UrsusMCPServerBatchValidationTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(service: service, configuration: configuration).makeServer()
    let client = Client(name: "BearMCPBatchValidationClient", version: "1.0")

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

private func assertToolError(
    client: Client,
    tool: String,
    arguments: [String: Value],
    expectedError: String
) async throws {
    let result = try await client.callTool(name: tool, arguments: arguments)
    #expect(result.isError == true)
    #expect(try toolResultText(result) == expectedError)
}

private func assertToolSuccess(
    client: Client,
    tool: String,
    arguments: [String: Value]
) async throws {
    let result = try await client.callTool(name: tool, arguments: arguments)
    #expect(result.isError != true, "Tool error: \(result.content)")
}

private func toolResultText(_ result: (content: [Tool.Content], isError: Bool?)) throws -> String {
    let first = try #require(result.content.first)
    switch first {
    case .text(let text, _, _):
        return text
    default:
        throw BatchValidationTestError.unexpectedToolContent
    }
}

private enum BatchValidationTestError: Error {
    case unexpectedToolContent
}

private struct BatchValidationReadStore: BearReadStore {
    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch {
        DiscoveryNoteBatch(notes: [], hasMore: false)
    }

    func note(id: String) throws -> BearNote? { nil }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func notes(titled title: String, location: BearNoteLocation) throws -> [BearNote] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private actor BatchValidationWriteTransport: BearWriteTransport {
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
