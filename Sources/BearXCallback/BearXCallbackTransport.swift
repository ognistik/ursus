import AppKit
import BearCore
import Foundation
import GRDB

public actor BearXCallbackTransport: BearWriteTransport {
    private let builder: BearXCallbackURLBuilder
    private let readStore: BearReadStore
    private let urlOpener: @Sendable (URL, Bool) async throws -> Void
    private let selectedNoteResolveTimeout: Duration
    private let selectedNoteResolver: (@Sendable (URL, Duration) async throws -> String)?
    private let callbackAppInstalledProvider: @Sendable () -> Bool
    private let helperInstalledProvider: @Sendable () -> Bool

    public init(
        builder: BearXCallbackURLBuilder = BearXCallbackURLBuilder(),
        readStore: BearReadStore,
        urlOpener: (@Sendable (URL) async throws -> Void)? = nil,
        selectedNoteResolveTimeout: Duration = .seconds(4),
        selectedNoteResolver: (@Sendable (URL, Duration) async throws -> String)? = nil,
        callbackAppInstalledProvider: @escaping @Sendable () -> Bool = { BearMCPAppLocator.installedAppBundleURL() != nil },
        helperInstalledProvider: @escaping @Sendable () -> Bool = { BearSelectedNoteHelperLocator.installedAppBundleURL() != nil }
    ) {
        self.builder = builder
        self.readStore = readStore
        self.selectedNoteResolveTimeout = selectedNoteResolveTimeout
        self.selectedNoteResolver = selectedNoteResolver
        self.callbackAppInstalledProvider = callbackAppInstalledProvider
        self.helperInstalledProvider = helperInstalledProvider
        if let urlOpener {
            self.urlOpener = { url, _ in
                try await urlOpener(url)
            }
        } else {
            self.urlOpener = Self.defaultOpen
        }
    }

    public init(
        builder: BearXCallbackURLBuilder = BearXCallbackURLBuilder(),
        readStore: BearReadStore,
        urlOpenerWithActivation: @escaping @Sendable (URL, Bool) async throws -> Void,
        selectedNoteResolveTimeout: Duration = .seconds(4),
        selectedNoteResolver: (@Sendable (URL, Duration) async throws -> String)? = nil,
        callbackAppInstalledProvider: @escaping @Sendable () -> Bool = { BearMCPAppLocator.installedAppBundleURL() != nil },
        helperInstalledProvider: @escaping @Sendable () -> Bool = { BearSelectedNoteHelperLocator.installedAppBundleURL() != nil }
    ) {
        self.builder = builder
        self.readStore = readStore
        self.urlOpener = urlOpenerWithActivation
        self.selectedNoteResolveTimeout = selectedNoteResolveTimeout
        self.selectedNoteResolver = selectedNoteResolver
        self.callbackAppInstalledProvider = callbackAppInstalledProvider
        self.helperInstalledProvider = helperInstalledProvider
    }

    public func resolveSelectedNoteID(token: String) async throws -> String {
        let url = try builder.resolveSelectedNoteURL(token: token)
        let callbackAppInstalled = callbackAppInstalledProvider()
        let helperInstalled = helperInstalledProvider()
        BearDebugLog.append("xcallback.resolve-selected-note callbackAppInstalled=\(callbackAppInstalled) helperInstalled=\(helperInstalled) \(debugDescription(for: url))")

        if let selectedNoteResolver {
            return try await selectedNoteResolver(url, selectedNoteResolveTimeout)
        }

        return try await BearSelectedNoteHelperRunner.resolveSelectedNoteID(
            bearURL: url,
            timeout: selectedNoteResolveTimeout
        )
    }

    public func resolveSelectedNoteIDUsingInstalledApp() async throws -> String? {
        guard callbackAppInstalledProvider() else {
            return nil
        }

        let url = try builder.resolveSelectedNoteURL()
        let helperInstalled = helperInstalledProvider()
        BearDebugLog.append("xcallback.resolve-selected-note host=app managedTokenAccess=true helperInstalled=\(helperInstalled) \(debugDescription(for: url))")

        if let selectedNoteResolver {
            return try await selectedNoteResolver(url, selectedNoteResolveTimeout)
        }

        return try await BearSelectedNoteHelperRunner.resolveSelectedNoteID(
            bearURL: url,
            timeout: selectedNoteResolveTimeout
        )
    }

    public func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        let startedAt = Date()
        let url = try builder.createURL(request: request)
        try await openAndLog(action: "create", url: url, activates: request.presentation.opensNoteInUI)

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
        try await openAndLog(action: "insert-text", url: url, activates: request.presentation.opensNoteInUI)

        let updated = try await waitForNoteMutation(noteID: request.noteID, previous: previous)
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
        try await openAndLog(action: "replace-all", url: url, activates: presentation.opensNoteInUI)

        let updated = try await waitForNoteMutation(noteID: noteID, previous: previous)
        return MutationReceipt(
            noteID: noteID,
            title: updated?.title ?? previous?.title,
            status: updated == nil ? "submitted" : "updated",
            modifiedAt: updated?.revision.modifiedAt ?? previous?.revision.modifiedAt
        )
    }

    public func addFile(_ request: AddFileRequest) async throws -> MutationReceipt {
        let previous = try readStore.note(id: request.noteID)
        let previousAttachments = try readStore.attachments(noteID: request.noteID)
        let url = try builder.addFileURL(request: request)
        try await openAndLog(action: "add-file", url: url, activates: request.presentation.opensNoteInUI)

        let updated = try await waitForNoteMutation(
            noteID: request.noteID,
            previous: previous,
            previousAttachmentCount: previousAttachments.count
        )
        return MutationReceipt(
            noteID: request.noteID,
            title: updated?.title ?? previous?.title,
            status: updated == nil ? "submitted" : "updated",
            modifiedAt: updated?.revision.modifiedAt ?? previous?.revision.modifiedAt
        )
    }

    public func open(_ request: OpenNoteRequest) async throws -> MutationReceipt {
        let url = try builder.openURL(request: request)
        try await openAndLog(action: "open", url: url, activates: true)
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
        try await openAndLog(action: "open-tag", url: url, activates: true)

        return TagMutationReceipt(
            tag: request.tag,
            newTag: nil,
            status: "opened"
        )
    }

    public func renameTag(_ request: RenameTagRequest) async throws -> TagMutationReceipt {
        let url = try builder.renameTagURL(request: request)
        try await openAndLog(action: "rename-tag", url: url, activates: false)

        let renamed = try await waitForTagRename(from: request.name, to: request.newName)
        return TagMutationReceipt(
            tag: request.name,
            newTag: request.newName,
            status: renamed ? "renamed" : "submitted"
        )
    }

    public func deleteTag(_ request: DeleteTagRequest) async throws -> TagMutationReceipt {
        let url = try builder.deleteTagURL(request: request)
        try await openAndLog(action: "delete-tag", url: url, activates: false)

        let deleted = try await waitForTagDeletion(tag: request.name)
        return TagMutationReceipt(
            tag: request.name,
            newTag: nil,
            status: deleted ? "deleted" : "submitted"
        )
    }

    public func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        let previous = try readStore.note(id: noteID)
        let url = try builder.archiveURL(noteID: noteID, showWindow: showWindow)
        try await openAndLog(action: "archive", url: url, activates: false)

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

    public func trash(noteID: String) async throws -> MutationReceipt {
        let previous = try readStore.note(id: noteID)
        if previous?.trashed == true {
            return MutationReceipt(
                noteID: noteID,
                title: previous?.title,
                status: "already_trashed",
                modifiedAt: previous?.revision.modifiedAt
            )
        }

        let url = try builder.trashURL(noteID: noteID)
        try await openAndLog(action: "trash", url: url, activates: false)

        let updated: BearNote? = try await poll(timeout: .seconds(4), interval: .milliseconds(200)) {
            guard let note = try self.readStore.note(id: noteID), note.trashed else {
                return nil
            }
            return note
        }

        return MutationReceipt(
            noteID: noteID,
            title: updated?.title ?? previous?.title,
            status: updated == nil ? "submitted" : "trashed",
            modifiedAt: updated?.revision.modifiedAt ?? previous?.revision.modifiedAt
        )
    }

    private func open(url: URL, activates: Bool) async throws {
        try await urlOpener(url, activates)
    }

    private func openAndLog(action: String, url: URL, activates: Bool) async throws {
        BearDebugLog.append("xcallback.\(action) activates=\(activates) \(debugDescription(for: url))")
        try await open(url: url, activates: activates)
    }

    func debugDescription(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "url=\(url.absoluteString)"
        }

        let base = "\(components.scheme ?? "bear")://\(components.host ?? "x-callback-url")\(components.path)"
        let query: String = (components.queryItems ?? []).map { item -> String in
            let value = item.value ?? ""
            switch item.name {
            case "text", "file":
                return "\(item.name)=<redacted length=\(value.count)>"
            case "token", "x-success", "x-error", "state":
                return "\(item.name)=<redacted>"
            default:
                return "\(item.name)=\(value)"
            }
        }.joined(separator: "&")

        guard !query.isEmpty else {
            return "url=\(base)"
        }

        return "url=\(base)?\(query)"
    }

    private static func defaultOpen(url: URL, activates: Bool) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(url, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: BearError.xCallback("Bear did not accept the x-callback action. \(error.localizedDescription)"))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func waitForNoteMutation(
        noteID: String,
        previous: BearNote?,
        previousAttachmentCount: Int? = nil
    ) async throws -> BearNote? {
        try await poll(timeout: .seconds(4), interval: .milliseconds(200)) {
            guard let note = try self.readStore.note(id: noteID) else {
                return nil
            }

            guard let previous else {
                return note
            }

            if note.revision.version != previous.revision.version {
                return note
            }

            if note.revision.modifiedAt != previous.revision.modifiedAt {
                return note
            }

            if note.rawText != previous.rawText {
                return note
            }

            if let previousAttachmentCount {
                let currentAttachments = try self.readStore.attachments(noteID: noteID)
                if currentAttachments.count != previousAttachmentCount {
                    return note
                }
            }

            return nil
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

    private func waitForTagDeletion(tag: String) async throws -> Bool {
        let key = BearTag.deduplicationKey(tag)

        let deleted = try await poll(timeout: .seconds(4), interval: .milliseconds(200)) {
            let notesTags = try self.readStore.listTags(ListTagsQuery(location: .notes, query: nil, underTag: nil))
            let archiveTags = try self.readStore.listTags(ListTagsQuery(location: .archive, query: nil, underTag: nil))
            let allKeys = Set((notesTags + archiveTags).map { BearTag.deduplicationKey($0.name) })
            return allKeys.contains(key) ? nil : true
        }

        return deleted ?? false
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

private extension BearPresentationOptions {
    var opensNoteInUI: Bool {
        openNoteOverride ?? openNote
    }
}
