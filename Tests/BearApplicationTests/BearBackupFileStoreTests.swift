import BearApplication
import BearCore
import Foundation
import Testing

@Test
func backupFileStoreCapturesListsAndLoadsSnapshots() async throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    let store = BearBackupFileStore(
        retentionDays: 30,
        directoryURL: temporaryDirectory
    )
    let note = makeBackupStoreNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1\nLine 2"
    )

    let summary = try #require(await store.capture(note: note, reason: .replaceContent, operationGroupID: "op-1"))
    let listed = try await store.list(noteID: "note-1", limit: nil)
    let snapshot = try #require(await store.snapshot(noteID: "note-1", snapshotID: summary.snapshotID))

    #expect(listed.count == 1)
    #expect(listed.first?.snapshotID == summary.snapshotID)
    #expect(listed.first?.reason == .replaceContent)
    #expect(listed.first?.snippet == "Line 1 Line 2")
    #expect(snapshot.rawText == note.rawText)
    #expect(snapshot.operationGroupID == "op-1")
}

@Test
func backupFileStorePrunesSnapshotsWhenRetentionIsDisabled() async throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    let enabledStore = BearBackupFileStore(
        retentionDays: 30,
        directoryURL: temporaryDirectory
    )
    let note = makeBackupStoreNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1"
    )

    _ = try await enabledStore.capture(note: note, reason: .insertText, operationGroupID: "op-1")
    let disabledStore = BearBackupFileStore(
        retentionDays: 0,
        directoryURL: temporaryDirectory
    )
    let listed = try await disabledStore.list(noteID: nil, limit: nil)

    #expect(listed.isEmpty)
    #expect(fileManager.fileExists(atPath: temporaryDirectory.appendingPathComponent("index.json").path) == false)
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
