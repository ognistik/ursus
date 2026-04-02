import BearCore
import Foundation
import GRDB

public actor BearBackupFileStore: BearBackupStore {
    private let retentionDays: Int
    private let directoryURL: URL
    private let metadataURL: URL
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private var databaseQueue: DatabaseQueue?

    public init(
        retentionDays: Int,
        directoryURL: URL = BearPaths.backupsDirectoryURL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.retentionDays = max(0, retentionDays)
        self.directoryURL = directoryURL
        self.metadataURL = directoryURL.appendingPathComponent("backups.sqlite", isDirectory: false)
        self.fileManager = fileManager
        self.now = now
    }

    public func capture(note: BearNote, reason: BackupReason, operationGroupID: String?) throws -> BearBackupSummary? {
        guard retentionDays > 0 else {
            try cleanupDisabledBackups()
            return nil
        }

        let dbQueue = try prepareMetadataStore()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let snapshotID = UUID().uuidString.lowercased()
        let fileName = "\(snapshotID).json"
        let capturedAt = now()
        let snapshot = BearBackupSnapshot(
            snapshotID: snapshotID,
            noteID: note.ref.identifier,
            title: note.title,
            rawText: note.rawText,
            modifiedAt: note.revision.modifiedAt,
            capturedAt: capturedAt,
            reason: reason,
            operationGroupID: operationGroupID
        )

        let snapshotData = try BearJSON.makeEncoder().encode(snapshot)
        try snapshotData.write(to: snapshotFileURL(named: fileName), options: .atomic)
        let record = BackupMetadataRecord(snapshot: snapshot, fileName: fileName)

        try dbQueue.write { db in
            try record.insert(db)
        }

        return record.summary
    }

    public func list(_ query: BackupListQuery) throws -> BackupSummaryPage {
        let resolvedLimit = max(1, query.limit)
        guard retentionDays > 0 else {
            try cleanupDisabledBackups()
            return emptyPage(limit: resolvedLimit)
        }

        let dbQueue = try prepareMetadataStore()
        let entries = try dbQueue.read { db in
            try BackupMetadataRecord.fetchAll(
                db,
                sql: """
                SELECT snapshot_id, note_id, modified_at, captured_at, reason, operation_group_id, file_name
                FROM snapshots
                WHERE note_id = ?
                    AND (? IS NULL OR captured_at >= ?)
                    AND (? IS NULL OR captured_at <= ?)
                    AND (
                        ? IS NULL
                        OR captured_at < ?
                        OR (captured_at = ? AND snapshot_id < ?)
                    )
                ORDER BY captured_at DESC, snapshot_id DESC
                LIMIT ?
                """,
                arguments: [
                    query.noteID,
                    query.from == nil ? nil : 1,
                    query.from?.timeIntervalSince1970,
                    query.to == nil ? nil : 1,
                    query.to?.timeIntervalSince1970,
                    query.cursor == nil ? nil : 1,
                    query.cursor?.lastCapturedAt.timeIntervalSince1970,
                    query.cursor?.lastCapturedAt.timeIntervalSince1970,
                    query.cursor?.lastSnapshotID,
                    resolvedLimit + 1,
                ]
            )
        }

        let pageEntries = Array(entries.prefix(resolvedLimit))
        let nextCursor: String?
        if entries.count > resolvedLimit, let lastEntry = pageEntries.last {
            nextCursor = try BackupListCursorCoder.encode(
                BackupListCursor(
                    noteID: query.noteID,
                    filterKey: query.filterKey,
                    lastCapturedAt: lastEntry.capturedAt,
                    lastSnapshotID: lastEntry.snapshotID
                )
            )
        } else {
            nextCursor = nil
        }

        return BackupSummaryPage(
            items: pageEntries.map(\.summary),
            page: DiscoveryPageInfo(
                limit: resolvedLimit,
                returned: pageEntries.count,
                hasMore: nextCursor != nil,
                nextCursor: nextCursor
            )
        )
    }

    public func snapshot(noteID: String, snapshotID: String?) throws -> BearBackupSnapshot? {
        guard retentionDays > 0 else {
            try cleanupDisabledBackups()
            return nil
        }

        let dbQueue = try prepareMetadataStore()
        let entry = try dbQueue.read { db in
            if let snapshotID {
                return try BackupMetadataRecord.fetchOne(
                    db,
                    sql: """
                    SELECT snapshot_id, note_id, modified_at, captured_at, reason, operation_group_id, file_name
                    FROM snapshots
                    WHERE snapshot_id = ? AND note_id = ?
                    LIMIT 1
                    """,
                    arguments: [snapshotID, noteID]
                )
            }

            return try BackupMetadataRecord.fetchOne(
                db,
                sql: """
                SELECT snapshot_id, note_id, modified_at, captured_at, reason, operation_group_id, file_name
                FROM snapshots
                WHERE note_id = ?
                ORDER BY captured_at DESC, snapshot_id DESC
                LIMIT 1
                """,
                arguments: [noteID]
            )
        }

        guard let entry else {
            return nil
        }

        let snapshotURL = snapshotFileURL(named: entry.fileName)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            _ = try dbQueue.write { db in
                try entry.delete(db)
            }
            return nil
        }

        let data = try Data(contentsOf: snapshotURL)
        return try BearJSON.makeDecoder().decode(BearBackupSnapshot.self, from: data)
    }

    public func delete(snapshotID: String, noteID: String?) throws -> Int {
        guard retentionDays > 0 else {
            try cleanupDisabledBackups()
            return 0
        }

        let dbQueue = try prepareMetadataStore()
        guard let entry = try dbQueue.read({ db in
            try BackupMetadataRecord.fetchOne(
                db,
                sql: """
                SELECT snapshot_id, note_id, modified_at, captured_at, reason, operation_group_id, file_name
                FROM snapshots
                WHERE snapshot_id = ?
                    AND (? IS NULL OR note_id = ?)
                LIMIT 1
                """,
                arguments: [snapshotID, noteID, noteID]
            )
        }) else {
            return 0
        }

        try removeSnapshotFile(named: entry.fileName)
        _ = try dbQueue.write { db in
            try entry.delete(db)
        }
        return 1
    }

    public func deleteAll(noteID: String) throws -> Int {
        guard retentionDays > 0 else {
            try cleanupDisabledBackups()
            return 0
        }

        let dbQueue = try prepareMetadataStore()
        let entries = try dbQueue.read { db in
            try BackupMetadataRecord.fetchAll(
                db,
                sql: """
                SELECT snapshot_id, note_id, modified_at, captured_at, reason, operation_group_id, file_name
                FROM snapshots
                WHERE note_id = ?
                """,
                arguments: [noteID]
            )
        }

        guard !entries.isEmpty else {
            return 0
        }

        for entry in entries {
            try removeSnapshotFile(named: entry.fileName)
        }

        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM snapshots WHERE note_id = ?",
                arguments: [noteID]
            )
        }
        return entries.count
    }

    private func prepareMetadataStore() throws -> DatabaseQueue {
        let dbQueue = try openMetadataStore()
        try pruneExpiredSnapshots(using: dbQueue)
        return dbQueue
    }

    private func openMetadataStore() throws -> DatabaseQueue {
        if let databaseQueue {
            return databaseQueue
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var configuration = Configuration()
        configuration.label = "ursus.backups"

        let dbQueue = try DatabaseQueue(path: metadataURL.path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createSnapshots") { db in
            try db.create(table: "snapshots") { table in
                table.column("snapshot_id", .text).notNull().primaryKey()
                table.column("note_id", .text).notNull()
                table.column("modified_at", .double).notNull()
                table.column("captured_at", .double).notNull()
                table.column("reason", .text).notNull()
                table.column("operation_group_id", .text)
                table.column("file_name", .text).notNull()
            }

            try db.create(
                index: "snapshots_note_captured_snapshot_idx",
                on: "snapshots",
                columns: ["note_id", "captured_at", "snapshot_id"]
            )
            try db.create(
                index: "snapshots_captured_at_idx",
                on: "snapshots",
                columns: ["captured_at"]
            )
        }
        try migrator.migrate(dbQueue)
        databaseQueue = dbQueue
        return dbQueue
    }

    private func pruneExpiredSnapshots(using dbQueue: DatabaseQueue) throws {
        let cutoff = now().addingTimeInterval(-Double(retentionDays) * 86_400).timeIntervalSince1970
        let expiredEntries = try dbQueue.read { db in
            try BackupMetadataRecord.fetchAll(
                db,
                sql: """
                SELECT snapshot_id, note_id, modified_at, captured_at, reason, operation_group_id, file_name
                FROM snapshots
                WHERE captured_at < ?
                """,
                arguments: [cutoff]
            )
        }

        guard !expiredEntries.isEmpty else {
            return
        }

        for entry in expiredEntries {
            try? removeSnapshotFile(named: entry.fileName)
        }

        let snapshotIDs = expiredEntries.map(\.snapshotID)
        try dbQueue.write { db in
            let placeholders = databasePlaceholders(count: snapshotIDs.count)
            try db.execute(
                sql: "DELETE FROM snapshots WHERE snapshot_id IN (\(placeholders))",
                arguments: StatementArguments(snapshotIDs)
            )
        }
    }

    private func cleanupDisabledBackups() throws {
        if fileManager.fileExists(atPath: directoryURL.path) {
            let contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in contents where url.pathExtension.lowercased() == "json" {
                try? fileManager.removeItem(at: url)
            }
        }

        try? fileManager.removeItem(at: metadataURL)
        try? fileManager.removeItem(at: metadataURL.appendingPathExtension("shm"))
        try? fileManager.removeItem(at: metadataURL.appendingPathExtension("wal"))
        databaseQueue = nil
    }

    private func removeSnapshotFile(named fileName: String) throws {
        let snapshotURL = snapshotFileURL(named: fileName)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            return
        }
        try fileManager.removeItem(at: snapshotURL)
    }

    private func snapshotFileURL(named fileName: String) -> URL {
        directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private func emptyPage(limit: Int) -> BackupSummaryPage {
        BackupSummaryPage(
            items: [],
            page: DiscoveryPageInfo(limit: limit, returned: 0, hasMore: false, nextCursor: nil)
        )
    }
}

private struct BackupMetadataRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "snapshots"

    enum Columns {
        static let snapshotID = Column(CodingKeys.snapshotID)
        static let noteID = Column(CodingKeys.noteID)
        static let modifiedAt = Column(CodingKeys.modifiedAt)
        static let capturedAt = Column(CodingKeys.capturedAt)
        static let reason = Column(CodingKeys.reason)
        static let operationGroupID = Column(CodingKeys.operationGroupID)
        static let fileName = Column(CodingKeys.fileName)
    }

    let snapshotID: String
    let noteID: String
    let modifiedAt: Date
    let capturedAt: Date
    let reason: BackupReason
    let operationGroupID: String?
    let fileName: String

    init(
        snapshotID: String,
        noteID: String,
        modifiedAt: Date,
        capturedAt: Date,
        reason: BackupReason,
        operationGroupID: String?,
        fileName: String
    ) {
        self.snapshotID = snapshotID
        self.noteID = noteID
        self.modifiedAt = modifiedAt
        self.capturedAt = capturedAt
        self.reason = reason
        self.operationGroupID = operationGroupID
        self.fileName = fileName
    }

    init(snapshot: BearBackupSnapshot, fileName: String) {
        self.init(
            snapshotID: snapshot.snapshotID,
            noteID: snapshot.noteID,
            modifiedAt: snapshot.modifiedAt,
            capturedAt: snapshot.capturedAt,
            reason: snapshot.reason,
            operationGroupID: snapshot.operationGroupID,
            fileName: fileName
        )
    }

    init(row: Row) {
        snapshotID = row["snapshot_id"]
        noteID = row["note_id"]
        modifiedAt = Date(timeIntervalSince1970: row["modified_at"])
        capturedAt = Date(timeIntervalSince1970: row["captured_at"])
        reason = BackupReason(rawValue: row["reason"]) ?? .manual
        operationGroupID = row["operation_group_id"]
        fileName = row["file_name"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["snapshot_id"] = snapshotID
        container["note_id"] = noteID
        container["modified_at"] = modifiedAt.timeIntervalSince1970
        container["captured_at"] = capturedAt.timeIntervalSince1970
        container["reason"] = reason.rawValue
        container["operation_group_id"] = operationGroupID
        container["file_name"] = fileName
    }

    var summary: BearBackupSummary {
        BearBackupSummary(
            snapshotID: snapshotID,
            noteID: noteID,
            modifiedAt: modifiedAt,
            capturedAt: capturedAt,
            reason: reason
        )
    }
}

private func databasePlaceholders(count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ",")
}
