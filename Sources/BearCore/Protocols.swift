import Foundation

public protocol BearReadStore: Sendable {
    func searchNotes(_ query: NoteSearchQuery) throws -> [NoteSearchHit]
    func note(id: String) throws -> BearNote?
    func notes(withIDs ids: [String]) throws -> [BearNote]
    func notes(matchingTag tag: String) throws -> [BearNote]
    func notes(inScope scope: BearScope, activeTags: [String]) throws -> [BearNote]
    func listTags() throws -> [TagSummary]
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote]
}

public protocol BearWriteTransport: Sendable {
    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt
    func insertText(_ request: InsertTextRequest) async throws -> MutationReceipt
    func replaceAll(noteID: String, fullText: String, presentation: BearPresentationOptions) async throws -> MutationReceipt
    func addFile(_ request: AddFileRequest) async throws -> MutationReceipt
    func open(_ request: OpenNoteRequest) async throws -> MutationReceipt
    func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt
}
