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
        activeTags: ["0-inbox", "#Daily"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        openNoteInEditModeByDefault: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsActiveTagsByDefault: true,
        createRequestTagsMode: .append
    )
    let service = BearService(
        configuration: configuration,
        readStore: EmptyReadStore(),
        writeTransport: transport,
        logger: Logger(label: "BearServiceCreateTests")
    )

    let templateURL = BearPaths.noteTemplateURL
    let fileManager = FileManager.default
    let originalTemplate = fileManager.fileExists(atPath: templateURL.path) ? try String(contentsOf: templateURL) : nil
    try fileManager.createDirectory(at: BearPaths.configDirectoryURL, withIntermediateDirectories: true)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        if let originalTemplate {
            try? originalTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
        } else {
            try? fileManager.removeItem(at: templateURL)
        }
    }

    _ = try await service.createNotes([
        CreateNoteRequest(
            title: "Sample Note",
            content: "# Sample Note\n\nBody line",
            tags: ["project-x", "#daily"],
            presentation: BearPresentationOptions(openNote: true, newWindow: true, showWindow: true, edit: true)
        ),
    ])

    let captured = try #require(await transport.createdRequests.first)
    #expect(captured.title == "Sample Note")
    #expect(captured.content == "Body line\n\n#0-inbox #Daily #project-x")
    #expect(captured.tags == ["0-inbox", "#Daily", "project-x"])
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
        createRequestTagsMode: .replace
    )
    let service = BearService(
        configuration: configuration,
        readStore: EmptyReadStore(),
        writeTransport: transport,
        logger: Logger(label: "BearServiceCreateTests")
    )

    let templateURL = BearPaths.noteTemplateURL
    let fileManager = FileManager.default
    let originalTemplate = fileManager.fileExists(atPath: templateURL.path) ? try String(contentsOf: templateURL) : nil
    try fileManager.createDirectory(at: BearPaths.configDirectoryURL, withIntermediateDirectories: true)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        if let originalTemplate {
            try? originalTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
        } else {
            try? fileManager.removeItem(at: templateURL)
        }
    }

    _ = try await service.createNotes([
        CreateNoteRequest(
            title: "Sample Note",
            content: "Body line",
            tags: ["project-x"],
            presentation: BearPresentationOptions(openNote: true, newWindow: true, showWindow: true, edit: true)
        ),
    ])

    let captured = try #require(await transport.createdRequests.first)
    #expect(captured.content == "Body line\n\n#project-x")
    #expect(captured.tags == ["project-x"])
}

private struct EmptyReadStore: BearReadStore {
    func searchNotes(_ query: NoteSearchQuery) throws -> [NoteSearchHit] { [] }
    func note(id: String) throws -> BearNote? { nil }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func notes(matchingTag tag: String) throws -> [BearNote] { [] }
    func notes(inScope scope: BearScope, activeTags: [String]) throws -> [BearNote] { [] }
    func listTags() throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private actor RecordingWriteTransport: BearWriteTransport {
    private(set) var createdRequests: [CreateNoteRequest] = []

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

    func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        MutationReceipt(noteID: noteID, title: nil, status: "archived", modifiedAt: nil)
    }
}
