import BearCore
import Foundation
import GRDB

public final class BearBackupAvailabilityReader: @unchecked Sendable {
    private let retentionDays: Int
    private let metadataURL: URL
    private let fileManager: FileManager

    public init(
        retentionDays: Int,
        metadataURL: URL = BearPaths.backupsMetadataURL,
        fileManager: FileManager = .default
    ) {
        self.retentionDays = max(0, retentionDays)
        self.metadataURL = metadataURL
        self.fileManager = fileManager
    }

    public var isEnabled: Bool {
        retentionDays > 0
    }

    public func noteIDsWithBackups(_ noteIDs: [String]) throws -> Set<String> {
        guard isEnabled else {
            return []
        }

        let normalizedNoteIDs = Array(Set(noteIDs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }))
            .sorted()

        guard !normalizedNoteIDs.isEmpty else {
            return []
        }

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return []
        }

        var configuration = Configuration()
        configuration.readonly = true
        configuration.label = "ursus.backups.lookup"
        let dbQueue = try DatabaseQueue(path: metadataURL.path, configuration: configuration)

        let placeholders = Array(repeating: "?", count: normalizedNoteIDs.count).joined(separator: ",")
        let sql = """
            SELECT DISTINCT note_id
            FROM snapshots
            WHERE note_id IN (\(placeholders))
            """

        return try dbQueue.read { db in
            let arguments = StatementArguments(normalizedNoteIDs)
            return Set(try String.fetchAll(db, sql: sql, arguments: arguments))
        }
    }
}
