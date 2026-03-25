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
    modifiedAt: Double
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
            0,
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
