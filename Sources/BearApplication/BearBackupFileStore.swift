import BearCore
import Foundation
import GRDB

public actor BearBackupFileStore: BearBackupStore {
    private let retentionDays: Int
    private let directoryURL: URL
    private let metadataURL: URL
    private let quarantineDirectoryURL: URL
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private var databaseQueue: DatabaseQueue?

    public init(
        retentionDays: Int,
        directoryURL: URL = BearPaths.backupsDirectoryURL,
        metadataURL: URL = BearPaths.backupsMetadataURL,
        quarantineDirectoryURL: URL = BearPaths.backupsQuarantineDirectoryURL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.retentionDays = max(0, retentionDays)
        self.directoryURL = directoryURL
        self.metadataURL = metadataURL
        self.quarantineDirectoryURL = quarantineDirectoryURL
        self.fileManager = fileManager
        self.now = now
    }

    public func capture(note: BearNote, reason: BackupReason, operationGroupID: String?) throws -> BearBackupSummary? {
        guard retentionDays > 0 else {
            try cleanupDisabledBackups()
            return nil
        }

        let dbQueue = try prepareMetadataStore()
        let snapshotID = UUID().uuidString.lowercased()
        let fileName = "\(snapshotID).json"
        let capturedAt = now()
        let snapshot = BearBackupSnapshot(
            snapshotID: snapshotID,
            noteID: note.ref.identifier,
            version: note.revision.version,
            title: note.title,
            rawText: note.rawText,
            modifiedAt: note.revision.modifiedAt,
            capturedAt: capturedAt,
            reason: reason,
            operationGroupID: operationGroupID
        )

        let snapshotURL = snapshotFileURL(noteID: snapshot.noteID, fileName: fileName)
        try fileManager.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let snapshotData = try BearJSON.makeEncoder().encode(snapshot)
        try snapshotData.write(to: snapshotURL, options: .atomic)
        let record = BackupMetadataRecord(snapshot: snapshot, fileName: fileName)

        try dbQueue.write { db in
            try record.insert(db)
        }
        try syncStoredBackupTreeFingerprint(using: dbQueue)

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
                SELECT snapshot_id, note_id, version, modified_at, captured_at, reason, operation_group_id, file_name
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
                    SELECT snapshot_id, note_id, version, modified_at, captured_at, reason, operation_group_id, file_name
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
                SELECT snapshot_id, note_id, version, modified_at, captured_at, reason, operation_group_id, file_name
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

        let snapshotURL = snapshotFileURL(noteID: entry.noteID, fileName: entry.fileName)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            _ = try dbQueue.write { db in
                try entry.delete(db)
            }
            try syncStoredBackupTreeFingerprint(using: dbQueue)
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
                SELECT snapshot_id, note_id, version, modified_at, captured_at, reason, operation_group_id, file_name
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

        try removeSnapshotFile(noteID: entry.noteID, named: entry.fileName)
        _ = try dbQueue.write { db in
            try entry.delete(db)
        }
        try cleanupEmptyBackupDirectories()
        try syncStoredBackupTreeFingerprint(using: dbQueue)
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
                SELECT snapshot_id, note_id, version, modified_at, captured_at, reason, operation_group_id, file_name
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
            try removeSnapshotFile(noteID: entry.noteID, named: entry.fileName)
        }

        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM snapshots WHERE note_id = ?",
                arguments: [noteID]
            )
        }
        try cleanupEmptyBackupDirectories()
        try syncStoredBackupTreeFingerprint(using: dbQueue)
        return entries.count
    }

    private func prepareMetadataStore() throws -> DatabaseQueue {
        let dbQueue = try openMetadataStore()
        let prunedExpiredSnapshots = try pruneExpiredSnapshots(using: dbQueue)
        if prunedExpiredSnapshots {
            try cleanupEmptyBackupDirectories()
            try persistBackupTreeFingerprint(
                try computeBackupTreeFingerprint(),
                using: dbQueue
            )
        }

        let currentFingerprint = try computeBackupTreeFingerprint()
        let storedFingerprint = try loadStoredBackupTreeFingerprint(using: dbQueue)

        if currentFingerprint != storedFingerprint {
            try rebuildMetadataIndex(using: dbQueue)
            try persistBackupTreeFingerprint(
                try computeBackupTreeFingerprint(),
                using: dbQueue
            )
        }

        return dbQueue
    }

    private func openMetadataStore() throws -> DatabaseQueue {
        if let databaseQueue {
            return databaseQueue
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: metadataURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.label = "ursus.backups"

        let dbQueue = try DatabaseQueue(path: metadataURL.path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createSnapshots") { db in
            try db.create(table: "snapshots") { table in
                table.column("snapshot_id", .text).notNull().primaryKey()
                table.column("note_id", .text).notNull()
                table.column("version", .integer).notNull()
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
        migrator.registerMigration("createMetadataState") { db in
            try db.create(table: "metadata_state") { table in
                table.column("key", .text).notNull().primaryKey()
                table.column("value", .text).notNull()
            }
        }
        try migrator.migrate(dbQueue)
        databaseQueue = dbQueue
        return dbQueue
    }

    private func rebuildMetadataIndex(using dbQueue: DatabaseQueue) throws {
        let records = try collectReconciledMetadataRecords()
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM snapshots")
            for record in records {
                try record.insert(db)
            }
        }
    }

    private func pruneExpiredSnapshots(using dbQueue: DatabaseQueue) throws -> Bool {
        let cutoff = now().addingTimeInterval(-Double(retentionDays) * 86_400).timeIntervalSince1970
        let expiredEntries = try dbQueue.read { db in
            try BackupMetadataRecord.fetchAll(
                db,
                sql: """
                SELECT snapshot_id, note_id, version, modified_at, captured_at, reason, operation_group_id, file_name
                FROM snapshots
                WHERE captured_at < ?
                """,
                arguments: [cutoff]
            )
        }

        guard expiredEntries.isEmpty == false else {
            return false
        }

        for entry in expiredEntries {
            try? removeSnapshotFile(noteID: entry.noteID, named: entry.fileName)
        }

        let snapshotIDs = expiredEntries.map(\.snapshotID)
        try dbQueue.write { db in
            let placeholders = databasePlaceholders(count: snapshotIDs.count)
            try db.execute(
                sql: "DELETE FROM snapshots WHERE snapshot_id IN (\(placeholders))",
                arguments: StatementArguments(snapshotIDs)
            )
        }

        return true
    }

    private func loadStoredBackupTreeFingerprint(using dbQueue: DatabaseQueue) throws -> String? {
        try dbQueue.read { db in
            try BackupMetadataStateRecord.fetchOne(db, key: BackupMetadataStateKey.backupTreeFingerprint.rawValue)?.value
        }
    }

    private func persistBackupTreeFingerprint(_ fingerprint: String, using dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            try BackupMetadataStateRecord(
                key: BackupMetadataStateKey.backupTreeFingerprint.rawValue,
                value: fingerprint
            ).save(db)
        }
    }

    private func syncStoredBackupTreeFingerprint(using dbQueue: DatabaseQueue) throws {
        try persistBackupTreeFingerprint(try computeBackupTreeFingerprint(), using: dbQueue)
    }

    private func computeBackupTreeFingerprint() throws -> String {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let entries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        let parts = try entries.sorted(by: { $0.path < $1.path }).compactMap { url -> String? in
            if url.standardizedFileURL == quarantineDirectoryURL.standardizedFileURL {
                return nil
            }

            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
            let modificationTime = values.contentModificationDate?.timeIntervalSince1970 ?? 0

            if values.isDirectory == true {
                return "D|\(url.lastPathComponent)|\(modificationTime)"
            }

            guard url.pathExtension.lowercased() == "json" else {
                return nil
            }

            let fileSize = values.fileSize ?? 0
            return "F|\(url.lastPathComponent)|\(modificationTime)|\(fileSize)"
        }

        return parts.joined(separator: "\n")
    }

    private func collectReconciledMetadataRecords() throws -> [BackupMetadataRecord] {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let candidateURLs = try enumeratedSnapshotURLs()
        var records: [BackupMetadataRecord] = []
        var indexedSnapshotIDs = Set<String>()

        for candidateURL in candidateURLs {
            guard fileManager.fileExists(atPath: candidateURL.path) else {
                continue
            }

            guard let snapshot = try loadSnapshot(at: candidateURL) else {
                try quarantineSnapshotFile(at: candidateURL)
                continue
            }

            guard snapshotIdentityIsValid(snapshot) else {
                try quarantineSnapshotFile(at: candidateURL)
                continue
            }

            if snapshotIsExpired(snapshot) {
                try? fileManager.removeItem(at: candidateURL)
                continue
            }

            let canonicalURL = snapshotFileURL(noteID: snapshot.noteID, fileName: "\(snapshot.snapshotID).json")
            if candidateURL.standardizedFileURL != canonicalURL.standardizedFileURL {
                let moveResult = try reconcileSnapshotLocation(
                    snapshot: snapshot,
                    from: candidateURL,
                    to: canonicalURL
                )
                switch moveResult {
                case .indexed:
                    break
                case .discarded:
                    continue
                }
            }

            if indexedSnapshotIDs.contains(snapshot.snapshotID) {
                try quarantineSnapshotFile(at: canonicalURL)
                continue
            }

            indexedSnapshotIDs.insert(snapshot.snapshotID)
            records.append(BackupMetadataRecord(snapshot: snapshot, fileName: canonicalURL.lastPathComponent))
        }

        try cleanupEmptyBackupDirectories()
        return records
    }

    private func reconcileSnapshotLocation(
        snapshot: BearBackupSnapshot,
        from sourceURL: URL,
        to canonicalURL: URL
    ) throws -> ReconcileMoveResult {
        try fileManager.createDirectory(
            at: canonicalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: canonicalURL.path) {
            if let canonicalSnapshot = try loadSnapshot(at: canonicalURL),
               snapshotIdentityIsValid(canonicalSnapshot) {
                if canonicalSnapshot == snapshot {
                    try? fileManager.removeItem(at: sourceURL)
                    return .discarded
                }

                try quarantineSnapshotFile(at: sourceURL)
                return .discarded
            }

            try quarantineSnapshotFile(at: canonicalURL)
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return .discarded
        }

        try fileManager.moveItem(at: sourceURL, to: canonicalURL)
        return .indexed
    }

    private func loadSnapshot(at url: URL) throws -> BearBackupSnapshot? {
        let data = try Data(contentsOf: url)
        return try? BearJSON.makeDecoder().decode(BearBackupSnapshot.self, from: data)
    }

    private func snapshotIsExpired(_ snapshot: BearBackupSnapshot) -> Bool {
        let cutoff = now().addingTimeInterval(-Double(retentionDays) * 86_400)
        return snapshot.capturedAt < cutoff
    }

    private func enumeratedSnapshotURLs() throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if url.standardizedFileURL == quarantineDirectoryURL.standardizedFileURL {
                enumerator.skipDescendants()
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                continue
            }

            if url.pathExtension.lowercased() == "json" {
                urls.append(url)
            }
        }

        return urls.sorted { $0.path < $1.path }
    }

    private func cleanupDisabledBackups() throws {
        if fileManager.fileExists(atPath: directoryURL.path) {
            let urls = try enumeratedAllBackupJSONURLs()
            for url in urls {
                try? fileManager.removeItem(at: url)
            }
            try cleanupEmptyBackupDirectories()
        }

        if fileManager.fileExists(atPath: quarantineDirectoryURL.path) {
            let urls = try enumeratedAllBackupJSONURLs(in: quarantineDirectoryURL)
            for url in urls {
                try? fileManager.removeItem(at: url)
            }
            try cleanupEmptyDirectories(startingAt: quarantineDirectoryURL, keepingRoot: true)
        }

        try? fileManager.removeItem(at: metadataURL)
        try? fileManager.removeItem(at: metadataURL.appendingPathExtension("shm"))
        try? fileManager.removeItem(at: metadataURL.appendingPathExtension("wal"))
        databaseQueue = nil
    }

    private func enumeratedAllBackupJSONURLs(in rootURL: URL? = nil) throws -> [URL] {
        let rootURL = rootURL ?? directoryURL
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                continue
            }
            if url.pathExtension.lowercased() == "json" {
                urls.append(url)
            }
        }
        return urls
    }

    private func quarantineSnapshotFile(at sourceURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }

        try fileManager.createDirectory(at: quarantineDirectoryURL, withIntermediateDirectories: true)
        let destinationURL = uniqueQuarantineURL(for: sourceURL)

        guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else {
            return
        }

        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private func uniqueQuarantineURL(for sourceURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        var candidate = quarantineDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
        if fileManager.fileExists(atPath: candidate.path) == false {
            return candidate
        }

        let token = UUID().uuidString.lowercased()
        let fileName = pathExtension.isEmpty
            ? "\(baseName)-\(token)"
            : "\(baseName)-\(token).\(pathExtension)"
        candidate = quarantineDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
        return candidate
    }

    private func removeSnapshotFile(noteID: String, named fileName: String) throws {
        let snapshotURL = snapshotFileURL(noteID: noteID, fileName: fileName)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            return
        }
        try fileManager.removeItem(at: snapshotURL)
    }

    private func snapshotFileURL(noteID: String, fileName: String) -> URL {
        directoryURL
            .appendingPathComponent(noteID, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func cleanupEmptyBackupDirectories() throws {
        try cleanupEmptyDirectories(startingAt: directoryURL, keepingRoot: true)
        try cleanupEmptyDirectories(startingAt: quarantineDirectoryURL, keepingRoot: true)
    }

    private func cleanupEmptyDirectories(startingAt rootURL: URL, keepingRoot: Bool) throws {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return
        }

        var directories: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                directories.append(url)
            }
        }

        for directory in directories.sorted(by: { $0.path.count > $1.path.count }) {
            try removeDirectoryIfEmpty(directory)
        }

        if keepingRoot == false {
            try removeDirectoryIfEmpty(rootURL)
        }
    }

    private func removeDirectoryIfEmpty(_ directoryURL: URL) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        if contents.isEmpty {
            try fileManager.removeItem(at: directoryURL)
        }
    }

    private func snapshotIdentityIsValid(_ snapshot: BearBackupSnapshot) -> Bool {
        pathComponentIsValid(snapshot.noteID) && pathComponentIsValid(snapshot.snapshotID)
    }

    private func pathComponentIsValid(_ value: String) -> Bool {
        value.isEmpty == false &&
        value != "." &&
        value != ".." &&
        value.contains("/") == false &&
        value.contains(":") == false &&
        value.contains("\0") == false
    }

    private func emptyPage(limit: Int) -> BackupSummaryPage {
        BackupSummaryPage(
            items: [],
            page: DiscoveryPageInfo(limit: limit, returned: 0, hasMore: false, nextCursor: nil)
        )
    }
}

private enum ReconcileMoveResult {
    case indexed
    case discarded
}

private struct BackupMetadataRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "snapshots"

    enum Columns {
        static let snapshotID = Column(CodingKeys.snapshotID)
        static let noteID = Column(CodingKeys.noteID)
        static let version = Column(CodingKeys.version)
        static let modifiedAt = Column(CodingKeys.modifiedAt)
        static let capturedAt = Column(CodingKeys.capturedAt)
        static let reason = Column(CodingKeys.reason)
        static let operationGroupID = Column(CodingKeys.operationGroupID)
        static let fileName = Column(CodingKeys.fileName)
    }

    let snapshotID: String
    let noteID: String
    let version: Int
    let modifiedAt: Date
    let capturedAt: Date
    let reason: BackupReason
    let operationGroupID: String?
    let fileName: String

    init(
        snapshotID: String,
        noteID: String,
        version: Int,
        modifiedAt: Date,
        capturedAt: Date,
        reason: BackupReason,
        operationGroupID: String?,
        fileName: String
    ) {
        self.snapshotID = snapshotID
        self.noteID = noteID
        self.version = version
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
            version: snapshot.version,
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
        version = row["version"]
        modifiedAt = Date(timeIntervalSince1970: row["modified_at"])
        capturedAt = Date(timeIntervalSince1970: row["captured_at"])
        reason = BackupReason(rawValue: row["reason"]) ?? .manual
        operationGroupID = row["operation_group_id"]
        fileName = row["file_name"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["snapshot_id"] = snapshotID
        container["note_id"] = noteID
        container["version"] = version
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

private enum BackupMetadataStateKey: String {
    case backupTreeFingerprint = "backup_tree_fingerprint"
}

private struct BackupMetadataStateRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "metadata_state"

    let key: String
    let value: String
}

private func databasePlaceholders(count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ",")
}
