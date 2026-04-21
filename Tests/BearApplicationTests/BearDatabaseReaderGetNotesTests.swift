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
func databaseReaderUsesZOPTForNoteVersion() throws {
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
            modifiedAt: 20,
            zOpt: 42
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let note = try #require(try reader.note(id: "note-1"))

    #expect(note.revision.version == 42)
}

@Test
func databaseReaderParsesFrontmatterAndExplicitTitleFromRawText() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertNote(
            db,
            pk: 1,
            noteID: "note-frontmatter",
            title: "Test Note",
            rawText: """
            ---
            key1: This is a test
            # Actually, I am just including some random text here.
            ---
            # Test Note
            this is the body
            """,
            archived: 0,
            trashed: 0,
            modifiedAt: 20
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let note = try #require(try reader.note(id: "note-frontmatter"))

    #expect(note.title == "Test Note")
    #expect(note.hasExplicitTitle == true)
    #expect(note.frontmatter?.content == "key1: This is a test\n# Actually, I am just including some random text here.")
    #expect(note.body == "this is the body")
}

@Test
func databaseReaderRetriesTransientExclusiveLockAndEventuallySucceeds() throws {
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
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let lock = try ExclusiveDatabaseLock(databaseURL: databaseURL)
    try lock.acquire()
    defer { lock.releaseAndWait() }

    lock.release(after: 0.2)

    let note = try #require(try reader.note(id: "note-1"))

    #expect(note.ref.identifier == "note-1")
}

@Test
func databaseReaderThrowsWhenExclusiveLockOutlivesRetryWindow() throws {
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
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let lock = try ExclusiveDatabaseLock(databaseURL: databaseURL)
    try lock.acquire()
    defer { lock.releaseAndWait() }

    #expect(throws: DatabaseError.self) {
        _ = try reader.note(id: "note-1")
    }
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

@Test
func databaseReaderFindNotesMatchesBodyAndAttachmentText() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "Inbox",
            rawText: "# Inbox\n\nBody mentions superwhisper",
            archived: 0,
            trashed: 0,
            modifiedAt: 20
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "Attachment note",
            rawText: "# Attachment note\n\nNo body match here",
            archived: 0,
            trashed: 0,
            modifiedAt: 30
        )
        try insertAttachment(
            db,
            pk: 10,
            attachmentID: "attachment-1",
            notePK: 2,
            filename: "ocr.pdf",
            fileExtension: "pdf",
            insertionDate: 10,
            searchText: "Attachment mentions superwhisper too"
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let query = FindNotesQuery(
        text: "superwhisper",
        textMode: .substring,
        textTerms: ["superwhisper"],
        textNot: [],
        searchFields: [.title, .body, .attachments],
        tagsAny: [],
        tagsAll: [],
        tagsNone: [],
        location: .notes,
        paging: DiscoveryPaging(limit: 10)
    )

    let batch = try reader.findNotes(query)

    #expect(batch.notes.map(\.ref.identifier) == ["note-1", "note-2"])
    #expect(batch.items.map(\.relevanceBucket) == [2, 3])
}

@Test
func databaseReaderFindNotesKeepsFilterOnlyDiscoveryInRecencyOrder() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertTag(db, pk: 10, title: "project", identifier: "tag-project")
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "Older",
            rawText: "# Older\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 10
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "Newest",
            rawText: "# Newest\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 30
        )
        try insertTag(db, pk: 11, title: "notes", identifier: "tag-notes")
        try attachTag(db, notePK: 1, tagPK: 10)
        try attachTag(db, notePK: 2, tagPK: 10)
        try attachTag(db, notePK: 2, tagPK: 11)
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let batch = try reader.findNotes(
        FindNotesQuery(
            text: nil,
            textMode: .substring,
            textTerms: [],
            textNot: [],
            searchFields: [.title, .body, .attachments],
            tagsAny: ["project"],
            tagsAll: [],
            tagsNone: [],
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )

    #expect(batch.notes.map(\.ref.identifier) == ["note-2", "note-1"])
    #expect(batch.items.map(\.relevanceBucket) == [0, 0])
}

@Test
func databaseReaderFindNotesRanksTitlePhraseBeforeNewerBodyPhrase() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "Searching these words",
            rawText: "# Searching these words\n\nOlder body",
            archived: 0,
            trashed: 0,
            modifiedAt: 10
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "Fresh note",
            rawText: "# Fresh note\n\nBody mentions searching these words here",
            archived: 0,
            trashed: 0,
            modifiedAt: 30
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let batch = try reader.findNotes(
        FindNotesQuery(
            text: "searching these words",
            textMode: .substring,
            textTerms: ["searching these words"],
            textNot: [],
            searchFields: [.title, .body],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )

    #expect(batch.notes.map(\.ref.identifier) == ["note-1", "note-2"])
    #expect(batch.items.map(\.relevanceBucket) == [1, 2])
}

@Test
func databaseReaderFindNotesRanksBodyPhraseBeforeOrderedTitleMatch() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "Body phrase",
            rawText: "# Body phrase\n\nBody includes searching these words in order",
            archived: 0,
            trashed: 0,
            modifiedAt: 10
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "searching alpha these beta words",
            rawText: "# searching alpha these beta words\n\nNewer body",
            archived: 0,
            trashed: 0,
            modifiedAt: 40
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let batch = try reader.findNotes(
        FindNotesQuery(
            text: "searching these words",
            textMode: .anyTerms,
            textTerms: ["searching", "these", "words"],
            textNot: [],
            searchFields: [.title, .body],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )

    #expect(batch.notes.map(\.ref.identifier) == ["note-1", "note-2"])
    #expect(batch.items.map(\.relevanceBucket) == [2, 4])
}

@Test
func databaseReaderFindNotesRanksOrderedTitleBeforeUnorderedTitleMatch() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "searching alpha these beta words",
            rawText: "# searching alpha these beta words\n\nOlder body",
            archived: 0,
            trashed: 0,
            modifiedAt: 10
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "words these searching",
            rawText: "# words these searching\n\nNewer body",
            archived: 0,
            trashed: 0,
            modifiedAt: 50
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let batch = try reader.findNotes(
        FindNotesQuery(
            text: "searching these words",
            textMode: .allTerms,
            textTerms: ["searching", "these", "words"],
            textNot: [],
            searchFields: [.title],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )

    #expect(batch.notes.map(\.ref.identifier) == ["note-1", "note-2"])
    #expect(batch.items.map(\.relevanceBucket) == [4, 7])
}

@Test
func databaseReaderFindNotesSearchFieldsPreventTitleRankingBoosts() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "searching these words",
            rawText: "# searching these words\n\nBody says words then searching then these",
            archived: 0,
            trashed: 0,
            modifiedAt: 30
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "Body match",
            rawText: "# Body match\n\nBody says searching these words exactly",
            archived: 0,
            trashed: 0,
            modifiedAt: 10
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let batch = try reader.findNotes(
        FindNotesQuery(
            text: "searching these words",
            textMode: .allTerms,
            textTerms: ["searching", "these", "words"],
            textNot: [],
            searchFields: [.body],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )

    #expect(batch.notes.map(\.ref.identifier) == ["note-2", "note-1"])
    #expect(batch.items.map(\.relevanceBucket) == [2, 8])
}

@Test
func databaseReaderBodySearchIncludesFrontmatterButExcludesTitleAfterFrontmatter() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertNote(
            db,
            pk: 1,
            noteID: "note-frontmatter",
            title: "Test Note",
            rawText: """
            ---
            key1: This is a test
            ---
            # Test Note
            body stays ordinary
            """,
            archived: 0,
            trashed: 0,
            modifiedAt: 30
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)

    let frontmatterBatch = try reader.findNotes(
        FindNotesQuery(
            text: "This is a test",
            textMode: .substring,
            textTerms: ["This is a test"],
            textNot: [],
            searchFields: [.body],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )
    let titleOnlyBatch = try reader.findNotes(
        FindNotesQuery(
            text: "Test Note",
            textMode: .substring,
            textTerms: ["Test Note"],
            textNot: [],
            searchFields: [.body],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )

    #expect(frontmatterBatch.notes.map(\.ref.identifier) == ["note-frontmatter"])
    #expect(titleOnlyBatch.notes.isEmpty)
}

@Test
func databaseReaderFindNotesPaginatesAcrossRankingBuckets() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "searching these words",
            rawText: "# searching these words\n\nOldest",
            archived: 0,
            trashed: 0,
            modifiedAt: 10
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "Body phrase",
            rawText: "# Body phrase\n\nsearching these words in body",
            archived: 0,
            trashed: 0,
            modifiedAt: 40
        )
        try insertNote(
            db,
            pk: 3,
            noteID: "note-3",
            title: "searching alpha these beta words",
            rawText: "# searching alpha these beta words\n\nMiddle",
            archived: 0,
            trashed: 0,
            modifiedAt: 20
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let query = FindNotesQuery(
        text: "searching these words",
        textMode: .anyTerms,
        textTerms: ["searching", "these", "words"],
        textNot: [],
        searchFields: [.title, .body],
        tagsAny: [],
        tagsAll: [],
        tagsNone: [],
        location: .notes,
        paging: DiscoveryPaging(limit: 2)
    )

    let firstBatch = try reader.findNotes(query)

    #expect(firstBatch.notes.map(\.ref.identifier) == ["note-1", "note-2"])
    #expect(firstBatch.items.map(\.relevanceBucket) == [1, 2])
    #expect(firstBatch.hasMore == true)

    let cursor = DiscoveryCursor(
        kind: .findNotes,
        location: .notes,
        filterKey: "pagination-test",
        relevanceBucket: try #require(firstBatch.items.last?.relevanceBucket),
        lastModifiedAt: try #require(firstBatch.items.last?.note.revision.modifiedAt),
        lastNoteID: try #require(firstBatch.items.last?.note.ref.identifier)
    )
    let secondBatch = try reader.findNotes(
        FindNotesQuery(
            text: "searching these words",
            textMode: .anyTerms,
            textTerms: ["searching", "these", "words"],
            textNot: [],
            searchFields: [.title, .body],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            location: .notes,
            paging: DiscoveryPaging(limit: 2, cursor: cursor)
        )
    )

    #expect(secondBatch.notes.map(\.ref.identifier) == ["note-3"])
    #expect(secondBatch.items.map(\.relevanceBucket) == [4])
    #expect(secondBatch.hasMore == false)
}

@Test
func databaseReaderFindNotesRespectsDateAndTagFilters() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertTag(db, pk: 10, title: "0-inbox", identifier: "tag-inbox")
        try insertTag(db, pk: 11, title: "project", identifier: "tag-project")
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "Recent",
            rawText: "# Recent\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 20
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "Older",
            rawText: "# Older\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 5
        )
        try attachTag(db, notePK: 1, tagPK: 10)
        try attachTag(db, notePK: 1, tagPK: 11)
        try attachTag(db, notePK: 2, tagPK: 10)
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)
    let query = FindNotesQuery(
        text: nil,
        textMode: .substring,
        textTerms: [],
        textNot: [],
        searchFields: [.title, .body, .attachments],
        tagsAny: ["0-inbox"],
        tagsAll: ["project"],
        tagsNone: [],
        location: .notes,
        dateField: .modifiedAt,
        from: Date(timeIntervalSinceReferenceDate: 10),
        to: nil,
        paging: DiscoveryPaging(limit: 10)
    )

    let batch = try reader.findNotes(query)

    #expect(batch.notes.map(\.ref.identifier) == ["note-1"])
}

@Test
func databaseReaderFindNotesSupportsPresenceFilters() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertTag(db, pk: 10, title: "project", identifier: "tag-project")
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "Plain",
            rawText: "# Plain\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 10
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "Attached",
            rawText: "# Attached\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 20
        )
        try insertNote(
            db,
            pk: 3,
            noteID: "note-3",
            title: "Tagged attachment",
            rawText: "# Tagged attachment\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 30
        )
        try attachTag(db, notePK: 3, tagPK: 10)
        try insertAttachment(
            db,
            pk: 10,
            attachmentID: "attachment-1",
            notePK: 2,
            filename: "scan.png",
            fileExtension: "png",
            insertionDate: 10,
            searchText: ""
        )
        try insertAttachment(
            db,
            pk: 11,
            attachmentID: "attachment-2",
            notePK: 3,
            filename: "scan.pdf",
            fileExtension: "pdf",
            insertionDate: 20,
            searchText: "Indexed attachment text"
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)

    let attachmentsBatch = try reader.findNotes(
        FindNotesQuery(
            text: nil,
            textMode: .substring,
            textTerms: [],
            textNot: [],
            searchFields: [.title, .body, .attachments],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            hasAttachments: true,
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )
    let noTagsBatch = try reader.findNotes(
        FindNotesQuery(
            text: nil,
            textMode: .substring,
            textTerms: [],
            textNot: [],
            searchFields: [.title, .body, .attachments],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            hasTags: false,
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )
    #expect(attachmentsBatch.notes.map(\.ref.identifier) == ["note-3", "note-2"])
    #expect(noTagsBatch.notes.map(\.ref.identifier) == ["note-2", "note-1"])
}

@Test
func databaseReaderFindNotesSupportsPinnedAndOpenTodoFilters() throws {
    let databaseURL = try makeTemporaryBearDatabaseURL()
    try seedBearDatabase(at: databaseURL) { db in
        try insertNote(
            db,
            pk: 1,
            noteID: "note-1",
            title: "Plain",
            rawText: "# Plain\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 10
        )
        try insertNote(
            db,
            pk: 2,
            noteID: "note-2",
            title: "Pinned",
            rawText: "# Pinned\n\nBody",
            archived: 0,
            trashed: 0,
            modifiedAt: 20,
            pinned: 1
        )
        try insertNote(
            db,
            pk: 3,
            noteID: "note-3",
            title: "Completed Todos",
            rawText: "# Completed Todos\n\n- [x] Done",
            archived: 0,
            trashed: 0,
            modifiedAt: 30,
            todoCompleted: 1
        )
        try insertNote(
            db,
            pk: 4,
            noteID: "note-4",
            title: "Open Todos",
            rawText: "# Open Todos\n\n- [ ] Next",
            archived: 0,
            trashed: 0,
            modifiedAt: 40,
            todoIncomplete: 1
        )
        try insertNote(
            db,
            pk: 5,
            noteID: "note-5",
            title: "Pinned Open Todos",
            rawText: "# Pinned Open Todos\n\n- [x] Done\n- [ ] Next",
            archived: 0,
            trashed: 0,
            modifiedAt: 50,
            pinned: 1,
            todoCompleted: 1,
            todoIncomplete: 1
        )
    }

    let reader = try BearDatabaseReader(databaseURL: databaseURL)

    let pinnedBatch = try reader.findNotes(
        FindNotesQuery(
            text: nil,
            textMode: .substring,
            textTerms: [],
            textNot: [],
            searchFields: [.title, .body, .attachments],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            hasPinned: true,
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )
    let openTodosBatch = try reader.findNotes(
        FindNotesQuery(
            text: nil,
            textMode: .substring,
            textTerms: [],
            textNot: [],
            searchFields: [.title, .body, .attachments],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            hasTodos: true,
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )
    let unpinnedOpenTodosBatch = try reader.findNotes(
        FindNotesQuery(
            text: nil,
            textMode: .substring,
            textTerms: [],
            textNot: [],
            searchFields: [.title, .body, .attachments],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            hasPinned: false,
            hasTodos: true,
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )
    let noOpenTodosBatch = try reader.findNotes(
        FindNotesQuery(
            text: nil,
            textMode: .substring,
            textTerms: [],
            textNot: [],
            searchFields: [.title, .body, .attachments],
            tagsAny: [],
            tagsAll: [],
            tagsNone: [],
            hasTodos: false,
            location: .notes,
            paging: DiscoveryPaging(limit: 10)
        )
    )

    #expect(pinnedBatch.notes.map(\.ref.identifier) == ["note-5", "note-2"])
    #expect(openTodosBatch.notes.map(\.ref.identifier) == ["note-5", "note-4"])
    #expect(unpinnedOpenTodosBatch.notes.map(\.ref.identifier) == ["note-4"])
    #expect(noOpenTodosBatch.notes.map(\.ref.identifier) == ["note-3", "note-2", "note-1"])
}

private func makeTemporaryBearDatabaseURL() throws -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("sqlite")
}

private final class ExclusiveDatabaseLock: @unchecked Sendable {
    private let queue: DatabaseQueue
    private let acquired = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let stateLock = NSLock()
    private let errorLock = NSLock()
    private var isReleased = false
    private var acquisitionError: Error?

    init(databaseURL: URL) throws {
        self.queue = try DatabaseQueue(path: databaseURL.path)
    }

    func acquire() throws {
        DispatchQueue.global().async {
            defer { self.finished.signal() }

            do {
                try self.queue.writeWithoutTransaction { db in
                    try db.execute(sql: "BEGIN EXCLUSIVE TRANSACTION")
                    self.acquired.signal()
                    self.releaseSignal.wait()
                    try db.execute(sql: "COMMIT TRANSACTION")
                }
            } catch {
                self.errorLock.lock()
                self.acquisitionError = error
                self.errorLock.unlock()
                self.acquired.signal()
            }
        }

        acquired.wait()
        errorLock.lock()
        let acquisitionError = self.acquisitionError
        errorLock.unlock()
        if let acquisitionError {
            throw acquisitionError
        }
    }

    func release(after delay: TimeInterval) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            self.release()
        }
    }

    func releaseAndWait() {
        release()
        finished.wait()
    }

    private func release() {
        stateLock.lock()
        let shouldSignal = !isReleased
        isReleased = true
        stateLock.unlock()

        if shouldSignal {
            releaseSignal.signal()
        }
    }
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
            Z_OPT INTEGER,
            ZUNIQUEIDENTIFIER TEXT,
            ZTITLE TEXT,
            ZTEXT TEXT,
            ZVERSION INTEGER,
            ZCREATIONDATE DOUBLE,
            ZMODIFICATIONDATE DOUBLE,
            ZARCHIVED INTEGER,
            ZPINNED INTEGER,
            ZTODOCOMPLETED INTEGER,
            ZTODOINCOMPLETED INTEGER,
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
    permanentlyDeleted: Int = 0,
    zOpt: Int = 3,
    pinned: Int = 0,
    todoCompleted: Int = 0,
    todoIncomplete: Int = 0
) throws {
    try db.execute(
        sql: """
        INSERT INTO ZSFNOTE (
            Z_PK,
            Z_OPT,
            ZUNIQUEIDENTIFIER,
            ZTITLE,
            ZTEXT,
            ZVERSION,
            ZCREATIONDATE,
            ZMODIFICATIONDATE,
            ZARCHIVED,
            ZPINNED,
            ZTODOCOMPLETED,
            ZTODOINCOMPLETED,
            ZTRASHED,
            ZENCRYPTED,
            ZPERMANENTLYDELETED
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        arguments: [
            pk,
            zOpt,
            noteID,
            title,
            rawText,
            3,
            modifiedAt - 10,
            modifiedAt,
            archived,
            pinned,
            todoCompleted,
            todoIncomplete,
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
