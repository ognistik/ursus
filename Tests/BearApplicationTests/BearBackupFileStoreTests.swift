import BearApplication
import BearCore
import Foundation
import GRDB
import Testing

@Test
func backupFileStoreCaptureWritesMetadataRowAndSnapshotFile() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let store = makeBackupStore(
        sandbox: sandbox,
        retentionDays: 30,
        now: { Date(timeIntervalSince1970: 1_710_000_500) }
    )
    let note = makeBackupStoreNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1\nLine 2"
    )

    let summary = try #require(await store.capture(note: note, reason: .replaceContent, operationGroupID: "op-1"))
    let listed = try await store.list(
        BackupListQuery(
            noteID: "note-1",
            limit: 10,
            filterKey: "all"
        )
    )
    let snapshot = try #require(await store.snapshot(noteID: "note-1", snapshotID: summary.snapshotID))
    let rows = try fetchMetadataRows(at: sandbox.metadataURL)
    let snapshotURL = sandbox.backupsDirectoryURL
        .appendingPathComponent("note-1", isDirectory: true)
        .appendingPathComponent("\(summary.snapshotID).json", isDirectory: false)

    #expect(rows.count == 1)
    #expect(rows.first?.snapshotID == summary.snapshotID)
    #expect(rows.first?.noteID == "note-1")
    #expect(rows.first?.version == 3)
    #expect(rows.first?.fileName == "\(summary.snapshotID).json")
    #expect(fileManager.fileExists(atPath: snapshotURL.path))
    #expect(listed.items.count == 1)
    #expect(listed.items.first?.snapshotID == summary.snapshotID)
    #expect(listed.items.first?.reason == .replaceContent)
    #expect(snapshot.rawText == note.rawText)
    #expect(snapshot.version == 3)
    #expect(snapshot.operationGroupID == "op-1")
}

@Test
func backupFileStoreListsUnfilteredNoteScopedHistoryFromSQLiteMetadata() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let clock = LockedClock(startingAt: Date(timeIntervalSince1970: 1_710_000_000))
    let store = makeBackupStore(
        sandbox: sandbox,
        retentionDays: 30,
        now: { clock.now() }
    )
    let note = makeBackupStoreNote(id: "note-a", title: "A", body: "Line A")

    let oldest = try #require(await store.capture(note: note, reason: .insertText, operationGroupID: "op-a1"))
    clock.advance(by: 1)
    let middle = try #require(await store.capture(note: note, reason: .replaceContent, operationGroupID: "op-a2"))
    clock.advance(by: 1)
    let newest = try #require(await store.capture(note: note, reason: .addFile, operationGroupID: "op-a3"))

    let listed = try await store.list(
        BackupListQuery(
            noteID: "note-a",
            limit: 10,
            filterKey: "all"
        )
    )

    #expect(listed.items.count == 3)
    #expect(listed.items.map(\.snapshotID) == [newest.snapshotID, middle.snapshotID, oldest.snapshotID])
    #expect(listed.page.returned == 3)
    #expect(listed.page.hasMore == false)
}

@Test
func backupFileStoreFiltersByInclusiveFromDateOnCapturedAt() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let clock = LockedClock(startingAt: Date(timeIntervalSince1970: 1_710_000_000))
    let store = makeBackupStore(
        sandbox: sandbox,
        retentionDays: 30,
        now: { clock.now() }
    )
    let note = makeBackupStoreNote(id: "note-a", title: "A", body: "Line A")

    let first = try #require(await store.capture(note: note, reason: .insertText, operationGroupID: "op-a1"))
    clock.advance(by: 1)
    let second = try #require(await store.capture(note: note, reason: .replaceContent, operationGroupID: "op-a2"))
    clock.advance(by: 1)
    let third = try #require(await store.capture(note: note, reason: .addFile, operationGroupID: "op-a3"))

    let listed = try await store.list(
        BackupListQuery(
            noteID: "note-a",
            from: second.capturedAt,
            limit: 10,
            filterKey: "from-only"
        )
    )

    #expect(listed.items.map(\.snapshotID) == [third.snapshotID, second.snapshotID])
    #expect(listed.items.contains(where: { $0.snapshotID == first.snapshotID }) == false)
}

@Test
func backupFileStoreFiltersByInclusiveToDateOnCapturedAt() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let clock = LockedClock(startingAt: Date(timeIntervalSince1970: 1_710_000_000))
    let store = makeBackupStore(
        sandbox: sandbox,
        retentionDays: 30,
        now: { clock.now() }
    )
    let note = makeBackupStoreNote(id: "note-a", title: "A", body: "Line A")

    let first = try #require(await store.capture(note: note, reason: .insertText, operationGroupID: "op-a1"))
    clock.advance(by: 1)
    let second = try #require(await store.capture(note: note, reason: .replaceContent, operationGroupID: "op-a2"))
    clock.advance(by: 1)
    _ = try await store.capture(note: note, reason: .addFile, operationGroupID: "op-a3")

    let listed = try await store.list(
        BackupListQuery(
            noteID: "note-a",
            to: second.capturedAt,
            limit: 10,
            filterKey: "to-only"
        )
    )

    #expect(listed.items.map(\.snapshotID) == [second.snapshotID, first.snapshotID])
}

@Test
func backupFileStoreFiltersByInclusiveBoundedDateRangeOnCapturedAt() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let clock = LockedClock(startingAt: Date(timeIntervalSince1970: 1_710_000_000))
    let store = makeBackupStore(
        sandbox: sandbox,
        retentionDays: 30,
        now: { clock.now() }
    )
    let note = makeBackupStoreNote(id: "note-a", title: "A", body: "Line A")

    _ = try await store.capture(note: note, reason: .insertText, operationGroupID: "op-a1")
    clock.advance(by: 1)
    let second = try #require(await store.capture(note: note, reason: .replaceContent, operationGroupID: "op-a2"))
    clock.advance(by: 1)
    let third = try #require(await store.capture(note: note, reason: .addFile, operationGroupID: "op-a3"))
    clock.advance(by: 1)
    _ = try await store.capture(note: note, reason: .manual, operationGroupID: "op-a4")

    let listed = try await store.list(
        BackupListQuery(
            noteID: "note-a",
            from: second.capturedAt,
            to: third.capturedAt,
            limit: 10,
            filterKey: "bounded"
        )
    )

    #expect(listed.items.map(\.snapshotID) == [third.snapshotID, second.snapshotID])
}

@Test
func backupFileStoreReturnsEmptyFilteredResultSetWhenNoSnapshotsMatch() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let store = makeBackupStore(
        sandbox: sandbox,
        retentionDays: 30,
        now: { Date(timeIntervalSince1970: 1_710_000_000) }
    )
    let note = makeBackupStoreNote(id: "note-a", title: "A", body: "Line A")

    _ = try await store.capture(note: note, reason: .insertText, operationGroupID: "op-a1")

    let listed = try await store.list(
        BackupListQuery(
            noteID: "note-a",
            from: Date(timeIntervalSince1970: 1_710_100_000),
            to: Date(timeIntervalSince1970: 1_710_100_100),
            limit: 10,
            filterKey: "empty"
        )
    )

    #expect(listed.items.isEmpty)
    #expect(listed.page.returned == 0)
    #expect(listed.page.hasMore == false)
}

@Test
func backupFileStorePaginatesFilteredHistoryAndCarriesFilterIdentityInCursor() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let clock = LockedClock(startingAt: Date(timeIntervalSince1970: 1_710_000_000))
    let store = makeBackupStore(
        sandbox: sandbox,
        retentionDays: 30,
        now: { clock.now() }
    )
    let note = makeBackupStoreNote(id: "note-a", title: "A", body: "Line A")

    _ = try await store.capture(note: note, reason: .insertText, operationGroupID: "op-a1")
    clock.advance(by: 1)
    let second = try #require(await store.capture(note: note, reason: .replaceContent, operationGroupID: "op-a2"))
    clock.advance(by: 1)
    let third = try #require(await store.capture(note: note, reason: .addFile, operationGroupID: "op-a3"))
    clock.advance(by: 1)
    let fourth = try #require(await store.capture(note: note, reason: .manual, operationGroupID: "op-a4"))

    let filterKey = "from-filter"
    let firstPage = try await store.list(
        BackupListQuery(
            noteID: "note-a",
            from: second.capturedAt,
            limit: 2,
            filterKey: filterKey
        )
    )
    let cursor = try BackupListCursorCoder.decode(try #require(firstPage.page.nextCursor))
    let secondPage = try await store.list(
        BackupListQuery(
            noteID: "note-a",
            from: second.capturedAt,
            limit: 2,
            filterKey: filterKey,
            cursor: cursor
        )
    )

    #expect(firstPage.items.map(\.snapshotID) == [fourth.snapshotID, third.snapshotID])
    #expect(firstPage.page.hasMore == true)
    #expect(cursor.noteID == "note-a")
    #expect(cursor.filterKey == filterKey)
    #expect(secondPage.items.map(\.snapshotID) == [second.snapshotID])
    #expect(secondPage.page.hasMore == false)
}

@Test
func backupFileStoreExactSnapshotLookupReturnsRequestedSnapshot() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let clock = LockedClock(startingAt: Date(timeIntervalSince1970: 1_710_000_000))
    let store = makeBackupStore(
        sandbox: sandbox,
        retentionDays: 30,
        now: { clock.now() }
    )
    let note = makeBackupStoreNote(id: "note-a", title: "A", body: "Original")

    let first = try #require(await store.capture(note: note, reason: .insertText, operationGroupID: "op-a1"))
    clock.advance(by: 1)
    let updated = makeBackupStoreNote(id: "note-a", title: "A", body: "Updated")
    _ = try await store.capture(note: updated, reason: .replaceContent, operationGroupID: "op-a2")

    let snapshot = try #require(await store.snapshot(noteID: "note-a", snapshotID: first.snapshotID))

    #expect(snapshot.snapshotID == first.snapshotID)
    #expect(snapshot.rawText == note.rawText)
    #expect(snapshot.reason == .insertText)
}

@Test
func backupFileStoreDeletesOneSnapshotAndAllSnapshotsForNote() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let store = makeBackupStore(
        sandbox: sandbox,
        retentionDays: 30,
        now: { Date(timeIntervalSince1970: 1_710_000_500) }
    )
    let noteA = makeBackupStoreNote(id: "note-a", title: "A", body: "Line A")
    let noteB = makeBackupStoreNote(id: "note-b", title: "B", body: "Line B")

    let snapshotA1 = try #require(await store.capture(note: noteA, reason: .insertText, operationGroupID: "op-a1"))
    let snapshotA2 = try #require(await store.capture(note: noteA, reason: .replaceContent, operationGroupID: "op-a2"))
    let snapshotB1 = try #require(await store.capture(note: noteB, reason: .addFile, operationGroupID: "op-b1"))

    let deletedSingle = try await store.delete(snapshotID: snapshotA1.snapshotID, noteID: nil)
    let deletedAllForNoteB = try await store.deleteAll(noteID: "note-b")
    let remaining = try await store.list(
        BackupListQuery(
            noteID: "note-a",
            limit: 10,
            filterKey: "all"
        )
    )
    let rows = try fetchMetadataRows(at: sandbox.metadataURL)

    #expect(deletedSingle == 1)
    #expect(deletedAllForNoteB == 1)
    #expect(remaining.items.count == 1)
    #expect(remaining.items.first?.snapshotID == snapshotA2.snapshotID)
    #expect(rows.map(\.snapshotID) == [snapshotA2.snapshotID])
    #expect(
        fileManager.fileExists(
            atPath: sandbox.backupsDirectoryURL
                .appendingPathComponent("note-a", isDirectory: true)
                .appendingPathComponent("\(snapshotA1.snapshotID).json", isDirectory: false)
                .path
        ) == false
    )
    #expect(
        fileManager.fileExists(
            atPath: sandbox.backupsDirectoryURL
                .appendingPathComponent("note-b", isDirectory: true)
                .appendingPathComponent("\(snapshotB1.snapshotID).json", isDirectory: false)
                .path
        ) == false
    )
    #expect(fileManager.fileExists(atPath: sandbox.backupsDirectoryURL.appendingPathComponent("note-b", isDirectory: true).path) == false)
}

@Test
func backupFileStoreLazyPruningRemovesExpiredRowsAndFiles() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let clock = LockedClock(startingAt: Date(timeIntervalSince1970: 1_710_000_000))
    let store = makeBackupStore(
        sandbox: sandbox,
        retentionDays: 1,
        now: { clock.now() }
    )
    let original = makeBackupStoreNote(id: "note-a", title: "A", body: "Original")

    let expired = try #require(await store.capture(note: original, reason: .insertText, operationGroupID: "op-old"))
    clock.advance(by: 172_800)
    let current = makeBackupStoreNote(id: "note-a", title: "A", body: "Current")
    let kept = try #require(await store.capture(note: current, reason: .replaceContent, operationGroupID: "op-new"))

    let rows = try fetchMetadataRows(at: sandbox.metadataURL)
    let listed = try await store.list(
        BackupListQuery(
            noteID: "note-a",
            limit: 10,
            filterKey: "all"
        )
    )

    #expect(rows.map(\.snapshotID) == [kept.snapshotID])
    #expect(listed.items.map(\.snapshotID) == [kept.snapshotID])
    #expect(
        fileManager.fileExists(
            atPath: sandbox.backupsDirectoryURL
                .appendingPathComponent("note-a", isDirectory: true)
                .appendingPathComponent("\(expired.snapshotID).json", isDirectory: false)
                .path
        ) == false
    )
    #expect(
        fileManager.fileExists(
            atPath: sandbox.backupsDirectoryURL
                .appendingPathComponent("note-a", isDirectory: true)
                .appendingPathComponent("\(kept.snapshotID).json", isDirectory: false)
                .path
        )
    )
}

@Test
func backupFileStoreRetentionZeroDisablesCaptureAndCleansExistingArtifacts() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let enabledStore = makeBackupStore(sandbox: sandbox, retentionDays: 30)
    let note = makeBackupStoreNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1"
    )

    let summary = try #require(await enabledStore.capture(note: note, reason: .insertText, operationGroupID: "op-1"))
    let disabledStore = makeBackupStore(sandbox: sandbox, retentionDays: 0)
    let capture = try await disabledStore.capture(note: note, reason: .manual, operationGroupID: "op-2")
    let listed = try await disabledStore.list(
        BackupListQuery(
            noteID: "note-1",
            limit: 10,
            filterKey: "all"
        )
    )

    #expect(capture == nil)
    #expect(listed.items.isEmpty)
    #expect(
        fileManager.fileExists(
            atPath: sandbox.backupsDirectoryURL
                .appendingPathComponent("note-1", isDirectory: true)
                .appendingPathComponent("\(summary.snapshotID).json", isDirectory: false)
                .path
        ) == false
    )
    #expect(fileManager.fileExists(atPath: sandbox.metadataURL.path) == false)
    #expect(fileManager.fileExists(atPath: sandbox.quarantineDirectoryURL.path) == false)
}

@Test
func backupFileStoreRebuildsMetadataSelfHealsLayoutAndQuarantinesMalformedFiles() async throws {
    let fileManager = FileManager.default
    let sandbox = makeTemporaryBackupSandbox()
    defer {
        try? fileManager.removeItem(at: sandbox.rootURL)
    }

    let snapshot = BearBackupSnapshot(
        snapshotID: "snapshot-1",
        noteID: "note-a",
        version: 3,
        title: "Inbox",
        rawText: "# Inbox\n\nBody",
        modifiedAt: Date(timeIntervalSince1970: 1_710_000_400),
        capturedAt: Date(timeIntervalSince1970: 1_710_000_450),
        reason: .manual,
        operationGroupID: "op-1"
    )

    let wrongFolderURL = sandbox.backupsDirectoryURL
        .appendingPathComponent("wrong-folder", isDirectory: true)
        .appendingPathComponent("wrong-name.json", isDirectory: false)
    try fileManager.createDirectory(at: wrongFolderURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try BearJSON.makeEncoder().encode(snapshot)
    try data.write(to: wrongFolderURL, options: .atomic)

    let malformedURL = sandbox.backupsDirectoryURL
        .appendingPathComponent("broken", isDirectory: true)
        .appendingPathComponent("bad.json", isDirectory: false)
    try fileManager.createDirectory(at: malformedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: malformedURL, options: .atomic)

    let store = makeBackupStore(
        sandbox: sandbox,
        retentionDays: 30,
        now: { Date(timeIntervalSince1970: 1_710_000_500) }
    )

    let listed = try await store.list(
        BackupListQuery(
            noteID: "note-a",
            limit: 10,
            filterKey: "all"
        )
    )
    let rows = try fetchMetadataRows(at: sandbox.metadataURL)
    let canonicalURL = sandbox.backupsDirectoryURL
        .appendingPathComponent("note-a", isDirectory: true)
        .appendingPathComponent("snapshot-1.json", isDirectory: false)
    let quarantinedBadURL = sandbox.quarantineDirectoryURL.appendingPathComponent("bad.json", isDirectory: false)

    #expect(listed.items.map(\.snapshotID) == ["snapshot-1"])
    #expect(rows.map(\.snapshotID) == ["snapshot-1"])
    #expect(fileManager.fileExists(atPath: canonicalURL.path))
    #expect(fileManager.fileExists(atPath: wrongFolderURL.path) == false)
    #expect(fileManager.fileExists(atPath: sandbox.backupsDirectoryURL.appendingPathComponent("wrong-folder", isDirectory: true).path) == false)
    #expect(fileManager.fileExists(atPath: quarantinedBadURL.path))
    #expect(fileManager.fileExists(atPath: malformedURL.path) == false)
    #expect(fileManager.fileExists(atPath: sandbox.backupsDirectoryURL.appendingPathComponent("broken", isDirectory: true).path) == false)
}

private struct BackupMetadataRow: Sendable {
    let snapshotID: String
    let noteID: String
    let version: Int
    let fileName: String
}

private struct BackupTestSandbox: Sendable {
    let rootURL: URL
    let backupsDirectoryURL: URL
    let metadataURL: URL
    let quarantineDirectoryURL: URL
}

private func makeTemporaryBackupSandbox() -> BackupTestSandbox {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let backupsDirectoryURL = rootURL.appendingPathComponent("Backups", isDirectory: true)
    let metadataURL = rootURL.appendingPathComponent("backups.sqlite", isDirectory: false)
    let quarantineDirectoryURL = backupsDirectoryURL.appendingPathComponent("_quarantine", isDirectory: true)
    return BackupTestSandbox(
        rootURL: rootURL,
        backupsDirectoryURL: backupsDirectoryURL,
        metadataURL: metadataURL,
        quarantineDirectoryURL: quarantineDirectoryURL
    )
}

private func makeBackupStore(
    sandbox: BackupTestSandbox,
    retentionDays: Int,
    now: @escaping @Sendable () -> Date = { Date() }
) -> BearBackupFileStore {
    BearBackupFileStore(
        retentionDays: retentionDays,
        directoryURL: sandbox.backupsDirectoryURL,
        metadataURL: sandbox.metadataURL,
        quarantineDirectoryURL: sandbox.quarantineDirectoryURL,
        now: now
    )
}

private func fetchMetadataRows(at metadataURL: URL) throws -> [BackupMetadataRow] {
    guard FileManager.default.fileExists(atPath: metadataURL.path) else {
        return []
    }

    let queue = try DatabaseQueue(path: metadataURL.path)
    return try queue.read { db in
        try Row.fetchAll(
            db,
            sql: """
            SELECT snapshot_id, note_id, version, file_name
            FROM snapshots
            ORDER BY captured_at DESC, snapshot_id DESC
            """
        ).map {
            BackupMetadataRow(
                snapshotID: $0["snapshot_id"],
                noteID: $0["note_id"],
                version: $0["version"],
                fileName: $0["file_name"]
            )
        }
    }
}

private func makeBackupStoreNote(id: String, title: String, body: String) -> BearNote {
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

private final class LockedClock: @unchecked Sendable {
    private var current: Date

    init(startingAt current: Date) {
        self.current = current
    }

    func now() -> Date {
        current
    }

    func advance(by interval: TimeInterval) {
        current = current.addingTimeInterval(interval)
    }
}
