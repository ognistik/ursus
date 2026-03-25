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

    public func searchNotes(_ query: NoteSearchQuery) throws -> DiscoveryNoteBatch {
        let pagination = paginationClause(for: query.paging.cursor)
        let argumentValues: [DatabaseValueConvertible] = [
            archivedFlag(for: query.location),
            likePattern(for: query.query),
            likePattern(for: query.query),
        ] + pagination.arguments + [query.paging.limit + 1]

        return try fetchDiscoveryBatch(
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
                \(pagination.sql)
            GROUP BY n.Z_PK
            ORDER BY n.ZMODIFICATIONDATE DESC, n.ZUNIQUEIDENTIFIER DESC
            LIMIT ?
            """,
            arguments: argumentValues,
            limit: query.paging.limit
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

    public func notes(titled title: String, location: BearNoteLocation) throws -> [BearNote] {
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
                AND n.ZTRASHED = 0
                AND n.ZARCHIVED = ?
                AND n.ZTITLE = ? COLLATE NOCASE
            GROUP BY n.Z_PK
            ORDER BY n.ZMODIFICATIONDATE DESC, n.ZUNIQUEIDENTIFIER DESC
            """,
            arguments: [archivedFlag(for: location), title]
        )
    }

    public func notes(matchingAnyTags query: TagNotesQuery) throws -> DiscoveryNoteBatch {
        let normalizedTags = query.tags.map(normalizedTag).filter { !$0.isEmpty }
        guard !normalizedTags.isEmpty else {
            return DiscoveryNoteBatch(notes: [], hasMore: false)
        }

        let placeholders = Array(repeating: "?", count: normalizedTags.count).joined(separator: ",")
        let pagination = paginationClause(for: query.paging.cursor)
        return try fetchDiscoveryBatch(
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
                AND EXISTS (
                    SELECT 1
                    FROM Z_5TAGS nt2
                    JOIN ZSFNOTETAG t2 ON t2.Z_PK = nt2.Z_13TAGS
                    WHERE nt2.Z_5NOTES = n.Z_PK
                        AND t2.ZTITLE IN (\(placeholders))
                )
                \(pagination.sql)
            GROUP BY n.Z_PK
            ORDER BY n.ZMODIFICATIONDATE DESC, n.ZUNIQUEIDENTIFIER DESC
            LIMIT ?
            """,
            arguments: [archivedFlag(for: query.location)] + normalizedTags + pagination.arguments + [query.paging.limit + 1],
            limit: query.paging.limit
        )
    }

    public func listTags(_ query: ListTagsQuery) throws -> [TagSummary] {
        var conditions = [
            "n.ZPERMANENTLYDELETED = 0",
            "n.ZTRASHED = 0",
            "n.ZARCHIVED = ?",
        ]
        var arguments: [DatabaseValueConvertible] = [archivedFlag(for: query.location)]

        if let nameQuery = query.query?.trimmingCharacters(in: .whitespacesAndNewlines), !nameQuery.isEmpty {
            conditions.append("LOWER(t.ZTITLE) LIKE ? ESCAPE '\\'")
            arguments.append(likePattern(for: nameQuery.lowercased()))
        }

        let normalizedUnderTag = BearTag.normalizedParentPath(query.underTag ?? "")
        if !normalizedUnderTag.isEmpty {
            conditions.append("LOWER(t.ZTITLE) LIKE ? ESCAPE '\\'")
            arguments.append(tagDescendantPattern(for: normalizedUnderTag.lowercased()))
        }

        return try databaseQueue.read { db in
            try TagRow.fetchAll(
                db,
                sql: """
                SELECT
                    t.ZTITLE AS title,
                    t.ZUNIQUEIDENTIFIER AS identifier,
                    COUNT(DISTINCT n.Z_PK) AS noteCount
                FROM ZSFNOTETAG t
                JOIN Z_5TAGS nt ON nt.Z_13TAGS = t.Z_PK
                JOIN ZSFNOTE n ON n.Z_PK = nt.Z_5NOTES
                WHERE \(conditions.joined(separator: "\n                    AND "))
                GROUP BY t.Z_PK
                ORDER BY LOWER(t.ZTITLE) ASC
                """,
                arguments: StatementArguments(arguments) ?? StatementArguments()
            )
            .map(\.summary)
        }
    }

    public func attachments(noteID: String) throws -> [NoteAttachment] {
        try databaseQueue.read { db in
            try AttachmentRow.fetchAll(
                db,
                sql: """
                SELECT
                    f.ZUNIQUEIDENTIFIER AS attachmentID,
                    f.ZFILENAME AS filename,
                    f.ZNORMALIZEDFILEEXTENSION AS fileExtension,
                    f.ZSEARCHTEXT AS searchText
                FROM ZSFNOTEFILE f
                JOIN ZSFNOTE n ON n.Z_PK = f.ZNOTE
                WHERE n.ZUNIQUEIDENTIFIER = ?
                    AND n.ZPERMANENTLYDELETED = 0
                    AND f.ZPERMANENTLYDELETED = 0
                ORDER BY f.ZINSERTIONDATE ASC, f.ZUNIQUEIDENTIFIER ASC
                """,
                arguments: [noteID]
            )
            .map(\.attachment)
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
            ORDER BY n.ZMODIFICATIONDATE DESC, n.ZUNIQUEIDENTIFIER DESC
            LIMIT ?
            """,
            arguments: arguments + [limit]
        )
    }

    private func paginationClause(for cursor: DiscoveryCursor?) -> (sql: String, arguments: [DatabaseValueConvertible]) {
        guard let cursor else {
            return ("", [])
        }

        let modifiedAt = cursor.lastModifiedAt.timeIntervalSinceReferenceDate
        return (
            """
            AND (
                n.ZMODIFICATIONDATE < ?
                OR (n.ZMODIFICATIONDATE = ? AND n.ZUNIQUEIDENTIFIER < ?)
            )
            """,
            [modifiedAt, modifiedAt, cursor.lastNoteID]
        )
    }

    private func likePattern(for query: String) -> String {
        "%\(query.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
    }

    private func tagDescendantPattern(for parentTag: String) -> String {
        "\(parentTag.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))/%"
    }

    private func normalizedTag(_ tag: String) -> String {
        BearTag.normalizedName(tag)
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

    private func fetchNotes(
        sql: String,
        arguments: [DatabaseValueConvertible],
        limit: Int
    ) throws -> [BearNote] {
        try fetchNotes(sql: sql + "\nLIMIT ?", arguments: arguments + [limit])
    }

    private func fetchDiscoveryBatch(
        sql: String,
        arguments: [DatabaseValueConvertible],
        limit: Int
    ) throws -> DiscoveryNoteBatch {
        let notes = try fetchNotes(sql: sql, arguments: arguments)
        let hasMore = notes.count > limit
        return DiscoveryNoteBatch(notes: Array(notes.prefix(limit)), hasMore: hasMore)
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

private struct AttachmentRow: FetchableRecord, Decodable {
    let attachmentID: String?
    let filename: String?
    let fileExtension: String?
    let searchText: String?

    var attachment: NoteAttachment {
        let trimmedSearchText = searchText?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return NoteAttachment(
            attachmentID: attachmentID ?? "",
            filename: filename ?? "",
            fileExtension: fileExtension,
            searchText: trimmedSearchText?.isEmpty == false ? trimmedSearchText : nil
        )
    }
}
