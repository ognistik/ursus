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

private func makeTagMutationConfiguration() -> BearConfiguration {
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
        maxSnippetLength: 1_000
    )
}

private struct TagMutationReadStore: BearReadStore {
    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }

    func note(id: String) throws -> BearNote? { nil }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }

    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private actor TagRecordingWriteTransport: BearWriteTransport {
    private(set) var openedTags: [OpenTagRequest] = []
    private(set) var renamedTags: [RenameTagRequest] = []

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

    func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        MutationReceipt(noteID: noteID, title: nil, status: "archived", modifiedAt: nil)
    }
}
