import BearCore
import Foundation

public actor BearBackupFileStore: BearBackupStore {
    private let retentionDays: Int
    private let directoryURL: URL
    private let indexURL: URL
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    public init(
        retentionDays: Int,
        directoryURL: URL = BearPaths.backupsDirectoryURL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.retentionDays = max(0, retentionDays)
        self.directoryURL = directoryURL
        self.indexURL = directoryURL.appendingPathComponent("index.json", isDirectory: false)
        self.fileManager = fileManager
        self.now = now
    }

    public func capture(note: BearNote, reason: BackupReason, operationGroupID: String?) throws -> BearBackupSummary? {
        let index = try loadPrunedIndex()
        guard retentionDays > 0 else {
            return nil
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let snapshotID = UUID().uuidString.lowercased()
        let fileName = "\(snapshotID).json"
        let capturedAt = now()
        let snapshot = BearBackupSnapshot(
            snapshotID: snapshotID,
            noteID: note.ref.identifier,
            title: note.title,
            rawText: note.rawText,
            version: note.revision.version,
            modifiedAt: note.revision.modifiedAt,
            capturedAt: capturedAt,
            reason: reason,
            operationGroupID: operationGroupID
        )

        let snapshotData = try BearJSON.makeEncoder().encode(snapshot)
        try snapshotData.write(to: directoryURL.appendingPathComponent(fileName, isDirectory: false), options: .atomic)

        var updatedIndex = index
        updatedIndex.entries.append(BackupIndexEntry(snapshot: snapshot, fileName: fileName))
        try writeIndex(updatedIndex)
        return BackupIndexEntry(snapshot: snapshot, fileName: fileName).summary
    }

    public func list(noteID: String?, limit: Int?) throws -> [BearBackupSummary] {
        let index = try loadPrunedIndex()
        let entries = index.entries
            .filter { noteID == nil || $0.noteID == noteID }
            .sorted(by: backupSortOrder)

        guard let limit else {
            return entries.map(\.summary)
        }

        return Array(entries.prefix(max(0, limit))).map(\.summary)
    }

    public func snapshot(noteID: String, snapshotID: String?) throws -> BearBackupSnapshot? {
        let index = try loadPrunedIndex()
        let entries = index.entries
            .filter { $0.noteID == noteID }
            .sorted(by: backupSortOrder)

        let entry: BackupIndexEntry?
        if let snapshotID {
            entry = entries.first(where: { $0.snapshotID == snapshotID })
        } else {
            entry = entries.first
        }

        guard let entry else {
            return nil
        }

        let snapshotURL = directoryURL.appendingPathComponent(entry.fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            var updatedIndex = index
            updatedIndex.entries.removeAll { $0.snapshotID == entry.snapshotID }
            try writeIndex(updatedIndex)
            return nil
        }

        let data = try Data(contentsOf: snapshotURL)
        return try BearJSON.makeDecoder().decode(BearBackupSnapshot.self, from: data)
    }

    private func loadPrunedIndex() throws -> BackupIndex {
        let index = try loadIndex()
        let pruned = try prune(index)
        if pruned != index {
            try writeIndex(pruned)
        }
        return pruned
    }

    private func loadIndex() throws -> BackupIndex {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return BackupIndex(entries: [])
        }

        let data = try Data(contentsOf: indexURL)
        return try BearJSON.makeDecoder().decode(BackupIndex.self, from: data)
    }

    private func writeIndex(_ index: BackupIndex) throws {
        guard retentionDays > 0 || !index.entries.isEmpty else {
            if fileManager.fileExists(atPath: indexURL.path) {
                try? fileManager.removeItem(at: indexURL)
            }
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try BearJSON.makeEncoder().encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    private func prune(_ index: BackupIndex) throws -> BackupIndex {
        guard !index.entries.isEmpty else {
            return index
        }

        let cutoff: Date? = retentionDays > 0
            ? now().addingTimeInterval(-Double(retentionDays) * 86_400)
            : now()

        var kept: [BackupIndexEntry] = []
        for entry in index.entries {
            let shouldKeep = retentionDays > 0 && cutoff.map { entry.capturedAt >= $0 } == true
            if shouldKeep {
                kept.append(entry)
                continue
            }

            let snapshotURL = directoryURL.appendingPathComponent(entry.fileName, isDirectory: false)
            if fileManager.fileExists(atPath: snapshotURL.path) {
                try? fileManager.removeItem(at: snapshotURL)
            }
        }

        if retentionDays == 0, fileManager.fileExists(atPath: indexURL.path) {
            try? fileManager.removeItem(at: indexURL)
        }

        return BackupIndex(entries: kept)
    }

    private func backupSortOrder(_ lhs: BackupIndexEntry, _ rhs: BackupIndexEntry) -> Bool {
        if lhs.capturedAt != rhs.capturedAt {
            return lhs.capturedAt > rhs.capturedAt
        }
        return lhs.snapshotID > rhs.snapshotID
    }
}

private struct BackupIndex: Codable, Hashable, Sendable {
    var entries: [BackupIndexEntry]
}

private struct BackupIndexEntry: Codable, Hashable, Sendable {
    let snapshotID: String
    let noteID: String
    let title: String
    let version: Int
    let modifiedAt: Date
    let capturedAt: Date
    let reason: BackupReason
    let operationGroupID: String?
    let snippet: String?
    let fileName: String

    init(snapshot: BearBackupSnapshot, fileName: String) {
        self.snapshotID = snapshot.snapshotID
        self.noteID = snapshot.noteID
        self.title = snapshot.title
        self.version = snapshot.version
        self.modifiedAt = snapshot.modifiedAt
        self.capturedAt = snapshot.capturedAt
        self.reason = snapshot.reason
        self.operationGroupID = snapshot.operationGroupID
        self.snippet = Self.makeSnippet(rawText: snapshot.rawText, fallbackTitle: snapshot.title)
        self.fileName = fileName
    }

    var summary: BearBackupSummary {
        BearBackupSummary(
            snapshotID: snapshotID,
            noteID: noteID,
            title: title,
            version: version,
            modifiedAt: modifiedAt,
            capturedAt: capturedAt,
            reason: reason,
            snippet: snippet
        )
    }

    private static func makeSnippet(rawText: String, fallbackTitle: String) -> String? {
        let body = BearText.parse(rawText: rawText, fallbackTitle: fallbackTitle).body
        let normalized = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !normalized.isEmpty else {
            return nil
        }

        let limit = 160
        guard normalized.count > limit else {
            return normalized
        }

        let cutoff = normalized.index(normalized.startIndex, offsetBy: limit)
        let prefix = String(normalized[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "…"
    }
}
