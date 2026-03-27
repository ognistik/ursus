import Foundation

public protocol BearReadStore: Sendable {
    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch
    func note(id: String) throws -> BearNote?
    func notes(withIDs ids: [String]) throws -> [BearNote]
    func notes(titled title: String, location: BearNoteLocation) throws -> [BearNote]
    func attachments(noteID: String) throws -> [NoteAttachment]
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary]
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote]
}

public extension BearReadStore {
    func notes(titled title: String, location: BearNoteLocation) throws -> [BearNote] { [] }
    func attachments(noteID: String) throws -> [NoteAttachment] { [] }
}

public protocol BearWriteTransport: Sendable {
    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt
    func insertText(_ request: InsertTextRequest) async throws -> MutationReceipt
    func replaceAll(noteID: String, fullText: String, presentation: BearPresentationOptions) async throws -> MutationReceipt
    func addFile(_ request: AddFileRequest) async throws -> MutationReceipt
    func open(_ request: OpenNoteRequest) async throws -> MutationReceipt
    func openTag(_ request: OpenTagRequest) async throws -> TagMutationReceipt
    func renameTag(_ request: RenameTagRequest) async throws -> TagMutationReceipt
    func deleteTag(_ request: DeleteTagRequest) async throws -> TagMutationReceipt
    func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt
}

public protocol BearBackupStore: Sendable {
    func capture(note: BearNote, reason: BackupReason, operationGroupID: String?) async throws -> BearBackupSummary?
    func list(noteID: String?, limit: Int?) async throws -> [BearBackupSummary]
    func snapshot(noteID: String, snapshotID: String?) async throws -> BearBackupSnapshot?
    func delete(snapshotID: String, noteID: String?) async throws -> Int
    func deleteAll(noteID: String) async throws -> Int
}
