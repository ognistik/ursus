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

    public func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch {
        var conditions = [
            "n.ZPERMANENTLYDELETED = 0",
            "n.ZTRASHED = 0",
            "n.ZARCHIVED = ?",
        ]
        var arguments: [DatabaseValueConvertible] = [archivedFlag(for: query.location)]

        appendTextConditions(to: &conditions, arguments: &arguments, query: query)
        appendTagConditions(to: &conditions, arguments: &arguments, query: query)
        appendPresenceConditions(to: &conditions, query: query)
        appendDateConditions(to: &conditions, arguments: &arguments, query: query)

        let pagination = paginationClause(for: query.paging.cursor)
        let ranking = rankingCaseExpression(query: query, noteAlias: "f")
        let sql = """
            WITH filtered AS (
                SELECT
                    n.Z_PK AS pk,
                    n.ZUNIQUEIDENTIFIER AS noteID,
                    n.ZTITLE AS title,
                    n.ZTEXT AS rawText,
                    n.Z_OPT AS version,
                    n.ZCREATIONDATE AS creationDate,
                    n.ZMODIFICATIONDATE AS modificationDate,
                    n.ZARCHIVED AS archived,
                    n.ZTRASHED AS trashed,
                    n.ZENCRYPTED AS encrypted,
                    COALESCE(GROUP_CONCAT(t.ZTITLE, '|'), '') AS tags
                FROM ZSFNOTE n
                LEFT JOIN Z_5TAGS nt ON nt.Z_5NOTES = n.Z_PK
                LEFT JOIN ZSFNOTETAG t ON t.Z_PK = nt.Z_13TAGS
                WHERE \(conditions.joined(separator: "\n                    AND "))
                GROUP BY n.Z_PK
            ),
            ranked AS (
                SELECT
                    f.pk AS pk,
                    f.noteID AS noteID,
                    f.title AS title,
                    f.rawText AS rawText,
                    f.version AS version,
                    f.creationDate AS creationDate,
                    f.modificationDate AS modificationDate,
                    f.archived AS archived,
                    f.trashed AS trashed,
                    f.encrypted AS encrypted,
                    f.tags AS tags,
                    \(ranking.sql) AS relevanceBucket
                FROM filtered f
            )
            SELECT
                pk,
                noteID,
                title,
                rawText,
                version,
                creationDate,
                modificationDate,
                archived,
                trashed,
                encrypted,
                tags,
                relevanceBucket
            FROM ranked
            WHERE 1 = 1
                \(pagination.sql)
            ORDER BY relevanceBucket ASC, modificationDate DESC, noteID DESC
            LIMIT ?
            """

        return try fetchDiscoveryBatch(
            sql: sql,
            arguments: arguments + ranking.arguments + pagination.arguments + [query.paging.limit + 1],
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
                n.Z_OPT AS version,
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
                n.Z_OPT AS version,
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
                relevanceBucket > ?
                OR (
                    relevanceBucket = ?
                    AND (
                        modificationDate < ?
                        OR (modificationDate = ? AND noteID < ?)
                    )
                )
            )
            """,
            [cursor.relevanceBucket, cursor.relevanceBucket, modifiedAt, modifiedAt, cursor.lastNoteID]
        )
    }

    private func appendTextConditions(
        to conditions: inout [String],
        arguments: inout [DatabaseValueConvertible],
        query: FindNotesQuery
    ) {
        if let text = query.text {
            switch query.textMode {
            case .substring:
                let predicate = positiveTextPredicate(
                    mode: .substring,
                    terms: [text],
                    searchFields: query.searchFields
                )
                conditions.append(predicate.sql)
                arguments += predicate.arguments
            case .anyTerms:
                let predicate = positiveTextPredicate(
                    mode: .anyTerms,
                    terms: query.textTerms,
                    searchFields: query.searchFields
                )
                conditions.append(predicate.sql)
                arguments += predicate.arguments
            case .allTerms:
                let predicate = positiveTextPredicate(
                    mode: .allTerms,
                    terms: query.textTerms,
                    searchFields: query.searchFields
                )
                conditions.append(predicate.sql)
                arguments += predicate.arguments
            }
        }

        for excluded in query.textNot {
            let predicate = fieldMatchPredicate(term: excluded, searchFields: query.searchFields)
            conditions.append("NOT \(predicate.sql)")
            arguments += predicate.arguments
        }
    }

    private func appendTagConditions(
        to conditions: inout [String],
        arguments: inout [DatabaseValueConvertible],
        query: FindNotesQuery
    ) {
        if !query.tagsAny.isEmpty {
            let placeholders = placeholders(count: query.tagsAny.count)
            conditions.append("""
                EXISTS (
                    SELECT 1
                    FROM Z_5TAGS nt2
                    JOIN ZSFNOTETAG t2 ON t2.Z_PK = nt2.Z_13TAGS
                    WHERE nt2.Z_5NOTES = n.Z_PK
                        AND t2.ZTITLE IN (\(placeholders))
                )
                """)
            arguments += query.tagsAny
        }

        for tag in query.tagsAll {
            conditions.append("""
                EXISTS (
                    SELECT 1
                    FROM Z_5TAGS nt2
                    JOIN ZSFNOTETAG t2 ON t2.Z_PK = nt2.Z_13TAGS
                    WHERE nt2.Z_5NOTES = n.Z_PK
                        AND t2.ZTITLE = ?
                )
                """)
            arguments.append(tag)
        }

        if !query.tagsNone.isEmpty {
            let placeholders = placeholders(count: query.tagsNone.count)
            conditions.append("""
                NOT EXISTS (
                    SELECT 1
                    FROM Z_5TAGS nt2
                    JOIN ZSFNOTETAG t2 ON t2.Z_PK = nt2.Z_13TAGS
                    WHERE nt2.Z_5NOTES = n.Z_PK
                        AND t2.ZTITLE IN (\(placeholders))
                )
                """)
            arguments += query.tagsNone
        }
    }

    private func appendDateConditions(
        to conditions: inout [String],
        arguments: inout [DatabaseValueConvertible],
        query: FindNotesQuery
    ) {
        guard let field = query.dateField else {
            return
        }

        let column: String
        switch field {
        case .createdAt:
            column = "n.ZCREATIONDATE"
        case .modifiedAt:
            column = "n.ZMODIFICATIONDATE"
        }

        if let from = query.from {
            conditions.append("\(column) >= ?")
            arguments.append(from.timeIntervalSinceReferenceDate)
        }

        if let to = query.to {
            conditions.append("\(column) <= ?")
            arguments.append(to.timeIntervalSinceReferenceDate)
        }
    }

    private func appendPresenceConditions(
        to conditions: inout [String],
        query: FindNotesQuery
    ) {
        if let hasAttachments = query.hasAttachments {
            conditions.append(booleanPresencePredicate(
                hasAttachments,
                existsSQL: """
                    EXISTS (
                        SELECT 1
                        FROM ZSFNOTEFILE f
                        WHERE f.ZNOTE = n.Z_PK
                            AND f.ZPERMANENTLYDELETED = 0
                    )
                    """
            ))
        }

        if let hasAttachmentSearchText = query.hasAttachmentSearchText {
            conditions.append(booleanPresencePredicate(
                hasAttachmentSearchText,
                existsSQL: """
                    EXISTS (
                        SELECT 1
                        FROM ZSFNOTEFILE f
                        WHERE f.ZNOTE = n.Z_PK
                            AND f.ZPERMANENTLYDELETED = 0
                            AND TRIM(COALESCE(f.ZSEARCHTEXT, '')) <> ''
                    )
                    """
            ))
        }

        if let hasTags = query.hasTags {
            conditions.append(booleanPresencePredicate(
                hasTags,
                existsSQL: """
                    EXISTS (
                        SELECT 1
                        FROM Z_5TAGS nt2
                        JOIN ZSFNOTETAG t2 ON t2.Z_PK = nt2.Z_13TAGS
                        WHERE nt2.Z_5NOTES = n.Z_PK
                    )
                    """
            ))
        }
    }

    private func positiveTextPredicate(
        mode: FindTextMode,
        terms: [String],
        searchFields: [FindSearchField]
    ) -> SQLPredicate {
        switch mode {
        case .substring, .anyTerms:
            let parts = terms.map { fieldMatchPredicate(term: $0, searchFields: searchFields) }
            return combinePredicates(parts, joiner: "OR")
        case .allTerms:
            let parts = terms.map { fieldMatchPredicate(term: $0, searchFields: searchFields) }
            return combinePredicates(parts, joiner: "AND")
        }
    }

    private func fieldMatchPredicate(
        term: String,
        searchFields: [FindSearchField]
    ) -> SQLPredicate {
        let pattern = likePattern(for: term)
        var clauses: [String] = []
        var arguments: [DatabaseValueConvertible] = []

        for field in searchFields {
            switch field {
            case .title:
                clauses.append("n.ZTITLE LIKE ? ESCAPE '\\'")
                arguments.append(pattern)
            case .body:
                clauses.append("\(bodySearchExpression()) LIKE ? ESCAPE '\\'")
                arguments.append(pattern)
            case .attachments:
                clauses.append("""
                    EXISTS (
                        SELECT 1
                        FROM ZSFNOTEFILE f
                        WHERE f.ZNOTE = n.Z_PK
                            AND f.ZPERMANENTLYDELETED = 0
                            AND f.ZSEARCHTEXT LIKE ? ESCAPE '\\'
                    )
                    """)
                arguments.append(pattern)
            }
        }

        return SQLPredicate(
            sql: "(" + clauses.joined(separator: " OR ") + ")",
            arguments: arguments
        )
    }

    private func combinePredicates(_ predicates: [SQLPredicate], joiner: String) -> SQLPredicate {
        SQLPredicate(
            sql: "(" + predicates.map(\.sql).joined(separator: " \(joiner) ") + ")",
            arguments: predicates.flatMap(\.arguments)
        )
    }

    private func booleanPresencePredicate(_ value: Bool, existsSQL: String) -> String {
        value ? existsSQL : "NOT \(existsSQL)"
    }

    private func rankingCaseExpression(query: FindNotesQuery, noteAlias: String) -> SQLPredicate {
        guard let text = query.text else {
            return SQLPredicate(sql: "0", arguments: [])
        }

        let terms = query.textTerms.isEmpty ? [text] : query.textTerms
        var clauses: [(Int, SQLPredicate)] = []

        if query.searchFields.contains(.title) {
            clauses.append((1, likePredicate(expression: titleExpression(noteAlias: noteAlias), pattern: likePattern(for: text))))
            clauses.append((4, likePredicate(expression: titleExpression(noteAlias: noteAlias), pattern: likeOrderedPattern(for: terms))))
            clauses.append((7, allLikePredicate(expression: titleExpression(noteAlias: noteAlias), terms: terms)))
        }

        if query.searchFields.contains(.body) {
            let expression = bodySearchExpression(rawTextExpression: "\(noteAlias).rawText", titleExpression: "\(noteAlias).title")
            clauses.append((2, likePredicate(expression: expression, pattern: likePattern(for: text))))
            clauses.append((5, likePredicate(expression: expression, pattern: likeOrderedPattern(for: terms))))
            clauses.append((8, allLikePredicate(expression: expression, terms: terms)))
        }

        if query.searchFields.contains(.attachments) {
            clauses.append((3, attachmentLikePredicate(notePKExpression: "\(noteAlias).pk", pattern: likePattern(for: text))))
            clauses.append((6, attachmentLikePredicate(notePKExpression: "\(noteAlias).pk", pattern: likeOrderedPattern(for: terms))))
            clauses.append((9, attachmentAllLikePredicate(notePKExpression: "\(noteAlias).pk", terms: terms)))
        }

        guard !clauses.isEmpty else {
            return SQLPredicate(sql: "10", arguments: [])
        }

        let sql = """
        CASE
            \(clauses.map { "WHEN \($0.1.sql) THEN \($0.0)" }.joined(separator: "\n            "))
            ELSE 10
        END
        """

        return SQLPredicate(sql: sql, arguments: clauses.flatMap(\.1.arguments))
    }

    private func titleExpression(noteAlias: String) -> String {
        "COALESCE(\(noteAlias).title, '')"
    }

    private func bodySearchExpression() -> String {
        bodySearchExpression(rawTextExpression: "n.ZTEXT", titleExpression: "n.ZTITLE")
    }

    private func bodySearchExpression(rawTextExpression: String, titleExpression: String) -> String {
        """
        CASE
            WHEN \(rawTextExpression) = '# ' || COALESCE(\(titleExpression), '') THEN ''
            WHEN \(rawTextExpression) LIKE '# ' || COALESCE(\(titleExpression), '') || char(10) || '%' THEN SUBSTR(\(rawTextExpression), LENGTH('# ' || COALESCE(\(titleExpression), '')) + 3)
            ELSE \(rawTextExpression)
        END
        """
    }

    private func likePattern(for query: String) -> String {
        "%\(query.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
    }

    private func likeOrderedPattern(for terms: [String]) -> String {
        let escapedTerms = terms.map {
            $0.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        }
        return "%" + escapedTerms.joined(separator: "%") + "%"
    }

    private func likePredicate(expression: String, pattern: String) -> SQLPredicate {
        SQLPredicate(sql: "\(expression) LIKE ? ESCAPE '\\'", arguments: [pattern])
    }

    private func allLikePredicate(expression: String, terms: [String]) -> SQLPredicate {
        let patterns = terms.map(likePattern(for:))
        return SQLPredicate(
            sql: "(" + Array(repeating: "\(expression) LIKE ? ESCAPE '\\'", count: patterns.count).joined(separator: " AND ") + ")",
            arguments: patterns
        )
    }

    private func attachmentLikePredicate(notePKExpression: String, pattern: String) -> SQLPredicate {
        SQLPredicate(
            sql: """
            EXISTS (
                SELECT 1
                FROM ZSFNOTEFILE f
                WHERE f.ZNOTE = \(notePKExpression)
                    AND f.ZPERMANENTLYDELETED = 0
                    AND COALESCE(f.ZSEARCHTEXT, '') LIKE ? ESCAPE '\\'
            )
            """,
            arguments: [pattern]
        )
    }

    private func attachmentAllLikePredicate(notePKExpression: String, terms: [String]) -> SQLPredicate {
        let parts = terms.map { attachmentLikePredicate(notePKExpression: notePKExpression, pattern: likePattern(for: $0)) }
        return combinePredicates(parts, joiner: "AND")
    }

    private func tagDescendantPattern(for parentTag: String) -> String {
        "\(parentTag.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))/%"
    }

    private func normalizedTag(_ tag: String) -> String {
        BearTag.normalizedName(tag)
    }

    private func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
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
        let items = try databaseQueue.read { db in
            try NoteRow.fetchAll(
                db,
                sql: sql,
                arguments: StatementArguments(arguments) ?? StatementArguments()
            )
            .map(\.rankedNote)
        }
        let hasMore = items.count > limit
        return DiscoveryNoteBatch(items: Array(items.prefix(limit)), hasMore: hasMore)
    }
}

private struct SQLPredicate {
    let sql: String
    let arguments: [DatabaseValueConvertible]
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
    let relevanceBucket: Int?

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

    var rankedNote: DiscoveryRankedNote {
        DiscoveryRankedNote(note: note, relevanceBucket: relevanceBucket ?? 0)
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
