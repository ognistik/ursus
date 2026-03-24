import BearCore
import Foundation
import GRDB

public final class BearDatabaseReader: @unchecked Sendable, BearReadStore {
    private let databaseQueue: DatabaseQueue

    public init(databaseURL: URL) throws {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.label = "bear-mcp.db"
        self.databaseQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
    }

    public func searchNotes(_ query: NoteSearchQuery) throws -> [BearNote] {
        let argumentValues: [DatabaseValueConvertible] = [
            archivedFlag(for: query.location),
            likePattern(for: query.query),
            likePattern(for: query.query),
            query.limit,
        ]

        return try fetchNotes(
            sql: """
            SELECT
                n.Z_PK AS pk,
                n.ZUNIQUEIDENTIFIER AS noteID,
                n.ZTITLE AS title,
                n.ZTEXT AS rawText,
                n.ZVERSION AS version,
                n.ZCREATIONDATE AS creationDate,
                n.ZMODIFICATIONDATE AS modificationDate,
                n.ZARCHIVED AS archived,
                n.ZTRASHED AS trashed,
                n.ZENCRYPTED AS encrypted,
                COALESCE(GROUP_CONCAT(t.ZTITLE, '|'), '') AS tags
            FROM ZSFNOTE n
            LEFT JOIN Z_5TAGS nt ON nt.Z_5NOTES = n.Z_PK
            LEFT JOIN ZSFNOTETAG t ON t.Z_PK = nt.Z_13TAGS
            WHERE n.ZPERMANENTLYDELETED = 0
                AND n.ZTRASHED = 0
                AND n.ZARCHIVED = ?
                AND (n.ZTITLE LIKE ? ESCAPE '\\' OR n.ZTEXT LIKE ? ESCAPE '\\')
            GROUP BY n.Z_PK
            ORDER BY n.ZMODIFICATIONDATE DESC
            LIMIT ?
            """,
            arguments: argumentValues
        )
    }

    public func note(id: String) throws -> BearNote? {
        let notes = try notes(matchingSQL: "n.ZUNIQUEIDENTIFIER = ?", arguments: [id], limit: 1)
        return notes.first
    }

    public func notes(withIDs ids: [String]) throws -> [BearNote] {
        guard !ids.isEmpty else {
            return []
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        return try notes(
            matchingSQL: "n.ZUNIQUEIDENTIFIER IN (\(placeholders))",
            arguments: ids,
            limit: ids.count
        )
    }

    public func notes(matchingAnyTags tags: [String], location: BearNoteLocation, limit: Int) throws -> [BearNote] {
        let normalizedTags = tags.map(normalizedTag).filter { !$0.isEmpty }
        guard !normalizedTags.isEmpty else {
            return []
        }

        let placeholders = Array(repeating: "?", count: normalizedTags.count).joined(separator: ",")
        return try notes(
            matchingSQL: """
            n.ZTRASHED = 0
                AND n.ZARCHIVED = ?
                AND EXISTS (
                    SELECT 1
                    FROM Z_5TAGS nt2
                    JOIN ZSFNOTETAG t2 ON t2.Z_PK = nt2.Z_13TAGS
                    WHERE nt2.Z_5NOTES = n.Z_PK
                        AND t2.ZTITLE IN (\(placeholders))
                )
            """,
            arguments: [archivedFlag(for: location)] + normalizedTags,
            limit: limit
        )
    }

    public func listTags() throws -> [TagSummary] {
        try databaseQueue.read { db in
            try TagRow.fetchAll(
                db,
                sql: """
                SELECT
                    t.ZTITLE AS title,
                    t.ZUNIQUEIDENTIFIER AS identifier,
                    COUNT(nt.Z_5NOTES) AS noteCount
                FROM ZSFNOTETAG t
                LEFT JOIN Z_5TAGS nt ON nt.Z_13TAGS = t.Z_PK
                GROUP BY t.Z_PK
                ORDER BY LOWER(t.ZTITLE) ASC
                """
            )
            .map(\.summary)
        }
    }

    public func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] {
        var arguments: [DatabaseValueConvertible] = [title]
        var whereClause = "n.ZTITLE = ?"
        if let modifiedAfter {
            whereClause += " AND n.ZMODIFICATIONDATE >= ?"
            arguments.append(modifiedAfter.timeIntervalSinceReferenceDate)
        }

        return try notes(matchingSQL: whereClause, arguments: arguments, limit: 10)
    }

    private func notes(
        matchingSQL whereClause: String,
        arguments: [DatabaseValueConvertible],
        limit: Int
    ) throws -> [BearNote] {
        try fetchNotes(
            sql: """
            SELECT
                n.Z_PK AS pk,
                n.ZUNIQUEIDENTIFIER AS noteID,
                n.ZTITLE AS title,
                n.ZTEXT AS rawText,
                n.ZVERSION AS version,
                n.ZCREATIONDATE AS creationDate,
                n.ZMODIFICATIONDATE AS modificationDate,
                n.ZARCHIVED AS archived,
                n.ZTRASHED AS trashed,
                n.ZENCRYPTED AS encrypted,
                COALESCE(GROUP_CONCAT(t.ZTITLE, '|'), '') AS tags
            FROM ZSFNOTE n
            LEFT JOIN Z_5TAGS nt ON nt.Z_5NOTES = n.Z_PK
            LEFT JOIN ZSFNOTETAG t ON t.Z_PK = nt.Z_13TAGS
            WHERE n.ZPERMANENTLYDELETED = 0
                AND \(whereClause)
            GROUP BY n.Z_PK
            ORDER BY n.ZMODIFICATIONDATE DESC
            LIMIT ?
            """,
            arguments: arguments + [limit]
        )
    }

    private func likePattern(for query: String) -> String {
        "%\(query.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
    }

    private func normalizedTag(_ tag: String) -> String {
        tag.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func archivedFlag(for location: BearNoteLocation) -> Int {
        switch location {
        case .notes:
            0
        case .archive:
            1
        }
    }

    private func fetchNotes(
        sql: String,
        arguments: [DatabaseValueConvertible]
    ) throws -> [BearNote] {
        try databaseQueue.read { db in
            try NoteRow.fetchAll(
                db,
                sql: sql,
                arguments: StatementArguments(arguments) ?? StatementArguments()
            )
            .map(\.note)
        }
    }
}

private struct NoteRow: FetchableRecord, Decodable {
    let noteID: String
    let title: String?
    let rawText: String?
    let version: Int?
    let creationDate: Double?
    let modificationDate: Double?
    let archived: Int?
    let trashed: Int?
    let encrypted: Int?
    let tags: String?

    var note: BearNote {
        let resolvedTitle = title ?? ""
        let resolvedRawText = rawText ?? BearText.composeRawText(title: resolvedTitle, body: "")
        let parsedText = BearText.parse(rawText: resolvedRawText, fallbackTitle: resolvedTitle)

        return BearNote(
            ref: NoteRef(identifier: noteID),
            revision: NoteRevision(
                version: version ?? 0,
                createdAt: Date(timeIntervalSinceReferenceDate: creationDate ?? modificationDate ?? 0),
                modifiedAt: Date(timeIntervalSinceReferenceDate: modificationDate ?? 0)
            ),
            title: resolvedTitle,
            body: parsedText.body,
            rawText: resolvedRawText,
            tags: splitTags(tags),
            archived: (archived ?? 0) != 0,
            trashed: (trashed ?? 0) != 0,
            encrypted: (encrypted ?? 0) != 0
        )
    }

    private func splitTags(_ tags: String?) -> [String] {
        guard let tags, !tags.isEmpty else {
            return []
        }
        return tags.split(separator: "|").map(String.init)
    }
}

private struct TagRow: FetchableRecord, Decodable {
    let title: String
    let identifier: String?
    let noteCount: Int

    var summary: TagSummary {
        TagSummary(name: title, identifier: identifier, noteCount: noteCount)
    }
}
