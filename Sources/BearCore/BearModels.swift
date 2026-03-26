import Foundation

public struct NoteRef: Codable, Hashable, Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }
}

public struct NoteRevision: Codable, Hashable, Sendable {
    public let version: Int
    public let createdAt: Date
    public let modifiedAt: Date

    public init(version: Int, createdAt: Date, modifiedAt: Date) {
        self.version = version
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct BearNote: Codable, Hashable, Sendable {
    public let ref: NoteRef
    public let revision: NoteRevision
    public let title: String
    public let body: String
    public let rawText: String
    public let tags: [String]
    public let archived: Bool
    public let trashed: Bool
    public let encrypted: Bool

    public init(
        ref: NoteRef,
        revision: NoteRevision,
        title: String,
        body: String,
        rawText: String,
        tags: [String],
        archived: Bool,
        trashed: Bool,
        encrypted: Bool
    ) {
        self.ref = ref
        self.revision = revision
        self.title = title
        self.body = body
        self.rawText = rawText
        self.tags = tags
        self.archived = archived
        self.trashed = trashed
        self.encrypted = encrypted
    }
}

public struct NoteAttachment: Codable, Hashable, Sendable {
    public let attachmentID: String
    public let filename: String
    public let fileExtension: String?
    public let searchText: String?

    public init(
        attachmentID: String,
        filename: String,
        fileExtension: String?,
        searchText: String?
    ) {
        self.attachmentID = attachmentID
        self.filename = filename
        self.fileExtension = fileExtension
        self.searchText = searchText
    }

    enum CodingKeys: String, CodingKey {
        case attachmentID
        case filename
        case fileExtension = "extension"
        case searchText
    }
}

public struct BearFetchedNote: Codable, Hashable, Sendable {
    public let noteID: String
    public let title: String
    public let content: String
    public let tags: [String]
    public let createdAt: Date
    public let modifiedAt: Date
    public let version: Int
    public let attachments: [NoteAttachment]
    public let encrypted: Bool?

    public init(
        noteID: String,
        title: String,
        content: String,
        tags: [String],
        createdAt: Date,
        modifiedAt: Date,
        version: Int,
        attachments: [NoteAttachment],
        encrypted: Bool? = nil
    ) {
        self.noteID = noteID
        self.title = title
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.version = version
        self.attachments = attachments
        self.encrypted = encrypted
    }
}

public enum FindTextMode: String, Codable, Hashable, Sendable {
    case substring
    case anyTerms = "any_terms"
    case allTerms = "all_terms"
}

public enum FindSearchField: String, Codable, Hashable, Sendable {
    case title
    case body
    case attachments
}

public enum FindTagMatchMode: String, Codable, Hashable, Sendable {
    case any
    case all
}

public enum FindDateField: String, Codable, Hashable, Sendable {
    case createdAt = "created_at"
    case modifiedAt = "modified_at"
}

public struct FindNotesOperation: Codable, Hashable, Sendable {
    public let id: String?
    public let text: String?
    public let textMode: FindTextMode
    public let textNot: [String]
    public let searchFields: [FindSearchField]
    public let tagsAny: [String]
    public let tagsAll: [String]
    public let tagsNone: [String]
    public let hasAttachments: Bool?
    public let hasAttachmentSearchText: Bool?
    public let hasTags: Bool?
    public let activeTagsMode: FindTagMatchMode?
    public let dateField: FindDateField?
    public let from: String?
    public let to: String?
    public let location: BearNoteLocation
    public let limit: Int?
    public let snippetLength: Int?
    public let cursor: String?

    public init(
        id: String? = nil,
        text: String? = nil,
        textMode: FindTextMode = .substring,
        textNot: [String] = [],
        searchFields: [FindSearchField] = [],
        tagsAny: [String] = [],
        tagsAll: [String] = [],
        tagsNone: [String] = [],
        hasAttachments: Bool? = nil,
        hasAttachmentSearchText: Bool? = nil,
        hasTags: Bool? = nil,
        activeTagsMode: FindTagMatchMode? = nil,
        dateField: FindDateField? = nil,
        from: String? = nil,
        to: String? = nil,
        location: BearNoteLocation = .notes,
        limit: Int? = nil,
        snippetLength: Int? = nil,
        cursor: String? = nil
    ) {
        self.id = id
        self.text = text
        self.textMode = textMode
        self.textNot = textNot
        self.searchFields = searchFields
        self.tagsAny = tagsAny
        self.tagsAll = tagsAll
        self.tagsNone = tagsNone
        self.hasAttachments = hasAttachments
        self.hasAttachmentSearchText = hasAttachmentSearchText
        self.hasTags = hasTags
        self.activeTagsMode = activeTagsMode
        self.dateField = dateField
        self.from = from
        self.to = to
        self.location = location
        self.limit = limit
        self.snippetLength = snippetLength
        self.cursor = cursor
    }
}

public struct FindNotesQuery: Codable, Hashable, Sendable {
    public let text: String?
    public let textMode: FindTextMode
    public let textTerms: [String]
    public let textNot: [String]
    public let searchFields: [FindSearchField]
    public let tagsAny: [String]
    public let tagsAll: [String]
    public let tagsNone: [String]
    public let hasAttachments: Bool?
    public let hasAttachmentSearchText: Bool?
    public let hasTags: Bool?
    public let location: BearNoteLocation
    public let dateField: FindDateField?
    public let from: Date?
    public let to: Date?
    public let paging: DiscoveryPaging

    public init(
        text: String?,
        textMode: FindTextMode,
        textTerms: [String],
        textNot: [String],
        searchFields: [FindSearchField],
        tagsAny: [String],
        tagsAll: [String],
        tagsNone: [String],
        hasAttachments: Bool? = nil,
        hasAttachmentSearchText: Bool? = nil,
        hasTags: Bool? = nil,
        location: BearNoteLocation = .notes,
        dateField: FindDateField? = nil,
        from: Date? = nil,
        to: Date? = nil,
        paging: DiscoveryPaging = DiscoveryPaging(limit: 20)
    ) {
        self.text = text
        self.textMode = textMode
        self.textTerms = textTerms
        self.textNot = textNot
        self.searchFields = searchFields
        self.tagsAny = tagsAny
        self.tagsAll = tagsAll
        self.tagsNone = tagsNone
        self.hasAttachments = hasAttachments
        self.hasAttachmentSearchText = hasAttachmentSearchText
        self.hasTags = hasTags
        self.location = location
        self.dateField = dateField
        self.from = from
        self.to = to
        self.paging = paging
    }
}

public struct FindNotesByTagOperation: Codable, Hashable, Sendable {
    public let id: String?
    public let tags: [String]
    public let tagMatch: FindTagMatchMode
    public let location: BearNoteLocation
    public let limit: Int?
    public let snippetLength: Int?
    public let cursor: String?

    public init(
        id: String? = nil,
        tags: [String],
        tagMatch: FindTagMatchMode = .any,
        location: BearNoteLocation = .notes,
        limit: Int? = nil,
        snippetLength: Int? = nil,
        cursor: String? = nil
    ) {
        self.id = id
        self.tags = tags
        self.tagMatch = tagMatch
        self.location = location
        self.limit = limit
        self.snippetLength = snippetLength
        self.cursor = cursor
    }
}

public struct FindNotesByActiveTagsOperation: Codable, Hashable, Sendable {
    public let id: String?
    public let match: FindTagMatchMode
    public let location: BearNoteLocation
    public let limit: Int?
    public let snippetLength: Int?
    public let cursor: String?

    public init(
        id: String? = nil,
        match: FindTagMatchMode = .any,
        location: BearNoteLocation = .notes,
        limit: Int? = nil,
        snippetLength: Int? = nil,
        cursor: String? = nil
    ) {
        self.id = id
        self.match = match
        self.location = location
        self.limit = limit
        self.snippetLength = snippetLength
        self.cursor = cursor
    }
}

public struct ListTagsQuery: Codable, Hashable, Sendable {
    public let location: BearNoteLocation
    public let query: String?
    public let underTag: String?

    public init(
        location: BearNoteLocation = .notes,
        query: String? = nil,
        underTag: String? = nil
    ) {
        self.location = location
        self.query = query
        self.underTag = underTag
    }
}

public struct DiscoveryPaging: Codable, Hashable, Sendable {
    public let limit: Int
    public let cursor: DiscoveryCursor?

    public init(limit: Int, cursor: DiscoveryCursor? = nil) {
        self.limit = limit
        self.cursor = cursor
    }
}

public enum DiscoveryKind: String, Codable, Hashable, Sendable {
    case findNotes = "find_notes"
    case searchNotes = "search_notes"
    case notesByTag = "notes_by_tag"
    case notesByActiveTags = "notes_by_active_tags"
}

public struct DiscoveryCursor: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    private enum CodingKeys: String, CodingKey {
        case version
        case kind
        case location
        case filterKey
        case relevanceBucket
        case lastModifiedAt
        case lastNoteID
    }

    public let version: Int
    public let kind: DiscoveryKind
    public let location: BearNoteLocation
    public let filterKey: String
    public let relevanceBucket: Int
    public let lastModifiedAt: Date
    public let lastNoteID: String

    public init(
        version: Int = DiscoveryCursor.currentVersion,
        kind: DiscoveryKind,
        location: BearNoteLocation,
        filterKey: String,
        relevanceBucket: Int = 0,
        lastModifiedAt: Date,
        lastNoteID: String
    ) {
        self.version = version
        self.kind = kind
        self.location = location
        self.filterKey = filterKey
        self.relevanceBucket = relevanceBucket
        self.lastModifiedAt = lastModifiedAt
        self.lastNoteID = lastNoteID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.kind = try container.decode(DiscoveryKind.self, forKey: .kind)
        self.location = try container.decode(BearNoteLocation.self, forKey: .location)
        self.filterKey = try container.decode(String.self, forKey: .filterKey)
        self.relevanceBucket = try container.decodeIfPresent(Int.self, forKey: .relevanceBucket) ?? 0
        self.lastModifiedAt = try container.decode(Date.self, forKey: .lastModifiedAt)
        self.lastNoteID = try container.decode(String.self, forKey: .lastNoteID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(kind, forKey: .kind)
        try container.encode(location, forKey: .location)
        try container.encode(filterKey, forKey: .filterKey)
        try container.encode(relevanceBucket, forKey: .relevanceBucket)
        try container.encode(lastModifiedAt, forKey: .lastModifiedAt)
        try container.encode(lastNoteID, forKey: .lastNoteID)
    }
}

public enum DiscoveryCursorCodingError: LocalizedError {
    case invalidToken

    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            "Invalid discovery cursor."
        }
    }
}

public enum DiscoveryCursorCoder {
    public static func encode(_ cursor: DiscoveryCursor) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CompactDiscoveryCursorPayload(cursor: cursor)
        let data = try encoder.encode(payload)
        return base64URLEncoded(data)
    }

    public static func decode(_ token: String) throws -> DiscoveryCursor {
        guard let data = base64URLDecoded(token) else {
            throw DiscoveryCursorCodingError.invalidToken
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(CompactDiscoveryCursorPayload.self, from: data).cursor
        } catch {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(DiscoveryCursor.self, from: data)
            } catch {
                throw DiscoveryCursorCodingError.invalidToken
            }
        }
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecoded(_ token: String) -> Data? {
        let paddedLength = ((token.count + 3) / 4) * 4
        let padding = String(repeating: "=", count: paddedLength - token.count)
        let standard = (token + padding)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: standard)
    }
}

private struct CompactDiscoveryCursorPayload: Codable {
    let v: Int
    let k: DiscoveryKind
    let l: BearNoteLocation
    let f: String
    let r: Int?
    let m: Double
    let i: String

    init(cursor: DiscoveryCursor) {
        self.v = cursor.version
        self.k = cursor.kind
        self.l = cursor.location
        self.f = cursor.filterKey
        self.r = cursor.relevanceBucket
        self.m = cursor.lastModifiedAt.timeIntervalSinceReferenceDate
        self.i = cursor.lastNoteID
    }

    var cursor: DiscoveryCursor {
        DiscoveryCursor(
            version: v,
            kind: k,
            location: l,
            filterKey: f,
            relevanceBucket: r ?? 0,
            lastModifiedAt: Date(timeIntervalSinceReferenceDate: m),
            lastNoteID: i
        )
    }
}

public struct DiscoveryRankedNote: Hashable, Sendable {
    public let note: BearNote
    public let relevanceBucket: Int

    public init(note: BearNote, relevanceBucket: Int = 0) {
        self.note = note
        self.relevanceBucket = relevanceBucket
    }
}

public struct DiscoveryNoteBatch: Hashable, Sendable {
    public let items: [DiscoveryRankedNote]
    public let hasMore: Bool

    public var notes: [BearNote] {
        items.map(\.note)
    }

    public init(notes: [BearNote], hasMore: Bool, relevanceBuckets: [Int]? = nil) {
        let buckets = relevanceBuckets ?? Array(repeating: 0, count: notes.count)
        self.items = notes.enumerated().map { index, note in
            DiscoveryRankedNote(note: note, relevanceBucket: index < buckets.count ? buckets[index] : 0)
        }
        self.hasMore = hasMore
    }

    public init(items: [DiscoveryRankedNote], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }
}

public struct NoteSummary: Codable, Hashable, Sendable {
    public let noteID: String
    public let title: String
    public let snippet: String
    public let attachmentSnippet: String?
    public let matchedFields: [FindSearchField]?
    public let tags: [String]
    public let createdAt: Date
    public let modifiedAt: Date
    public let archived: Bool

    public init(
        noteID: String,
        title: String,
        snippet: String,
        attachmentSnippet: String? = nil,
        matchedFields: [FindSearchField]? = nil,
        tags: [String],
        createdAt: Date,
        modifiedAt: Date,
        archived: Bool,
    ) {
        self.noteID = noteID
        self.title = title
        self.snippet = snippet
        self.attachmentSnippet = attachmentSnippet
        self.matchedFields = matchedFields
        self.tags = tags
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.archived = archived
    }
}

public struct DiscoveryPageInfo: Codable, Hashable, Sendable {
    public let limit: Int
    public let returned: Int
    public let hasMore: Bool
    public let nextCursor: String?

    public init(limit: Int, returned: Int, hasMore: Bool, nextCursor: String?) {
        self.limit = limit
        self.returned = returned
        self.hasMore = hasMore
        self.nextCursor = nextCursor
    }
}

public struct DiscoveryPage<Item: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public let items: [Item]
    public let page: DiscoveryPageInfo

    public init(items: [Item], page: DiscoveryPageInfo) {
        self.items = items
        self.page = page
    }
}

public typealias NoteSummaryPage = DiscoveryPage<NoteSummary>

public struct FindNotesOperationResult: Codable, Hashable, Sendable {
    public let index: Int
    public let id: String?
    public let items: [NoteSummary]?
    public let page: DiscoveryPageInfo?
    public let error: String?

    public init(
        index: Int,
        id: String?,
        items: [NoteSummary]? = nil,
        page: DiscoveryPageInfo? = nil,
        error: String? = nil
    ) {
        self.index = index
        self.id = id
        self.items = items
        self.page = page
        self.error = error
    }
}

public struct FindNotesBatchResult: Codable, Hashable, Sendable {
    public let results: [FindNotesOperationResult]

    public init(results: [FindNotesOperationResult]) {
        self.results = results
    }
}

public struct ListBackupsOperation: Codable, Hashable, Sendable {
    public let id: String?
    public let noteID: String?
    public let limit: Int?

    public init(id: String? = nil, noteID: String? = nil, limit: Int? = nil) {
        self.id = id
        self.noteID = noteID
        self.limit = limit
    }
}

public struct BearBackupSummary: Codable, Hashable, Sendable {
    public let snapshotID: String
    public let noteID: String
    public let title: String
    public let version: Int
    public let modifiedAt: Date
    public let capturedAt: Date
    public let reason: BackupReason
    public let snippet: String?

    public init(
        snapshotID: String,
        noteID: String,
        title: String,
        version: Int,
        modifiedAt: Date,
        capturedAt: Date,
        reason: BackupReason,
        snippet: String?
    ) {
        self.snapshotID = snapshotID
        self.noteID = noteID
        self.title = title
        self.version = version
        self.modifiedAt = modifiedAt
        self.capturedAt = capturedAt
        self.reason = reason
        self.snippet = snippet
    }
}

public struct ListBackupsOperationResult: Codable, Hashable, Sendable {
    public let index: Int
    public let id: String?
    public let items: [BearBackupSummary]
    public let error: String?

    public init(index: Int, id: String?, items: [BearBackupSummary] = [], error: String? = nil) {
        self.index = index
        self.id = id
        self.items = items
        self.error = error
    }
}

public struct ListBackupsBatchResult: Codable, Hashable, Sendable {
    public let results: [ListBackupsOperationResult]

    public init(results: [ListBackupsOperationResult]) {
        self.results = results
    }
}

public struct TagSummary: Codable, Hashable, Sendable {
    public let name: String
    public let identifier: String?
    public let noteCount: Int

    public init(name: String, identifier: String?, noteCount: Int) {
        self.name = name
        self.identifier = identifier
        self.noteCount = noteCount
    }
}

public enum BearNoteLocation: String, Codable, Hashable, Sendable {
    case notes
    case archive
}

public enum InsertPosition: String, Codable, Hashable, Sendable {
    case top
    case bottom
}

public enum ReplaceContentKind: String, Codable, Hashable, Sendable {
    case title
    case body
    case string
}

public enum ReplaceStringOccurrence: String, Codable, Hashable, Sendable {
    case one
    case all
}

public enum BackupReason: String, Codable, Hashable, Sendable {
    case insertText = "insert_text"
    case replaceContent = "replace_content"
    case addFile = "add_file"
    case restore = "restore"
}

public struct BearPresentationOptions: Codable, Hashable, Sendable {
    public var openNote: Bool
    public var openNoteOverride: Bool?
    public var newWindow: Bool
    public var newWindowOverride: Bool?
    public var showWindow: Bool
    public var edit: Bool

    public init(
        openNote: Bool = false,
        openNoteOverride: Bool? = nil,
        newWindow: Bool = false,
        newWindowOverride: Bool? = nil,
        showWindow: Bool = true,
        edit: Bool = false
    ) {
        self.openNote = openNote
        self.openNoteOverride = openNoteOverride
        self.newWindow = newWindow
        self.newWindowOverride = newWindowOverride
        self.showWindow = showWindow
        self.edit = edit
    }
}

public struct CreateNoteRequest: Codable, Hashable, Sendable {
    public let title: String
    public let content: String
    public let tags: [String]
    public let useOnlyRequestTags: Bool?
    public let presentation: BearPresentationOptions

    public init(
        title: String,
        content: String,
        tags: [String],
        useOnlyRequestTags: Bool? = nil,
        presentation: BearPresentationOptions
    ) {
        self.title = title
        self.content = content
        self.tags = tags
        self.useOnlyRequestTags = useOnlyRequestTags
        self.presentation = presentation
    }
}

public struct InsertTextRequest: Codable, Hashable, Sendable {
    public let noteID: String
    public let text: String
    public let position: InsertPosition
    public let presentation: BearPresentationOptions
    public let expectedVersion: Int?

    public init(
        noteID: String,
        text: String,
        position: InsertPosition,
        presentation: BearPresentationOptions,
        expectedVersion: Int?
    ) {
        self.noteID = noteID
        self.text = text
        self.position = position
        self.presentation = presentation
        self.expectedVersion = expectedVersion
    }
}

public struct ReplaceContentRequest: Codable, Hashable, Sendable {
    public let noteID: String
    public let kind: ReplaceContentKind
    public let oldString: String?
    public let occurrence: ReplaceStringOccurrence?
    public let newString: String
    public let presentation: BearPresentationOptions
    public let expectedVersion: Int?

    public init(
        noteID: String,
        kind: ReplaceContentKind,
        oldString: String?,
        occurrence: ReplaceStringOccurrence?,
        newString: String,
        presentation: BearPresentationOptions,
        expectedVersion: Int?
    ) {
        self.noteID = noteID
        self.kind = kind
        self.oldString = oldString
        self.occurrence = occurrence
        self.newString = newString
        self.presentation = presentation
        self.expectedVersion = expectedVersion
    }
}

public struct OpenNoteRequest: Codable, Hashable, Sendable {
    public let noteID: String
    public let presentation: BearPresentationOptions

    public init(noteID: String, presentation: BearPresentationOptions) {
        self.noteID = noteID
        self.presentation = presentation
    }
}

public struct OpenTagRequest: Codable, Hashable, Sendable {
    public let tag: String

    public init(tag: String) {
        self.tag = tag
    }
}

public struct RenameTagRequest: Codable, Hashable, Sendable {
    public let name: String
    public let newName: String
    public let showWindow: Bool?

    public init(name: String, newName: String, showWindow: Bool?) {
        self.name = name
        self.newName = newName
        self.showWindow = showWindow
    }
}

public struct AddFileRequest: Codable, Hashable, Sendable {
    public let noteID: String
    public let filePath: String
    public let header: String?
    public let position: InsertPosition
    public let presentation: BearPresentationOptions
    public let expectedVersion: Int?

    public init(
        noteID: String,
        filePath: String,
        header: String? = nil,
        position: InsertPosition,
        presentation: BearPresentationOptions,
        expectedVersion: Int?
    ) {
        self.noteID = noteID
        self.filePath = filePath
        self.header = header
        self.position = position
        self.presentation = presentation
        self.expectedVersion = expectedVersion
    }
}

public struct RestoreBackupRequest: Codable, Hashable, Sendable {
    public let noteID: String
    public let snapshotID: String?
    public let presentation: BearPresentationOptions

    public init(noteID: String, snapshotID: String?, presentation: BearPresentationOptions) {
        self.noteID = noteID
        self.snapshotID = snapshotID
        self.presentation = presentation
    }
}

public struct MutationReceipt: Codable, Hashable, Sendable {
    public let noteID: String?
    public let title: String?
    public let status: String
    public let modifiedAt: Date?

    public init(noteID: String?, title: String?, status: String, modifiedAt: Date?) {
        self.noteID = noteID
        self.title = title
        self.status = status
        self.modifiedAt = modifiedAt
    }
}

public struct RestoreBackupReceipt: Codable, Hashable, Sendable {
    public let noteID: String
    public let title: String?
    public let status: String
    public let modifiedAt: Date?
    public let snapshotID: String

    public init(noteID: String, title: String?, status: String, modifiedAt: Date?, snapshotID: String) {
        self.noteID = noteID
        self.title = title
        self.status = status
        self.modifiedAt = modifiedAt
        self.snapshotID = snapshotID
    }
}

public struct TagMutationReceipt: Codable, Hashable, Sendable {
    public let tag: String
    public let newTag: String?
    public let status: String

    public init(tag: String, newTag: String?, status: String) {
        self.tag = tag
        self.newTag = newTag
        self.status = status
    }
}

public struct BearBackupSnapshot: Codable, Hashable, Sendable {
    public let snapshotID: String
    public let noteID: String
    public let title: String
    public let rawText: String
    public let version: Int
    public let modifiedAt: Date
    public let capturedAt: Date
    public let reason: BackupReason
    public let operationGroupID: String?

    public init(
        snapshotID: String,
        noteID: String,
        title: String,
        rawText: String,
        version: Int,
        modifiedAt: Date,
        capturedAt: Date,
        reason: BackupReason,
        operationGroupID: String?
    ) {
        self.snapshotID = snapshotID
        self.noteID = noteID
        self.title = title
        self.rawText = rawText
        self.version = version
        self.modifiedAt = modifiedAt
        self.capturedAt = capturedAt
        self.reason = reason
        self.operationGroupID = operationGroupID
    }
}
