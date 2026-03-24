import Foundation

public struct NoteRef: Codable, Hashable, Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }
}

public struct NoteRevision: Codable, Hashable, Sendable {
    public let version: Int
    public let modifiedAt: Date

    public init(version: Int, modifiedAt: Date) {
        self.version = version
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
    public let scope: BearScope
    public let includeArchived: Bool
    public let includeTrashed: Bool
    public let limit: Int

    public init(
        query: String,
        scope: BearScope = .all,
        includeArchived: Bool = true,
        includeTrashed: Bool = false,
        limit: Int = 20
    ) {
        self.query = query
        self.scope = scope
        self.includeArchived = includeArchived
        self.includeTrashed = includeTrashed
        self.limit = limit
    }
}

public struct NoteSearchHit: Codable, Hashable, Sendable {
    public let ref: NoteRef
    public let title: String
    public let snippet: String
    public let tags: [String]
    public let archived: Bool
    public let trashed: Bool
    public let modifiedAt: Date

    public init(
        ref: NoteRef,
        title: String,
        snippet: String,
        tags: [String],
        archived: Bool,
        trashed: Bool,
        modifiedAt: Date
    ) {
        self.ref = ref
        self.title = title
        self.snippet = snippet
        self.tags = tags
        self.archived = archived
        self.trashed = trashed
        self.modifiedAt = modifiedAt
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

public enum BearScope: String, Codable, Hashable, Sendable {
    case all
    case active
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
    public var newWindow: Bool
    public var floatingWindow: Bool
    public var showWindow: Bool
    public var edit: Bool

    public init(
        openNote: Bool = false,
        newWindow: Bool = false,
        floatingWindow: Bool = false,
        showWindow: Bool = true,
        edit: Bool = false
    ) {
        self.openNote = openNote
        self.newWindow = newWindow
        self.floatingWindow = floatingWindow
        self.showWindow = showWindow
        self.edit = edit
    }
}

public struct CreateNoteRequest: Codable, Hashable, Sendable {
    public let title: String
    public let content: String
    public let tags: [String]
    public let presentation: BearPresentationOptions

    public init(title: String, content: String, tags: [String], presentation: BearPresentationOptions) {
        self.title = title
        self.content = content
        self.tags = tags
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
