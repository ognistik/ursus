import AppKit
import BearCore
import Foundation

public actor BearXCallbackTransport: BearWriteTransport {
    private let builder: BearXCallbackURLBuilder
    private let readStore: BearReadStore

    public init(builder: BearXCallbackURLBuilder = BearXCallbackURLBuilder(), readStore: BearReadStore) {
        self.builder = builder
        self.readStore = readStore
    }

    public func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        let startedAt = Date()
        let url = try builder.createURL(request: request)
        BearDebugLog.append("xcallback.create url=\(url.absoluteString)")
        try open(url: url)

        let matched = try await poll(timeout: .seconds(4), interval: .milliseconds(200)) {
            let matches = try self.readStore.findNotes(title: request.title, modifiedAfter: startedAt.addingTimeInterval(-1))
            return matches.sorted { $0.revision.modifiedAt > $1.revision.modifiedAt }.first
        }

        return MutationReceipt(
            noteID: matched?.ref.identifier,
            title: request.title,
            status: matched == nil ? "submitted" : "created",
            modifiedAt: matched?.revision.modifiedAt
        )
    }

    public func insertText(_ request: InsertTextRequest) async throws -> MutationReceipt {
        let previous = try readStore.note(id: request.noteID)
        let url = try builder.insertTextURL(request: request)
        try open(url: url)

        let updated = try await waitForVersionChange(noteID: request.noteID, previousVersion: previous?.revision.version)
        return MutationReceipt(
            noteID: request.noteID,
            title: updated?.title ?? previous?.title,
            status: updated == nil ? "submitted" : "updated",
            modifiedAt: updated?.revision.modifiedAt ?? previous?.revision.modifiedAt
        )
    }

    public func replaceAll(noteID: String, fullText: String, presentation: BearPresentationOptions) async throws -> MutationReceipt {
        let previous = try readStore.note(id: noteID)
        let url = try builder.replaceAllURL(noteID: noteID, fullText: fullText, presentation: presentation)
        try open(url: url)

        let updated = try await waitForVersionChange(noteID: noteID, previousVersion: previous?.revision.version)
        return MutationReceipt(
            noteID: noteID,
            title: updated?.title ?? previous?.title,
            status: updated == nil ? "submitted" : "updated",
            modifiedAt: updated?.revision.modifiedAt ?? previous?.revision.modifiedAt
        )
    }

    public func addFile(_ request: AddFileRequest) async throws -> MutationReceipt {
        let previous = try readStore.note(id: request.noteID)
        let url = try builder.addFileURL(request: request)
        try open(url: url)

        let updated = try await waitForVersionChange(noteID: request.noteID, previousVersion: previous?.revision.version)
        return MutationReceipt(
            noteID: request.noteID,
            title: updated?.title ?? previous?.title,
            status: updated == nil ? "submitted" : "updated",
            modifiedAt: updated?.revision.modifiedAt ?? previous?.revision.modifiedAt
        )
    }

    public func open(_ request: OpenNoteRequest) async throws -> MutationReceipt {
        let url = try builder.openURL(request: request)
        BearDebugLog.append("xcallback.open url=\(url.absoluteString)")
        try open(url: url)
        let note = try readStore.note(id: request.noteID)

        return MutationReceipt(
            noteID: request.noteID,
            title: note?.title,
            status: "opened",
            modifiedAt: note?.revision.modifiedAt
        )
    }

    public func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        let previous = try readStore.note(id: noteID)
        let url = try builder.archiveURL(noteID: noteID, showWindow: showWindow)
        try open(url: url)

        let updated: BearNote? = try await poll(timeout: .seconds(4), interval: .milliseconds(200)) {
            guard let note = try self.readStore.note(id: noteID), note.archived else {
                return nil
            }
            return note
        }

        return MutationReceipt(
            noteID: noteID,
            title: updated?.title ?? previous?.title,
            status: updated == nil ? "submitted" : "archived",
            modifiedAt: updated?.revision.modifiedAt ?? previous?.revision.modifiedAt
        )
    }

    private func open(url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw BearError.xCallback("Bear did not accept URL: \(url.absoluteString)")
        }
    }

    private func waitForVersionChange(noteID: String, previousVersion: Int?) async throws -> BearNote? {
        try await poll(timeout: .seconds(4), interval: .milliseconds(200)) {
            guard let note = try self.readStore.note(id: noteID) else {
                return nil
            }

            guard let previousVersion else {
                return note
            }

            return note.revision.version != previousVersion ? note : nil
        }
    }

    private func poll<T>(
        timeout: Duration,
        interval: Duration,
        operation: () throws -> T?
    ) async throws -> T? {
        let timeoutNs = timeout.components.seconds * 1_000_000_000 + Int64(timeout.components.attoseconds / 1_000_000_000)
        let intervalNs = interval.components.seconds * 1_000_000_000 + Int64(interval.components.attoseconds / 1_000_000_000)
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(timeoutNs, 0))

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let result = try operation() {
                return result
            }
            try await Task.sleep(nanoseconds: UInt64(max(intervalNs, 0)))
        }

        return nil
    }
}
