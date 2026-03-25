import AppKit
import BearCore
import Foundation
import GRDB

public actor BearXCallbackTransport: BearWriteTransport {
    private let builder: BearXCallbackURLBuilder
    private let readStore: BearReadStore
    private let urlOpener: @Sendable (URL) async throws -> Void

    public init(
        builder: BearXCallbackURLBuilder = BearXCallbackURLBuilder(),
        readStore: BearReadStore,
        urlOpener: (@Sendable (URL) async throws -> Void)? = nil
    ) {
        self.builder = builder
        self.readStore = readStore
        self.urlOpener = urlOpener ?? Self.defaultOpen
    }

    public func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        let startedAt = Date()
        let url = try builder.createURL(request: request)
        BearDebugLog.append("xcallback.create url=\(url.absoluteString)")
        try await open(url: url)

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
        try await open(url: url)

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
        try await open(url: url)

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
        try await open(url: url)

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
        try await open(url: url)
        let note = try readStore.note(id: request.noteID)

        return MutationReceipt(
            noteID: request.noteID,
            title: note?.title,
            status: "opened",
            modifiedAt: note?.revision.modifiedAt
        )
    }

    public func openTag(_ request: OpenTagRequest) async throws -> TagMutationReceipt {
        let url = try builder.openTagURL(request: request)
        BearDebugLog.append("xcallback.open-tag url=\(url.absoluteString)")
        try await open(url: url)

        return TagMutationReceipt(
            tag: request.tag,
            newTag: nil,
            status: "opened"
        )
    }

    public func renameTag(_ request: RenameTagRequest) async throws -> TagMutationReceipt {
        let url = try builder.renameTagURL(request: request)
        BearDebugLog.append("xcallback.rename-tag url=\(url.absoluteString)")
        try await open(url: url)

        let renamed = try await waitForTagRename(from: request.name, to: request.newName)
        return TagMutationReceipt(
            tag: request.name,
            newTag: request.newName,
            status: renamed ? "renamed" : "submitted"
        )
    }

    public func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        let previous = try readStore.note(id: noteID)
        let url = try builder.archiveURL(noteID: noteID, showWindow: showWindow)
        try await open(url: url)

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

    private func open(url: URL) async throws {
        try await urlOpener(url)
    }

    private static func defaultOpen(url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(url, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: BearError.xCallback("Bear did not accept URL: \(url.absoluteString). \(error.localizedDescription)"))
                } else {
                    continuation.resume()
                }
            }
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

    private func waitForTagRename(from oldTag: String, to newTag: String) async throws -> Bool {
        let oldKey = BearTag.deduplicationKey(oldTag)
        let newKey = BearTag.deduplicationKey(newTag)

        let renamed = try await poll(timeout: .seconds(4), interval: .milliseconds(200)) {
            let notesTags = try self.readStore.listTags(ListTagsQuery(location: .notes, query: nil, underTag: nil))
            let archiveTags = try self.readStore.listTags(ListTagsQuery(location: .archive, query: nil, underTag: nil))
            let allKeys = Set((notesTags + archiveTags).map { BearTag.deduplicationKey($0.name) })
            return allKeys.contains(newKey) && !allKeys.contains(oldKey) ? true : nil
        }

        return renamed ?? false
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
            do {
                if let result = try operation() {
                    return result
                }
            } catch let error as DatabaseError where Self.isRetryableReadLock(error) {
                BearDebugLog.append("xcallback.poll retrying after transient sqlite lock code=\(error.resultCode.rawValue) message=\(error.message ?? "unknown")")
            }
            try await Task.sleep(nanoseconds: UInt64(max(intervalNs, 0)))
        }

        return nil
    }

    private static func isRetryableReadLock(_ error: DatabaseError) -> Bool {
        switch error.resultCode {
        case .SQLITE_BUSY,
             .SQLITE_LOCKED,
             .SQLITE_BUSY_RECOVERY,
             .SQLITE_BUSY_SNAPSHOT,
             .SQLITE_BUSY_TIMEOUT,
             .SQLITE_LOCKED_SHAREDCACHE,
             .SQLITE_LOCKED_VTAB:
            return true
        default:
            return false
        }
    }
}
