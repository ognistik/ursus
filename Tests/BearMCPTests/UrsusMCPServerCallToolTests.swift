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
func mcpServerInitializeAdvertisesUrsusTitle() async throws {
    let note = BearNote(
        ref: NoteRef(identifier: "note-1"),
        revision: NoteRevision(
            version: 1,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_710_000_500)
        ),
        title: "Test Note",
        body: "Body",
        rawText: "# Test Note\n\nBody",
        tags: [],
        archived: false,
        trashed: false,
        encrypted: false
    )
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
        readStore: MCPToolReadStore(note: note),
        writeTransport: MCPToolRecordingWriteTransport(),
        logger: Logger(label: "UrsusMCPServerCallToolTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(service: service, configuration: configuration).makeServer()
    let client = Client(name: "BearMCPTestClient", version: "1.0")

    do {
        try await server.start(transport: serverTransport)
        let initializeResult = try await client.connect(transport: clientTransport)

        #expect(initializeResult.serverInfo.name == UrsusBranding.serverName)
        #expect(initializeResult.serverInfo.title == UrsusBranding.serverTitle)
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
    let writeTransport = MCPToolRecordingWriteTransport()
    let service = BearService(
        configuration: configuration,
        readStore: MCPToolReadStore(note: note),
        writeTransport: writeTransport,
        logger: Logger(label: "UrsusMCPServerCallToolTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(service: service, configuration: configuration).makeServer()
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

        #expect(result.isError != true, "Tool error: \(result.content)")

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

@Test(.timeLimit(.minutes(1)))
func bearApplyTemplateDecodesOperationsAndUsesMutationPresentationDefaults() async throws {
    let note = BearNote(
        ref: NoteRef(identifier: "note-1"),
        revision: NoteRevision(
            version: 3,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_710_000_500)
        ),
        title: "Test Note",
        body: "Body line\n\n#project-x",
        rawText: "# Test Note\n\nBody line\n\n#project-x",
        tags: ["project-x"],
        archived: false,
        trashed: false,
        encrypted: false
    )
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
    let writeTransport = MCPToolRecordingWriteTransport()
    let service = BearService(
        configuration: configuration,
        readStore: MCPToolReadStore(note: note),
        writeTransport: writeTransport,
        logger: Logger(label: "UrsusMCPServerCallToolTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(service: service, configuration: configuration).makeServer()
    let client = Client(name: "BearMCPTestClient", version: "1.0")

    do {
        try await withTemporaryMCPNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
            try await server.start(transport: serverTransport)
            _ = try await client.connect(transport: clientTransport)

            let result = try await client.callTool(
                name: "bear_apply_template",
                arguments: [
                    "operations": .array([
                        .object([
                            "note": .string("Test Note"),
                        ]),
                    ]),
                ]
            )

            #expect(result.isError != true)

            let replaceCall = try #require(await writeTransport.replaceCalls.first)
            #expect(replaceCall.noteID == "note-1")
            #expect(replaceCall.fullText == "# Test Note\n---\n#project-x\n---\nBody line")
            #expect(replaceCall.presentation.openNote == false)
            #expect(replaceCall.presentation.openNoteOverride == nil)
            #expect(replaceCall.presentation.newWindow == false)
            #expect(replaceCall.presentation.newWindowOverride == nil)
        }
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

@Test(.timeLimit(.minutes(1)))
func bearInsertTextDecodesRelativeTargetAndUsesReplaceAllFlow() async throws {
    let note = BearNote(
        ref: NoteRef(identifier: "note-1"),
        revision: NoteRevision(
            version: 3,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_710_000_500)
        ),
        title: "Test Note",
        body: "## Tasks\nLine 1",
        rawText: "# Test Note\n\n## Tasks\nLine 1",
        tags: ["test"],
        archived: false,
        trashed: false,
        encrypted: false
    )
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
    let writeTransport = MCPToolRecordingWriteTransport()
    let service = BearService(
        configuration: configuration,
        readStore: MCPToolReadStore(note: note),
        writeTransport: writeTransport,
        logger: Logger(label: "UrsusMCPServerCallToolTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(service: service, configuration: configuration).makeServer()
    let client = Client(name: "BearMCPTestClient", version: "1.0")

    do {
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)

        let result = try await client.callTool(
            name: "bear_insert_text",
            arguments: [
                "operations": .array([
                    .object([
                        "note": .string("Test Note"),
                        "text": .string("Line 2"),
                        "target": .object([
                            "text": .string("Tasks"),
                            "target_kind": .string("heading"),
                            "placement": .string("after"),
                        ]),
                    ]),
                ]),
            ]
        )

        #expect(result.isError != true)

        let replaceCall = try #require(await writeTransport.replaceCalls.first)
        #expect(replaceCall.noteID == "note-1")
        #expect(replaceCall.fullText == "# Test Note\n\n## Tasks\nLine 2\nLine 1")
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

@Test(.timeLimit(.minutes(1)))
func bearReplaceContentAcceptsSelectedNoteTargetAndResolvesOnce() async throws {
    let note = BearNote(
        ref: NoteRef(identifier: "note-1"),
        revision: NoteRevision(
            version: 3,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_710_000_500)
        ),
        title: "Test Note",
        body: "Body",
        rawText: "# Test Note\n\nBody",
        tags: ["test"],
        archived: false,
        trashed: false,
        encrypted: false
    )
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
    let writeTransport = MCPToolRecordingWriteTransport()
    let service = BearService(
        configuration: configuration,
        tokenStore: InMemoryBearTokenStore(token: "secret-token"),
        readStore: MCPToolReadStore(note: note),
        writeTransport: writeTransport,
        logger: Logger(label: "UrsusMCPServerCallToolTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(
        service: service,
        configuration: configuration,
        selectedNoteTokenConfigured: true
    ).makeServer()
    let client = Client(name: "BearMCPTestClient", version: "1.0")

    do {
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)

        let result = try await client.callTool(
            name: "bear_replace_content",
            arguments: [
                "operations": .array([
                    .object([
                        "selected": .bool(true),
                        "kind": .string("body"),
                        "new_string": .string("Updated"),
                    ]),
                ]),
            ]
        )

        #expect(result.isError != true, "Tool error: \(result.content)")

        let replaceCall = try #require(await writeTransport.replaceCalls.first)
        #expect(replaceCall.noteID == "note-1")
        #expect(await writeTransport.selectedNoteResolutionCount == 1)
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

@Test(.timeLimit(.minutes(1)))
func bearReplaceContentRejectsNoteAndSelectedTogether() async throws {
    let note = BearNote(
        ref: NoteRef(identifier: "note-1"),
        revision: NoteRevision(version: 3, createdAt: Date(), modifiedAt: Date()),
        title: "Test Note",
        body: "Body",
        rawText: "# Test Note\n\nBody",
        tags: ["test"],
        archived: false,
        trashed: false,
        encrypted: false
    )
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
    let writeTransport = MCPToolRecordingWriteTransport()
    let service = BearService(
        configuration: configuration,
        tokenStore: InMemoryBearTokenStore(token: "secret-token"),
        readStore: MCPToolReadStore(note: note),
        writeTransport: writeTransport,
        logger: Logger(label: "UrsusMCPServerCallToolTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(
        service: service,
        configuration: configuration,
        selectedNoteTokenConfigured: true
    ).makeServer()
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
                        "selected": .bool(true),
                        "kind": .string("body"),
                        "new_string": .string("Updated"),
                    ]),
                ]),
            ]
        )

        #expect(result.isError == true)
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

@Test(.timeLimit(.minutes(1)))
func bearListBackupsRejectsMissingNoteTarget() async throws {
    let note = BearNote(
        ref: NoteRef(identifier: "note-1"),
        revision: NoteRevision(version: 3, createdAt: Date(), modifiedAt: Date()),
        title: "Test Note",
        body: "Body",
        rawText: "# Test Note\n\nBody",
        tags: ["test"],
        archived: false,
        trashed: false,
        encrypted: false
    )
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
        tokenStore: InMemoryBearTokenStore(token: "secret-token"),
        readStore: MCPToolReadStore(note: note),
        writeTransport: MCPToolRecordingWriteTransport(),
        backupStore: MCPToolBackupStore(),
        logger: Logger(label: "UrsusMCPServerCallToolTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(service: service, configuration: configuration).makeServer()
    let client = Client(name: "BearMCPTestClient", version: "1.0")

    do {
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)

        let result = try await client.callTool(
            name: "bear_list_backups",
            arguments: [
                "operations": .array([
                    .object([
                        "limit": .int(1),
                    ]),
                ]),
            ]
        )

        #expect(result.isError == true)
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

@Test(.timeLimit(.minutes(1)))
func bearListBackupsForwardsDateFiltersToBackupListingQuery() async throws {
    let note = BearNote(
        ref: NoteRef(identifier: "note-1"),
        revision: NoteRevision(version: 3, createdAt: Date(), modifiedAt: Date()),
        title: "Test Note",
        body: "Body",
        rawText: "# Test Note\n\nBody",
        tags: ["test"],
        archived: false,
        trashed: false,
        encrypted: false
    )
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
    let backupStore = MCPToolBackupStore()
    let service = BearService(
        configuration: configuration,
        tokenStore: InMemoryBearTokenStore(token: "secret-token"),
        readStore: MCPToolReadStore(note: note),
        writeTransport: MCPToolRecordingWriteTransport(),
        backupStore: backupStore,
        logger: Logger(label: "UrsusMCPServerCallToolTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(service: service, configuration: configuration).makeServer()
    let client = Client(name: "BearMCPTestClient", version: "1.0")

    do {
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)

        let result = try await client.callTool(
            name: "bear_list_backups",
            arguments: [
                "operations": .array([
                    .object([
                        "note": .string("Test Note"),
                        "from": .string("2026-03-01"),
                        "to": .string("2026-03-31"),
                    ]),
                ]),
            ]
        )

        #expect(result.isError != true)
        let query = try #require(await backupStore.listQueries.first)
        #expect(query.noteID == "note-1")
        #expect(query.from != nil)
        #expect(query.to != nil)
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

@Test(.timeLimit(.minutes(1)))
func bearCreateBackupsAcceptsSelectedNoteTarget() async throws {
    let note = BearNote(
        ref: NoteRef(identifier: "note-1"),
        revision: NoteRevision(version: 3, createdAt: Date(), modifiedAt: Date()),
        title: "Test Note",
        body: "Body",
        rawText: "# Test Note\n\nBody",
        tags: ["test"],
        archived: false,
        trashed: false,
        encrypted: false
    )
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
    let writeTransport = MCPToolRecordingWriteTransport()
    let backupStore = MCPToolBackupStore()
    let service = BearService(
        configuration: configuration,
        tokenStore: InMemoryBearTokenStore(token: "secret-token"),
        readStore: MCPToolReadStore(note: note),
        writeTransport: writeTransport,
        backupStore: backupStore,
        logger: Logger(label: "UrsusMCPServerCallToolTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(
        service: service,
        configuration: configuration,
        selectedNoteTokenConfigured: true
    ).makeServer()
    let client = Client(name: "BearMCPTestClient", version: "1.0")

    do {
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)

        let result = try await client.callTool(
            name: "bear_create_backups",
            arguments: [
                "operations": .array([
                    .object([
                        "selected": .bool(true),
                    ]),
                ]),
            ]
        )

        #expect(result.isError != true)
        #expect(await writeTransport.selectedNoteResolutionCount == 1)
        #expect(await backupStore.capturedNoteIDs == ["note-1"])
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

@Test(.timeLimit(.minutes(1)))
func bearCompareBackupAcceptsSelectedNoteTarget() async throws {
    let note = BearNote(
        ref: NoteRef(identifier: "note-1"),
        revision: NoteRevision(version: 3, createdAt: Date(), modifiedAt: Date()),
        title: "Test Note",
        body: "Current body",
        rawText: "# Test Note\n\nCurrent body",
        tags: ["test"],
        archived: false,
        trashed: false,
        encrypted: false
    )
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
    let writeTransport = MCPToolRecordingWriteTransport()
    let backupStore = MCPToolBackupStore(
        snapshots: [
            "snapshot-1": BearBackupSnapshot(
                snapshotID: "snapshot-1",
                noteID: "note-1",
                version: 3,
                title: "Test Note",
                rawText: "# Test Note\n\nPrevious body",
                modifiedAt: Date(timeIntervalSince1970: 1_710_000_400),
                capturedAt: Date(timeIntervalSince1970: 1_710_000_450),
                reason: .replaceContent,
                operationGroupID: "op-1"
            ),
        ]
    )
    let service = BearService(
        configuration: configuration,
        tokenStore: InMemoryBearTokenStore(token: "secret-token"),
        readStore: MCPToolReadStore(note: note),
        writeTransport: writeTransport,
        backupStore: backupStore,
        logger: Logger(label: "UrsusMCPServerCallToolTests")
    )

    let (clientToServerRead, clientToServerWrite) = try FileDescriptor.pipe()
    let (serverToClientRead, serverToClientWrite) = try FileDescriptor.pipe()
    let serverTransport = StdioTransport(input: clientToServerRead, output: serverToClientWrite, logger: nil)
    let clientTransport = StdioTransport(input: serverToClientRead, output: clientToServerWrite, logger: nil)

    let server = await UrsusMCPServer(
        service: service,
        configuration: configuration,
        selectedNoteTokenConfigured: true
    ).makeServer()
    let client = Client(name: "BearMCPTestClient", version: "1.0")

    do {
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)

        let result = try await client.callTool(
            name: "bear_compare_backup",
            arguments: [
                "operations": .array([
                    .object([
                        "selected": .bool(true),
                        "snapshot_id": .string("snapshot-1"),
                        "detail": .string("full"),
                    ]),
                ]),
            ]
        )

        #expect(result.isError != true)
        #expect(await writeTransport.selectedNoteResolutionCount == 1)
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
        let presentation: BearPresentationOptions
    }

    private(set) var replaceCalls: [ReplaceCall] = []
    private(set) var selectedNoteResolutionCount = 0

    func resolveSelectedNoteID(token _: String) async throws -> String {
        selectedNoteResolutionCount += 1
        return "note-1"
    }

    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: "created", title: request.title, status: "created", modifiedAt: nil)
    }

    func insertText(_ request: InsertTextRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
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

private actor MCPToolBackupStore: BearBackupStore {
    private let snapshots: [String: BearBackupSnapshot]
    private(set) var capturedNoteIDs: [String] = []
    private(set) var listQueries: [BackupListQuery] = []

    init(snapshots: [String: BearBackupSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    func capture(note: BearNote, reason: BackupReason, operationGroupID: String?) async throws -> BearBackupSummary? {
        capturedNoteIDs.append(note.ref.identifier)
        return BearBackupSummary(
            snapshotID: "snapshot-\(capturedNoteIDs.count)",
            noteID: note.ref.identifier,
            modifiedAt: note.revision.modifiedAt,
            capturedAt: Date(timeIntervalSince1970: 1_710_000_600),
            reason: reason
        )
    }

    func list(_ query: BackupListQuery) async throws -> BackupSummaryPage {
        listQueries.append(query)
        return BackupSummaryPage(
            items: [],
            page: DiscoveryPageInfo(limit: query.limit, returned: 0, hasMore: false, nextCursor: nil)
        )
    }

    func snapshot(noteID: String, snapshotID: String?) async throws -> BearBackupSnapshot? {
        guard let snapshotID else {
            return snapshots.values.first(where: { $0.noteID == noteID })
        }
        let snapshot = snapshots[snapshotID]
        return snapshot?.noteID == noteID ? snapshot : nil
    }

    func delete(snapshotID: String, noteID: String?) async throws -> Int { 0 }
    func deleteAll(noteID: String) async throws -> Int { 0 }
}

private func withTemporaryMCPNoteTemplate<T: Sendable>(_ template: String?, operation: @Sendable () async throws -> T) async throws -> T {
    try await withSharedMCPTemplateFileLock {
        let templateURL = BearPaths.noteTemplateURL
        let fileManager = FileManager.default
        let originalTemplate = fileManager.fileExists(atPath: templateURL.path) ? try String(contentsOf: templateURL) : nil

        try fileManager.createDirectory(at: BearPaths.configDirectoryURL, withIntermediateDirectories: true)
        if let template {
            try template.write(to: templateURL, atomically: true, encoding: .utf8)
        } else if fileManager.fileExists(atPath: templateURL.path) {
            try fileManager.removeItem(at: templateURL)
        }
        defer {
            if let originalTemplate {
                try? originalTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
            } else {
                try? fileManager.removeItem(at: templateURL)
            }
        }

        return try await operation()
    }
}

private func withSharedMCPTemplateFileLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    let fileManager = FileManager.default
    let lockURL = fileManager.temporaryDirectory.appendingPathComponent("ursus-tests-template.lock", isDirectory: true)

    while true {
        do {
            try fileManager.createDirectory(at: lockURL, withIntermediateDirectories: false)
            break
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    defer { try? fileManager.removeItem(at: lockURL) }
    return try await operation()
}
