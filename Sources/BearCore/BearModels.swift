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

public struct NoteSearchQuery: Codable, Hashable, Sendable {
    public let query: String
    public let location: BearNoteLocation
    public let paging: DiscoveryPaging

    public init(
        query: String,
        location: BearNoteLocation = .notes,
        paging: DiscoveryPaging = DiscoveryPaging(limit: 20)
    ) {
        self.query = query
        self.location = location
        self.paging = paging
    }
}

public struct TagNotesQuery: Codable, Hashable, Sendable {
    public let tags: [String]
    public let location: BearNoteLocation
    public let paging: DiscoveryPaging

    public init(
        tags: [String],
        location: BearNoteLocation = .notes,
        paging: DiscoveryPaging = DiscoveryPaging(limit: 20)
    ) {
        self.tags = tags
        self.location = location
        self.paging = paging
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
    case searchNotes = "search_notes"
    case notesByTag = "notes_by_tag"
    case notesByActiveTags = "notes_by_active_tags"
}

public struct DiscoveryCursor: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let kind: DiscoveryKind
    public let location: BearNoteLocation
    public let filterKey: String
    public let lastModifiedAt: Date
    public let lastNoteID: String

    public init(
        version: Int = DiscoveryCursor.currentVersion,
        kind: DiscoveryKind,
        location: BearNoteLocation,
        filterKey: String,
        lastModifiedAt: Date,
        lastNoteID: String
    ) {
        self.version = version
        self.kind = kind
        self.location = location
        self.filterKey = filterKey
        self.lastModifiedAt = lastModifiedAt
        self.lastNoteID = lastNoteID
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
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cursor)
        return data.base64EncodedString()
    }

    public static func decode(_ token: String) throws -> DiscoveryCursor {
        guard let data = Data(base64Encoded: token) else {
            throw DiscoveryCursorCodingError.invalidToken
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(DiscoveryCursor.self, from: data)
        } catch {
            throw DiscoveryCursorCodingError.invalidToken
        }
    }
}

public struct DiscoveryNoteBatch: Hashable, Sendable {
    public let notes: [BearNote]
    public let hasMore: Bool

    public init(notes: [BearNote], hasMore: Bool) {
        self.notes = notes
        self.hasMore = hasMore
    }
}

public struct NoteSummary: Codable, Hashable, Sendable {
    public let noteID: String
    public let title: String
    public let snippet: String
    public let tags: [String]
    public let createdAt: Date
    public let modifiedAt: Date
    public let archived: Bool

    public init(
        noteID: String,
        title: String,
        snippet: String,
        tags: [String],
        createdAt: Date,
        modifiedAt: Date,
        archived: Bool,
    ) {
        self.noteID = noteID
        self.title = title
        self.snippet = snippet
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

public enum ReplaceMode: String, Codable, Hashable, Sendable {
    case exact
    case all
    case entireBody = "entire_body"
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

public struct ReplaceNoteBodyRequest: Codable, Hashable, Sendable {
    public let noteID: String
    public let mode: ReplaceMode
    public let oldString: String?
    public let newString: String
    public let presentation: BearPresentationOptions
    public let expectedVersion: Int?

    public init(
        noteID: String,
        mode: ReplaceMode,
        oldString: String?,
        newString: String,
        presentation: BearPresentationOptions,
        expectedVersion: Int?
    ) {
        self.noteID = noteID
        self.mode = mode
        self.oldString = oldString
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

public struct AddFileRequest: Codable, Hashable, Sendable {
    public let noteID: String
    public let filePath: String
    public let position: InsertPosition
    public let presentation: BearPresentationOptions
    public let expectedVersion: Int?

    public init(
        noteID: String,
        filePath: String,
        position: InsertPosition,
        presentation: BearPresentationOptions,
        expectedVersion: Int?
    ) {
        self.noteID = noteID
        self.filePath = filePath
        self.position = position
        self.presentation = presentation
        self.expectedVersion = expectedVersion
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
