import BearCore
import Foundation
import GRDB

public final class BearDatabaseReader: @unchecked Sendable, BearReadStore {
    private let databaseQueue: DatabaseQueue
    private let activeScopeTags: [String]

    public init(databaseURL: URL, activeScopeTags: [String] = []) throws {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.label = "bear-mcp.db"
        self.databaseQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        self.activeScopeTags = activeScopeTags.map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public func searchNotes(_ query: NoteSearchQuery) throws -> [NoteSearchHit] {
        let scopeTags = query.scope == .active ? activeScopeTags : []
        let argumentValues: [DatabaseValueConvertible] = [
            query.includeArchived,
            query.includeTrashed,
            likePattern(for: query.query),
            likePattern(for: query.query),
        ] + scopeTags + [query.limit]

        let rows = try databaseQueue.read { db in
            try NoteRow.fetchAll(
                db,
                sql: """
                SELECT
                    n.Z_PK AS pk,
                    n.ZUNIQUEIDENTIFIER AS noteID,
                    n.ZTITLE AS title,
                    n.ZTEXT AS rawText,
                    n.ZVERSION AS version,
                    n.ZMODIFICATIONDATE AS modificationDate,
                    n.ZARCHIVED AS archived,
                    n.ZTRASHED AS trashed,
                    n.ZENCRYPTED AS encrypted,
                    COALESCE(GROUP_CONCAT(t.ZTITLE, '|'), '') AS tags
                FROM ZSFNOTE n
                LEFT JOIN Z_5TAGS nt ON nt.Z_5NOTES = n.Z_PK
                LEFT JOIN ZSFNOTETAG t ON t.Z_PK = nt.Z_13TAGS
                WHERE n.ZPERMANENTLYDELETED = 0
                    AND (? OR n.ZARCHIVED = 0)
                    AND (? OR n.ZTRASHED = 0)
                    AND (n.ZTITLE LIKE ? ESCAPE '\\' OR n.ZTEXT LIKE ? ESCAPE '\\')
                    \(scopeTagsClause(count: scopeTags.count))
                GROUP BY n.Z_PK
                ORDER BY n.ZMODIFICATIONDATE DESC
                LIMIT ?
                """,
                arguments: StatementArguments(argumentValues) ?? StatementArguments()
            )
        }

        return rows.map { $0.searchHit }
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

    public func notes(matchingTag tag: String) throws -> [BearNote] {
        try notes(
            matchingSQL: "EXISTS (SELECT 1 FROM Z_5TAGS nt2 JOIN ZSFNOTETAG t2 ON t2.Z_PK = nt2.Z_13TAGS WHERE nt2.Z_5NOTES = n.Z_PK AND t2.ZTITLE = ?)",
            arguments: [normalizedTag(tag)],
            limit: 250
        )
    }

    public func notes(inScope scope: BearScope, activeTags: [String]) throws -> [BearNote] {
        switch scope {
        case .all:
            return try notes(matchingSQL: "1 = 1", arguments: [], limit: 250)
        case .active:
            let tags = activeTags.map(normalizedTag)
            guard !tags.isEmpty else {
                throw BearError.configuration("The active scope is empty. Add tags to ~/.config/bear-mcp/config.json first.")
            }

            let placeholders = Array(repeating: "?", count: tags.count).joined(separator: ",")
            return try notes(
                matchingSQL: "EXISTS (SELECT 1 FROM Z_5TAGS nt2 JOIN ZSFNOTETAG t2 ON t2.Z_PK = nt2.Z_13TAGS WHERE nt2.Z_5NOTES = n.Z_PK AND t2.ZTITLE IN (\(placeholders)))",
                arguments: tags,
                limit: 250
            )
        }
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
        try databaseQueue.read { db in
            try NoteRow.fetchAll(
                db,
                sql: """
                SELECT
                    n.Z_PK AS pk,
                    n.ZUNIQUEIDENTIFIER AS noteID,
                    n.ZTITLE AS title,
                    n.ZTEXT AS rawText,
                    n.ZVERSION AS version,
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
                arguments: StatementArguments(arguments + [limit]) ?? StatementArguments()
            )
            .map(\.note)
        }
    }

    private func scopeTagsClause(count: Int) -> String {
        guard count > 0 else {
            return ""
        }

        let placeholders = Array(repeating: "?", count: count).joined(separator: ",")
        return """
        AND EXISTS (
            SELECT 1
            FROM Z_5TAGS nt2
            JOIN ZSFNOTETAG t2 ON t2.Z_PK = nt2.Z_13TAGS
            WHERE nt2.Z_5NOTES = n.Z_PK
                AND t2.ZTITLE IN (\(placeholders))
        )
        """
    }

    private func likePattern(for query: String) -> String {
        "%\(query.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
    }

    private func normalizedTag(_ tag: String) -> String {
        tag.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct NoteRow: FetchableRecord, Decodable {
    let noteID: String
    let title: String?
    let rawText: String?
    let version: Int?
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

    var searchHit: NoteSearchHit {
        let note = note
        let snippetSource = note.body.isEmpty ? note.rawText : note.body
        let snippet = String(snippetSource.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines)

        return NoteSearchHit(
            ref: note.ref,
            title: note.title,
            snippet: snippet,
            tags: note.tags,
            archived: note.archived,
            trashed: note.trashed,
            modifiedAt: note.revision.modifiedAt
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
