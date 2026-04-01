import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func addFilesUseTemplateAwareAnchorFlowWhenNoteMatchesCurrentTemplate() async throws {
    let note = makeAddFileSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nLine 1",
        tags: ["0-inbox"]
    )
    let readStore = MutableAddFileReadStore(note: note)
    let transport = AddFileRecordingWriteTransport(readStore: readStore)
    let service = BearService(
        configuration: makeAddFileConfiguration(templateManagementEnabled: true),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceAddFileTests")
    )

    let fileURL = try temporaryAddFileURL(named: "example.txt", contents: "payload")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        _ = try await service.addFiles([
            AddFileRequest(
                noteID: "note-1",
                filePath: fileURL.path,
                position: .bottom,
                presentation: BearPresentationOptions(openNote: true, newWindow: true, showWindow: true, edit: true),
                expectedVersion: 3
            ),
        ])
    }

    let addFileRequest = try #require(await transport.addFileRequests.first)
    #expect(addFileRequest.header?.hasPrefix("BEAR_MCP_ATTACHMENT_") == true)
    #expect(addFileRequest.position == .top)
    #expect(addFileRequest.presentation.openNote == false)
    #expect(addFileRequest.presentation.showWindow == false)

    let replaceCalls = await transport.replaceCalls
    #expect(replaceCalls.count == 2)
    #expect(replaceCalls[0].fullText.contains("## BEAR_MCP_ATTACHMENT_"))
    #expect(replaceCalls[0].presentation.showWindow == false)
    #expect(replaceCalls[1].fullText == "# Inbox\n\n---\n#0-inbox\n---\nLine 1\n[file:example.txt]")
    #expect(replaceCalls[1].presentation.openNote == true)
    #expect(replaceCalls[1].presentation.newWindow == true)
    #expect(replaceCalls[1].presentation.edit == true)
}

@Test
func addFilesRespectTopPlacementInsideTemplateContent() async throws {
    let note = makeAddFileSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nLine 1",
        tags: ["0-inbox"]
    )
    let readStore = MutableAddFileReadStore(note: note)
    let transport = AddFileRecordingWriteTransport(readStore: readStore)
    let service = BearService(
        configuration: makeAddFileConfiguration(templateManagementEnabled: true),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceAddFileTests")
    )

    let fileURL = try temporaryAddFileURL(named: "example.txt", contents: "payload")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        _ = try await service.addFiles([
            AddFileRequest(
                noteID: "note-1",
                filePath: fileURL.path,
                position: .top,
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let addFileRequest = try #require(await transport.addFileRequests.first)
    #expect(addFileRequest.position == .top)
    let replaceCalls = await transport.replaceCalls
    #expect(replaceCalls[1].fullText == "# Inbox\n\n---\n#0-inbox\n---\n[file:example.txt]\n\nLine 1")
}

@Test
func addFilesCleanupRemovesAnchorWhenBearAppendsAttachmentInline() async throws {
    let note = makeAddFileSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox\n---\nLine 1",
        tags: ["0-inbox"]
    )
    let readStore = MutableAddFileReadStore(note: note, headerAttachmentLayout: .sameLine)
    let transport = AddFileRecordingWriteTransport(readStore: readStore)
    let service = BearService(
        configuration: makeAddFileConfiguration(templateManagementEnabled: true),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceAddFileTests")
    )

    let fileURL = try temporaryAddFileURL(named: "example.txt", contents: "payload")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        _ = try await service.addFiles([
            AddFileRequest(
                noteID: "note-1",
                filePath: fileURL.path,
                position: .bottom,
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCalls = await transport.replaceCalls
    #expect(replaceCalls.count == 2)
    #expect(replaceCalls[1].fullText == "# Inbox\n\n---\n#0-inbox\n---\nLine 1\n[file:example.txt]")
}

@Test
func addFilesFallBackToDirectAddFileWhenNoteDoesNotMatchCurrentTemplate() async throws {
    let note = makeAddFileSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Custom header\n\nLine 1",
        tags: ["0-inbox"]
    )
    let readStore = MutableAddFileReadStore(note: note)
    let transport = AddFileRecordingWriteTransport(readStore: readStore)
    let service = BearService(
        configuration: makeAddFileConfiguration(templateManagementEnabled: true),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceAddFileTests")
    )

    let fileURL = try temporaryAddFileURL(named: "example.txt", contents: "payload")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        _ = try await service.addFiles([
            AddFileRequest(
                noteID: "note-1",
                filePath: fileURL.path,
                position: .top,
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let addFileRequest = try #require(await transport.addFileRequests.first)
    #expect(addFileRequest.header == nil)
    #expect(addFileRequest.position == .top)
    #expect(await transport.replaceCalls.isEmpty)
}

@Test
func addFilesUseAnchorFlowForRelativeHeadingTargetOnPlainNote() async throws {
    let note = makeAddFileSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "## Tasks\nLine 1",
        tags: ["0-inbox"]
    )
    let readStore = MutableAddFileReadStore(note: note)
    let transport = AddFileRecordingWriteTransport(readStore: readStore)
    let service = BearService(
        configuration: makeAddFileConfiguration(templateManagementEnabled: false),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceAddFileTests")
    )

    let fileURL = try temporaryAddFileURL(named: "example.txt", contents: "payload")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    _ = try await service.addFiles([
        AddFileRequest(
            noteID: "note-1",
            filePath: fileURL.path,
            target: RelativeTextTarget(text: "Tasks", targetKind: .heading, placement: .after),
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let addFileRequest = try #require(await transport.addFileRequests.first)
    #expect(addFileRequest.header?.hasPrefix("BEAR_MCP_ATTACHMENT_") == true)
    #expect(addFileRequest.position == .top)
    let replaceCalls = await transport.replaceCalls
    #expect(replaceCalls.count == 2)
    #expect(replaceCalls[1].fullText == "# Inbox\n\n## Tasks\n[file:example.txt]\n\nLine 1")
}

@Test
func addFilesRejectAmbiguousRelativeStringTargetBeforeWriting() async throws {
    let note = makeAddFileSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1\n\nLine 1",
        tags: ["0-inbox"]
    )
    let readStore = MutableAddFileReadStore(note: note)
    let transport = AddFileRecordingWriteTransport(readStore: readStore)
    let service = BearService(
        configuration: makeAddFileConfiguration(templateManagementEnabled: false),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceAddFileTests")
    )

    let fileURL = try temporaryAddFileURL(named: "example.txt", contents: "payload")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    await #expect(throws: BearError.self) {
        _ = try await service.addFiles([
            AddFileRequest(
                noteID: "note-1",
                filePath: fileURL.path,
                target: RelativeTextTarget(text: "Line 1", placement: .after),
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    #expect(await transport.addFileRequests.isEmpty)
    #expect(await transport.replaceCalls.isEmpty)
}

private func makeAddFileConfiguration(templateManagementEnabled: Bool) -> BearConfiguration {
    BearConfiguration(
        databasePath: "/tmp/database.sqlite",
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

private func makeAddFileSourceNote(
    id: String,
    title: String,
    body: String,
    tags: [String]
) -> BearNote {
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
    let modifiedAt = Date(timeIntervalSince1970: 1_710_000_500)

    return BearNote(
        ref: NoteRef(identifier: id),
        revision: NoteRevision(version: 3, createdAt: createdAt, modifiedAt: modifiedAt),
        title: title,
        body: body,
        rawText: BearText.composeRawText(title: title, body: body),
        tags: tags,
        archived: false,
        trashed: false,
        encrypted: false
    )
}

private func temporaryAddFileURL(named filename: String, contents: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let fileURL = directoryURL.appendingPathComponent(filename)
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
}

private final class MutableAddFileReadStore: @unchecked Sendable, BearReadStore {
    private let lock = NSLock()
    private var note: BearNote
    private let headerAttachmentLayout: HeaderAttachmentLayout

    init(note: BearNote, headerAttachmentLayout: HeaderAttachmentLayout = .nextLine) {
        self.note = note
        self.headerAttachmentLayout = headerAttachmentLayout
    }

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }

    func note(id: String) throws -> BearNote? {
        lock.lock()
        defer { lock.unlock() }
        return note.ref.identifier == id ? note : nil
    }

    func replaceRawText(noteID: String, rawText: String) {
        lock.lock()
        defer { lock.unlock() }
        guard note.ref.identifier == noteID else {
            return
        }

        let parsed = parseRawText(rawText, fallbackTitle: note.title)
        note = BearNote(
            ref: note.ref,
            revision: NoteRevision(
                version: note.revision.version + 1,
                createdAt: note.revision.createdAt,
                modifiedAt: note.revision.modifiedAt.addingTimeInterval(1)
            ),
            title: parsed.title,
            body: parsed.body,
            rawText: rawText,
            tags: note.tags,
            archived: note.archived,
            trashed: note.trashed,
            encrypted: note.encrypted
        )
    }

    func addFile(noteID: String, filename: String, header: String?, position: InsertPosition) {
        lock.lock()
        defer { lock.unlock() }
        guard note.ref.identifier == noteID else {
            return
        }

        let attachmentLine = "[file:\(filename)]"
        let parsed = parseRawText(note.rawText, fallbackTitle: note.title)
        let updatedBody: String

        if let header {
            let headerLine = "## \(header)"
            switch position {
            case .top:
                let replacement = switch headerAttachmentLayout {
                case .nextLine:
                    "\(headerLine)\n\(attachmentLine)\n"
                case .sameLine:
                    "\(headerLine)\(attachmentLine)"
                }
                updatedBody = parsed.body.replacingOccurrences(
                    of: headerLine,
                    with: replacement,
                    options: [],
                    range: parsed.body.range(of: headerLine)
                )
            case .bottom:
                updatedBody = parsed.body + "\n" + attachmentLine
            }
        } else {
            updatedBody = position == .top
                ? attachmentLine + "\n" + parsed.body
                : parsed.body + "\n" + attachmentLine
        }

        note = BearNote(
            ref: note.ref,
            revision: NoteRevision(
                version: note.revision.version + 1,
                createdAt: note.revision.createdAt,
                modifiedAt: note.revision.modifiedAt.addingTimeInterval(1)
            ),
            title: parsed.title,
            body: updatedBody,
            rawText: BearText.composeRawText(title: parsed.title, body: updatedBody),
            tags: note.tags,
            archived: note.archived,
            trashed: note.trashed,
            encrypted: note.encrypted
        )
    }

    private func parseRawText(_ rawText: String, fallbackTitle: String) -> (title: String, body: String) {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard normalized.hasPrefix("# ") else {
            return (fallbackTitle, normalized)
        }

        let remainder = String(normalized.dropFirst(2))
        if let newlineIndex = remainder.firstIndex(of: "\n") {
            let title = String(remainder[..<newlineIndex])
            let body = String(remainder[remainder.index(after: newlineIndex)...]).trimmingCharacters(in: .newlines)
            return (title, body)
        }

        return (remainder, "")
    }
}

private enum HeaderAttachmentLayout {
    case nextLine
    case sameLine
}

private actor AddFileRecordingWriteTransport: BearWriteTransport {
    struct ReplaceCall: Sendable {
        let noteID: String
        let fullText: String
        let presentation: BearPresentationOptions
    }

    private let readStore: MutableAddFileReadStore
    private(set) var replaceCalls: [ReplaceCall] = []
    private(set) var addFileRequests: [AddFileRequest] = []

    func resolveSelectedNoteID(token _: String) async throws -> String {
        "selected-note"
    }

    init(readStore: MutableAddFileReadStore) {
        self.readStore = readStore
    }

    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: "created", title: request.title, status: "created", modifiedAt: nil)
    }

    func insertText(_ request: InsertTextRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func replaceAll(noteID: String, fullText: String, presentation: BearPresentationOptions) async throws -> MutationReceipt {
        replaceCalls.append(ReplaceCall(noteID: noteID, fullText: fullText, presentation: presentation))
        readStore.replaceRawText(noteID: noteID, rawText: fullText)
        return MutationReceipt(noteID: noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func addFile(_ request: AddFileRequest) async throws -> MutationReceipt {
        addFileRequests.append(request)
        readStore.addFile(
            noteID: request.noteID,
            filename: URL(fileURLWithPath: request.filePath).lastPathComponent,
            header: request.header,
            position: request.position ?? .bottom
        )
        return MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
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
