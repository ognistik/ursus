import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func openTagNormalizesWrappedTagBeforeSendingItToTransport() async throws {
    let transport = TagRecordingWriteTransport()
    let service = BearService(
        configuration: makeTagMutationConfiguration(),
        readStore: TagMutationReadStore(),
        writeTransport: transport,
        logger: Logger(label: "BearServiceTagMutationTests")
    )

    let receipt = try await service.openTag(" #deep work# ")

    let request = try #require(await transport.openedTags.first)
    #expect(request.tag == "deep work")
    #expect(receipt.tag == "deep work")
    #expect(receipt.status == "opened")
}

@Test
func renameTagsNormalizesNamesAndPreservesOmittedShowWindow() async throws {
    let transport = TagRecordingWriteTransport()
    let service = BearService(
        configuration: makeTagMutationConfiguration(),
        readStore: TagMutationReadStore(),
        writeTransport: transport,
        logger: Logger(label: "BearServiceTagMutationTests")
    )

    let receipts = try await service.renameTags([
        RenameTagRequest(name: " #todo# ", newName: " #done# ", showWindow: nil),
    ])

    let request = try #require(await transport.renamedTags.first)
    let receipt = try #require(receipts.first)
    #expect(request.name == "todo")
    #expect(request.newName == "done")
    #expect(request.showWindow == nil)
    #expect(receipt.tag == "todo")
    #expect(receipt.newTag == "done")
}

@Test
func deleteTagsNormalizesNamesAndPreservesOmittedShowWindow() async throws {
    let transport = TagRecordingWriteTransport()
    let service = BearService(
        configuration: makeTagMutationConfiguration(),
        readStore: TagMutationReadStore(notesTags: [
            TagSummary(name: "obsolete project", identifier: "tag-1", noteCount: 1),
        ]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceTagMutationTests")
    )

    let receipts = try await service.deleteTags([
        DeleteTagRequest(name: " #obsolete project# ", showWindow: nil),
    ])

    let request = try #require(await transport.deletedTags.first)
    let receipt = try #require(receipts.first)
    #expect(request.name == "obsolete project")
    #expect(request.showWindow == nil)
    #expect(receipt.tag == "obsolete project")
    #expect(receipt.status == "deleted")
}

@Test
func deleteTagsReturnsNotFoundWithoutCallingTransportWhenTagDoesNotExist() async throws {
    let transport = TagRecordingWriteTransport()
    let service = BearService(
        configuration: makeTagMutationConfiguration(),
        readStore: TagMutationReadStore(),
        writeTransport: transport,
        logger: Logger(label: "BearServiceTagMutationTests")
    )

    let receipts = try await service.deleteTags([
        DeleteTagRequest(name: " #missing tag# ", showWindow: nil),
    ])

    let receipt = try #require(receipts.first)
    let deletedTags = await transport.deletedTags
    #expect(deletedTags.isEmpty)
    #expect(receipt.tag == "missing tag")
    #expect(receipt.status == "not_found")
}

@Test
func deleteTagsStillDeletesTagThatExistsOnlyInArchive() async throws {
    let transport = TagRecordingWriteTransport()
    let service = BearService(
        configuration: makeTagMutationConfiguration(),
        readStore: TagMutationReadStore(
            archiveTags: [TagSummary(name: "archived-only", identifier: "tag-2", noteCount: 1)]
        ),
        writeTransport: transport,
        logger: Logger(label: "BearServiceTagMutationTests")
    )

    let receipts = try await service.deleteTags([
        DeleteTagRequest(name: " archived-only ", showWindow: false),
    ])

    let request = try #require(await transport.deletedTags.first)
    let receipt = try #require(receipts.first)
    #expect(request.name == "archived-only")
    #expect(request.showWindow == false)
    #expect(receipt.tag == "archived-only")
    #expect(receipt.status == "deleted")
}

private func makeTagMutationConfiguration() -> BearConfiguration {
    BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
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

private struct TagMutationReadStore: BearReadStore {
    let notesTags: [TagSummary]
    let archiveTags: [TagSummary]

    init(
        notesTags: [TagSummary] = [],
        archiveTags: [TagSummary] = []
    ) {
        self.notesTags = notesTags
        self.archiveTags = archiveTags
    }

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }

    func note(id: String) throws -> BearNote? { nil }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }

    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] {
        let source = query.location == .archive ? archiveTags : notesTags
        guard let query = query.query?.lowercased(), !query.isEmpty else {
            return source
        }
        return source.filter { $0.name.lowercased().contains(query) }
    }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private actor TagRecordingWriteTransport: BearWriteTransport {
    private(set) var openedTags: [OpenTagRequest] = []
    private(set) var renamedTags: [RenameTagRequest] = []
    private(set) var deletedTags: [DeleteTagRequest] = []

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
        deletedTags.append(request)
        return TagMutationReceipt(tag: request.name, newTag: nil, status: "deleted")
    }

    func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        MutationReceipt(noteID: noteID, title: nil, status: "archived", modifiedAt: nil)
    }
}
