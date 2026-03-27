import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func insertTextCapturesBackupBeforeDirectInsert() async throws {
    let note = makeBackupServiceNote(id: "note-1", title: "Inbox", body: "Line 1")
    let readStore = BackupServiceReadStore(noteByID: ["note-1": note])
    let writeTransport = BackupServiceWriteTransport()
    let backupStore = RecordingBackupStore()
    let service = BearService(
        configuration: makeBackupServiceConfiguration(templateManagementEnabled: false),
        readStore: readStore,
        writeTransport: writeTransport,
        backupStore: backupStore,
        logger: Logger(label: "BearServiceBackupTests")
    )

    _ = try await service.insertText([
        InsertTextRequest(
            noteID: "note-1",
            text: "Line 2",
            position: .bottom,
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let captured = try #require(await backupStore.captures.first)
    let inserted = try #require(await writeTransport.insertCalls.first)
    #expect(captured.noteID == "note-1")
    #expect(captured.reason == .insertText)
    #expect(captured.rawText == note.rawText)
    #expect(inserted.noteID == "note-1")
}

@Test
func addFilesCapturesBackupBeforeDirectAddFile() async throws {
    let note = makeBackupServiceNote(id: "note-1", title: "Inbox", body: "Line 1")
    let readStore = BackupServiceReadStore(noteByID: ["note-1": note])
    let writeTransport = BackupServiceWriteTransport()
    let backupStore = RecordingBackupStore()
    let service = BearService(
        configuration: makeBackupServiceConfiguration(templateManagementEnabled: false),
        readStore: readStore,
        writeTransport: writeTransport,
        backupStore: backupStore,
        logger: Logger(label: "BearServiceBackupTests")
    )

    _ = try await service.addFiles([
        AddFileRequest(
            noteID: "note-1",
            filePath: "/tmp/example.txt",
            position: .bottom,
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let captured = try #require(await backupStore.captures.first)
    let added = try #require(await writeTransport.addFileCalls.first)
    #expect(captured.reason == .addFile)
    #expect(captured.rawText == note.rawText)
    #expect(added.noteID == "note-1")
}

@Test
func restoreBackupsUsesRequestedSnapshotAndCapturesCurrentState() async throws {
    let note = makeBackupServiceNote(id: "note-1", title: "Inbox", body: "Current")
    let readStore = BackupServiceReadStore(noteByID: ["note-1": note])
    let writeTransport = BackupServiceWriteTransport()
    let backupStore = RecordingBackupStore(
        snapshots: [
            "snapshot-1": BearBackupSnapshot(
                snapshotID: "snapshot-1",
                noteID: "note-1",
                title: "Inbox",
                rawText: "# Inbox\n\nPrevious",
                version: 2,
                modifiedAt: Date(timeIntervalSince1970: 1_710_000_400),
                capturedAt: Date(timeIntervalSince1970: 1_710_000_450),
                reason: .replaceContent,
                operationGroupID: "op-1"
            ),
        ]
    )
    let service = BearService(
        configuration: makeBackupServiceConfiguration(templateManagementEnabled: false),
        readStore: readStore,
        writeTransport: writeTransport,
        backupStore: backupStore,
        logger: Logger(label: "BearServiceBackupTests")
    )

    let receipts = try await service.restoreBackups([
        RestoreBackupRequest(
            noteID: "note-1",
            snapshotID: "snapshot-1",
            presentation: BearPresentationOptions()
        ),
    ])

    let captured = try #require(await backupStore.captures.first)
    let replace = try #require(await writeTransport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(captured.reason == .restore)
    #expect(captured.rawText == note.rawText)
    #expect(replace.noteID == "note-1")
    #expect(replace.fullText == "# Inbox\n\nPrevious")
    #expect(receipt.snapshotID == "snapshot-1")
}

@Test
func listBackupsResolvesSelectorsAndReturnsPerOperationErrors() async throws {
    let note = makeBackupServiceNote(id: "note-1", title: "Inbox", body: "Current")
    let readStore = BackupServiceReadStore(noteByID: ["note-1": note], notesByTitle: ["inbox": [note]])
    let writeTransport = BackupServiceWriteTransport()
    let backupStore = RecordingBackupStore(
        listedSummariesByNoteID: [
            "note-1": [
                BearBackupSummary(
                    snapshotID: "snapshot-1",
                    noteID: "note-1",
                    title: "Inbox",
                    version: 3,
                    modifiedAt: Date(timeIntervalSince1970: 1_710_000_500),
                    capturedAt: Date(timeIntervalSince1970: 1_710_000_550),
                    reason: .insertText,
                    snippet: "Current"
                ),
            ],
        ]
    )
    let service = BearService(
        configuration: makeBackupServiceConfiguration(templateManagementEnabled: false),
        readStore: readStore,
        writeTransport: writeTransport,
        backupStore: backupStore,
        logger: Logger(label: "BearServiceBackupTests")
    )

    let result = try await service.listBackups([
        ListBackupsOperation(id: "ok", noteID: "Inbox", limit: 10),
        ListBackupsOperation(id: "missing", noteID: "Unknown", limit: 10),
    ])

    let first = try #require(result.results.first)
    let second = try #require(result.results.last)
    #expect(first.id == "ok")
    #expect(first.items.first?.snapshotID == "snapshot-1")
    #expect(second.id == "missing")
    #expect(second.error?.contains("not found") == true)
}

@Test
func deleteBackupsDeletesExactSnapshotAndNoteScopedHistory() async throws {
    let note = makeBackupServiceNote(id: "note-1", title: "Inbox", body: "Current")
    let readStore = BackupServiceReadStore(noteByID: ["note-1": note], notesByTitle: ["inbox": [note]])
    let writeTransport = BackupServiceWriteTransport()
    let backupStore = RecordingBackupStore(
        listedSummariesByNoteID: [
            "note-1": [
                BearBackupSummary(
                    snapshotID: "snapshot-1",
                    noteID: "note-1",
                    title: "Inbox",
                    version: 3,
                    modifiedAt: Date(timeIntervalSince1970: 1_710_000_500),
                    capturedAt: Date(timeIntervalSince1970: 1_710_000_550),
                    reason: .insertText,
                    snippet: "Current"
                ),
            ],
        ]
    )
    let service = BearService(
        configuration: makeBackupServiceConfiguration(templateManagementEnabled: false),
        readStore: readStore,
        writeTransport: writeTransport,
        backupStore: backupStore,
        logger: Logger(label: "BearServiceBackupTests")
    )

    let receipts = try await service.deleteBackups([
        DeleteBackupRequest(snapshotID: "snapshot-1"),
        DeleteBackupRequest(noteID: "Inbox", deleteAll: true),
    ])

    let first = try #require(receipts.first)
    let second = try #require(receipts.last)
    #expect(first.snapshotID == "snapshot-1")
    #expect(first.deletedCount == 1)
    #expect(first.status == "deleted")
    #expect(second.noteID == "note-1")
    #expect(second.deletedCount == 1)
    #expect(second.status == "deleted")
    #expect(await backupStore.deletedSnapshotIDs == ["snapshot-1"])
    #expect(await backupStore.deletedAllNoteIDs == ["note-1"])
}

@Test
func deleteBackupsRejectsBlindBulkDelete() async throws {
    let note = makeBackupServiceNote(id: "note-1", title: "Inbox", body: "Current")
    let service = BearService(
        configuration: makeBackupServiceConfiguration(templateManagementEnabled: false),
        readStore: BackupServiceReadStore(noteByID: ["note-1": note]),
        writeTransport: BackupServiceWriteTransport(),
        backupStore: RecordingBackupStore(),
        logger: Logger(label: "BearServiceBackupTests")
    )

    await #expect(throws: BearError.self) {
        _ = try await service.deleteBackups([
            DeleteBackupRequest(deleteAll: true),
        ])
    }
}

private func makeBackupServiceConfiguration(templateManagementEnabled: Bool) -> BearConfiguration {
    BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        activeTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: templateManagementEnabled,
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
}

private func makeBackupServiceNote(id: String, title: String, body: String) -> BearNote {
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
    let modifiedAt = Date(timeIntervalSince1970: 1_710_000_500)

    return BearNote(
        ref: NoteRef(identifier: id),
        revision: NoteRevision(version: 3, createdAt: createdAt, modifiedAt: modifiedAt),
        title: title,
        body: body,
        rawText: BearText.composeRawText(title: title, body: body),
        tags: ["0-inbox"],
        archived: false,
        trashed: false,
        encrypted: false
    )
}

private final class BackupServiceReadStore: @unchecked Sendable, BearReadStore {
    private let noteByID: [String: BearNote]
    private let notesByTitle: [String: [BearNote]]

    init(noteByID: [String: BearNote], notesByTitle: [String: [BearNote]] = [:]) {
        self.noteByID = noteByID
        self.notesByTitle = notesByTitle
    }

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func note(id: String) throws -> BearNote? { noteByID[id] }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func notes(titled title: String, location: BearNoteLocation) throws -> [BearNote] { notesByTitle[title.lowercased()] ?? [] }
    func attachments(noteID: String) throws -> [NoteAttachment] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private actor BackupServiceWriteTransport: BearWriteTransport {
    struct ReplaceCall: Sendable {
        let noteID: String
        let fullText: String
    }

    private(set) var insertCalls: [InsertTextRequest] = []
    private(set) var addFileCalls: [AddFileRequest] = []
    private(set) var replaceCalls: [ReplaceCall] = []

    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: "created", title: request.title, status: "created", modifiedAt: nil)
    }

    func insertText(_ request: InsertTextRequest) async throws -> MutationReceipt {
        insertCalls.append(request)
        return MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func replaceAll(noteID: String, fullText: String, presentation: BearPresentationOptions) async throws -> MutationReceipt {
        replaceCalls.append(ReplaceCall(noteID: noteID, fullText: fullText))
        return MutationReceipt(noteID: noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func addFile(_ request: AddFileRequest) async throws -> MutationReceipt {
        addFileCalls.append(request)
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

private actor RecordingBackupStore: BearBackupStore {
    struct Capture: Sendable {
        let noteID: String
        let rawText: String
        let reason: BackupReason
    }

    private(set) var captures: [Capture] = []
    private let snapshots: [String: BearBackupSnapshot]
    private let listedSummariesByNoteID: [String: [BearBackupSummary]]
    private(set) var deletedSnapshotIDs: [String] = []
    private(set) var deletedAllNoteIDs: [String] = []

    init(
        snapshots: [String: BearBackupSnapshot] = [:],
        listedSummariesByNoteID: [String: [BearBackupSummary]] = [:]
    ) {
        self.snapshots = snapshots
        self.listedSummariesByNoteID = listedSummariesByNoteID
    }

    func capture(note: BearNote, reason: BackupReason, operationGroupID: String?) async throws -> BearBackupSummary? {
        captures.append(Capture(noteID: note.ref.identifier, rawText: note.rawText, reason: reason))
        return nil
    }

    func list(noteID: String?, limit: Int?) async throws -> [BearBackupSummary] {
        let items = noteID.flatMap { listedSummariesByNoteID[$0] } ?? listedSummariesByNoteID.values.flatMap { $0 }
        guard let limit else {
            return items
        }
        return Array(items.prefix(limit))
    }

    func snapshot(noteID: String, snapshotID: String?) async throws -> BearBackupSnapshot? {
        if let snapshotID {
            let snapshot = snapshots[snapshotID]
            return snapshot?.noteID == noteID ? snapshot : nil
        }

        return snapshots.values.first(where: { $0.noteID == noteID })
    }

    func delete(snapshotID: String, noteID: String?) async throws -> Int {
        deletedSnapshotIDs.append(snapshotID)
        return 1
    }

    func deleteAll(noteID: String) async throws -> Int {
        deletedAllNoteIDs.append(noteID)
        return 1
    }
}
