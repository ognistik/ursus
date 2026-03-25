import BearCore
import BearDB
import Foundation
import GRDB
import Testing

@Test
func databaseReaderMatchesTitlesCaseInsensitivelyWithinRequestedLocation() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "INBOX",
            rawText: "# INBOX\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 20
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "Inbox",
            rawText: "# Inbox\n\nArchived body",
            archived: 1,
            trashed: 0,
            modifiedAt: 30
        )
        try insertNote(
            db,
            pk: 3,
            noteID: "note-3",
            title: "Inbox",
            rawText: "# Inbox\n\nTrashed body",
            archived: 0,
            trashed: 1,
            modifiedAt: 40
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)

    let notes = try reader.notes(titled: "inbox", location: .notes)
    let archiveNotes = try reader.notes(titled: "INBOX", location: .archive)

    #expect(notes.map(\.ref.identifier) == ["note-1"])
    #expect(archiveNotes.map(\.ref.identifier) == ["note-2"])
}

@Test
func databaseReaderLoadsAttachmentsInInsertionOrderAndNormalizesEmptySearchText() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "Inbox",
            rawText: "# Inbox\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 20
        )
        try insertAttachment(
            db,
            pk: 11,
            attachmentID: "attachment-2",
            notePK: 1,
            filename: "second.pdf",
            fileExtension: "pdf",
            insertionDate: 20,
            searchText: "Second OCR"
        )
        try insertAttachment(
            db,
            pk: 10,
            attachmentID: "attachment-1",
            notePK: 1,
            filename: "first.pdf",
            fileExtension: "pdf",
            insertionDate: 10,
            searchText: "   "
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let attachments = try reader.attachments(noteID: "note-1")

    #expect(attachments.map(\.attachmentID) == ["attachment-1", "attachment-2"])
    #expect(attachments.first?.searchText == nil)
    #expect(attachments.last?.searchText == "Second OCR")
}

@Test
func databaseReaderListTagsFiltersByLocationQueryAndParentPath() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertTag(db, pk: 10, title: "projects", identifier: "tag-projects")
        try insertTag(db, pk: 11, title: "projects/workflows", identifier: "tag-workflows")
        try insertTag(db, pk: 12, title: "projects/workflows/client", identifier: "tag-client")
        try insertTag(db, pk: 13, title: "projects/ideas", identifier: "tag-ideas")
        try insertTag(db, pk: 14, title: "home", identifier: "tag-home")
        try insertTag(db, pk: 15, title: "trash-only", identifier: "tag-trash")

        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "Projects",
            rawText: "# Projects\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 20
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "Ideas",
            rawText: "# Ideas\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 30
        )
        try insertNote(
            db,
            pk: 3,
            noteID: "note-3",
            title: "Archived",
            rawText: "# Archived\n\nBody",
            archived: 1,
            trashed: 0,
            modifiedAt: 40
        )
        try insertNote(
            db,
            pk: 4,
            noteID: "note-4",
            title: "Trashed",
            rawText: "# Trashed\n\nBody",
            archived: 0,
            trashed: 1,
            modifiedAt: 50
        )
        try insertNote(
            db,
            pk: 5,
            noteID: "note-5",
            title: "Deleted",
            rawText: "# Deleted\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 60,
            permanentlyDeleted: 1
        )

        try attachTag(db, notePK: 1, tagPK: 10)
        try attachTag(db, notePK: 1, tagPK: 11)
        try attachTag(db, notePK: 2, tagPK: 11)
        try attachTag(db, notePK: 2, tagPK: 12)
        try attachTag(db, notePK: 2, tagPK: 13)
        try attachTag(db, notePK: 3, tagPK: 11)
        try attachTag(db, notePK: 3, tagPK: 14)
        try attachTag(db, notePK: 4, tagPK: 15)
        try attachTag(db, notePK: 5, tagPK: 12)
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)

    let defaultTags = try reader.listTags(ListTagsQuery())
    let archiveTags = try reader.listTags(ListTagsQuery(location: .archive))
    let filteredTags = try reader.listTags(
        ListTagsQuery(location: .notes, query: "WORK", underTag: "projects/")
    )

    #expect(defaultTags.map(\.name) == ["projects", "projects/ideas", "projects/workflows", "projects/workflows/client"])
    #expect(defaultTags.first(where: { $0.name == "projects/workflows" })?.noteCount == 2)
    #expect(defaultTags.first(where: { $0.name == "projects/workflows/client" })?.noteCount == 1)
    #expect(defaultTags.contains(where: { $0.name == "home" }) == false)
    #expect(defaultTags.contains(where: { $0.name == "trash-only" }) == false)

    #expect(archiveTags.map(\.name) == ["home", "projects/workflows"])
    #expect(archiveTags.first(where: { $0.name == "projects/workflows" })?.noteCount == 1)

    #expect(filteredTags.map(\.name) == ["projects/workflows", "projects/workflows/client"])
}

private func makeTemporaryBearDatabaseURL() throws -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("sqlite")
}

private func seedBearDatabase(
    at url: URL,
    seed: (Database) throws -> Void
) throws {
    let queue = try DatabaseQueue(path: url.path)
    try queue.write { db in
        try db.execute(sql: """
        CREATE TABLE ZSFNOTE (
            Z_PK INTEGER PRIMARY KEY,
            ZUNIQUEIDENTIFIER TEXT,
            ZTITLE TEXT,
            ZTEXT TEXT,
            ZVERSION INTEGER,
            ZCREATIONDATE DOUBLE,
            ZMODIFICATIONDATE DOUBLE,
            ZARCHIVED INTEGER,
            ZTRASHED INTEGER,
            ZENCRYPTED INTEGER,
            ZPERMANENTLYDELETED INTEGER
        );
        """)
        try db.execute(sql: """
        CREATE TABLE ZSFNOTETAG (
            Z_PK INTEGER PRIMARY KEY,
            ZTITLE TEXT,
            ZUNIQUEIDENTIFIER TEXT
        );
        """)
        try db.execute(sql: """
        CREATE TABLE Z_5TAGS (
            Z_5NOTES INTEGER,
            Z_13TAGS INTEGER
        );
        """)
        try db.execute(sql: """
        CREATE TABLE ZSFNOTEFILE (
            Z_PK INTEGER PRIMARY KEY,
            ZUNIQUEIDENTIFIER TEXT,
            ZNOTE INTEGER,
            ZFILENAME TEXT,
            ZNORMALIZEDFILEEXTENSION TEXT,
            ZSEARCHTEXT TEXT,
            ZINSERTIONDATE DOUBLE,
            ZPERMANENTLYDELETED INTEGER
        );
        """)

        try seed(db)
    }
}

private func insertNote(
    _ db: Database,
    pk: Int,
    noteID: String,
    title: String,
    rawText: String,
    archived: Int,
    trashed: Int,
    modifiedAt: Double,
    permanentlyDeleted: Int = 0
) throws {
    try db.execute(
        sql: """
        INSERT INTO ZSFNOTE (
            Z_PK,
            ZUNIQUEIDENTIFIER,
            ZTITLE,
            ZTEXT,
            ZVERSION,
            ZCREATIONDATE,
            ZMODIFICATIONDATE,
            ZARCHIVED,
            ZTRASHED,
            ZENCRYPTED,
            ZPERMANENTLYDELETED
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        arguments: [
            pk,
            noteID,
            title,
            rawText,
            3,
            modifiedAt - 10,
            modifiedAt,
            archived,
            trashed,
            0,
            permanentlyDeleted,
        ]
    )
}

private func insertTag(
    _ db: Database,
    pk: Int,
    title: String,
    identifier: String
) throws {
    try db.execute(
        sql: """
        INSERT INTO ZSFNOTETAG (
            Z_PK,
            ZTITLE,
            ZUNIQUEIDENTIFIER
        ) VALUES (?, ?, ?)
        """,
        arguments: [
            pk,
            title,
            identifier,
        ]
    )
}

private func attachTag(
    _ db: Database,
    notePK: Int,
    tagPK: Int
) throws {
    try db.execute(
        sql: """
        INSERT INTO Z_5TAGS (
            Z_5NOTES,
            Z_13TAGS
        ) VALUES (?, ?)
        """,
        arguments: [
            notePK,
            tagPK,
        ]
    )
}

private func insertAttachment(
    _ db: Database,
    pk: Int,
    attachmentID: String,
    notePK: Int,
    filename: String,
    fileExtension: String,
    insertionDate: Double,
    searchText: String
) throws {
    try db.execute(
        sql: """
        INSERT INTO ZSFNOTEFILE (
            Z_PK,
            ZUNIQUEIDENTIFIER,
            ZNOTE,
            ZFILENAME,
            ZNORMALIZEDFILEEXTENSION,
            ZSEARCHTEXT,
            ZINSERTIONDATE,
            ZPERMANENTLYDELETED
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        arguments: [
            pk,
            attachmentID,
            notePK,
            filename,
            fileExtension,
            searchText,
            insertionDate,
            0,
        ]
    )
}
