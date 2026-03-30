import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func createInteractiveNoteUsesSelectedNoteTagsAndEditingPresentation() async throws {
    let transport = CLIUtilityRecordingWriteTransport(selectedNoteResult: .success("selected-note"))
    let readStore = CLIUtilityReadStore(
        noteByID: [
            "selected-note": makeCLIUtilityNote(
                id: "selected-note",
                title: "Context",
                body: "Body",
                tags: ["project-x", "deep work"]
            ),
        ],
        notesByTitle: [:]
    )
    let service = BearService(
        configuration: makeCLIUtilityConfiguration(token: "secret-token"),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceCLIUtilityTests")
    )

    try await withTemporaryCLIUtilityTemplate("{{content}}\n\n{{tags}}\n") {
        _ = try await service.createInteractiveNote(
            at: try #require(makeCLIUtilityDate(year: 2024, month: 3, day: 28, hour: 17, minute: 5)),
            timeZone: TimeZone(secondsFromGMT: 0)
        )
    }

    let request = try #require(await transport.createdRequests.first)
    #expect(request.title == "240328 - 05:05 PM")
    #expect(request.tags == ["project-x", "deep work"])
    #expect(request.useOnlyRequestTags == true)
    #expect(request.presentation.openNote == true)
    #expect(request.presentation.newWindowOverride == false)
    #expect(request.presentation.edit == true)
}

@Test
func createCLINewNoteDoesNotConsultSelectedNoteAndDefaultsToInboxTags() async throws {
    let transport = CLIUtilityRecordingWriteTransport(selectedNoteResult: .failure(BearError.invalidInput("should not resolve")))
    let service = BearService(
        configuration: makeCLIUtilityConfiguration(),
        readStore: CLIUtilityReadStore(noteByID: [:], notesByTitle: [:]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceCLIUtilityTests")
    )

    try await withTemporaryCLIUtilityTemplate("{{content}}\n\n{{tags}}\n") {
        _ = try await service.createCLINewNote(
            title: nil,
            content: nil,
            tags: nil,
            tagMergeMode: .append,
            openNote: nil,
            newWindow: nil,
            at: try #require(makeCLIUtilityDate(year: 2024, month: 3, day: 28, hour: 17, minute: 5)),
            timeZone: TimeZone(secondsFromGMT: 0)
        )
    }

    let request = try #require(await transport.createdRequests.first)
    #expect(request.title == "240328 - 05:05 PM")
    #expect(request.tags == ["0-inbox", "daily"])
    #expect(request.useOnlyRequestTags == true)
    #expect(request.presentation.openNote == true)
    #expect(request.presentation.openNoteOverride == nil)
    #expect(request.presentation.newWindow == true)
    #expect(request.presentation.newWindowOverride == nil)
    #expect(request.presentation.edit == true)
    #expect(await transport.selectedNoteResolutionCount == 0)
}

@Test
func createCLINewNoteDefaultsToAppendEvenWhenCreateConfigWouldNot() async throws {
    let transport = CLIUtilityRecordingWriteTransport(selectedNoteResult: .failure(BearError.invalidInput("should not resolve")))
    let service = BearService(
        configuration: makeCLIUtilityConfiguration(
            createAddsInboxTagsByDefault: false,
            tagsMergeMode: .replace
        ),
        readStore: CLIUtilityReadStore(noteByID: [:], notesByTitle: [:]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceCLIUtilityTests")
    )

    try await withTemporaryCLIUtilityTemplate("{{content}}\n\n{{tags}}\n") {
        _ = try await service.createCLINewNote(
            title: "Automated Note",
            content: "Body",
            tags: ["project-x"],
            tagMergeMode: .append,
            openNote: nil,
            newWindow: nil
        )
    }

    let request = try #require(await transport.createdRequests.first)
    #expect(request.tags == ["0-inbox", "daily", "project-x"])
    #expect(request.useOnlyRequestTags == true)
    #expect(await transport.selectedNoteResolutionCount == 0)
}

@Test
func createCLINewNoteCanReplaceTagsAndApplyPresentationOverrides() async throws {
    let transport = CLIUtilityRecordingWriteTransport(selectedNoteResult: .failure(BearError.invalidInput("should not resolve")))
    let service = BearService(
        configuration: makeCLIUtilityConfiguration(
            createOpensNoteByDefault: true,
            openUsesNewWindowByDefault: true
        ),
        readStore: CLIUtilityReadStore(noteByID: [:], notesByTitle: [:]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceCLIUtilityTests")
    )

    try await withTemporaryCLIUtilityTemplate("{{content}}\n\n{{tags}}\n") {
        _ = try await service.createCLINewNote(
            title: "Explicit Title",
            content: "# Explicit Title\n\nBody",
            tags: ["project-x"],
            tagMergeMode: .replace,
            openNote: false,
            newWindow: false
        )
    }

    let request = try #require(await transport.createdRequests.first)
    #expect(request.tags == ["project-x"])
    #expect(request.content == "Body\n\n#project-x")
    #expect(request.presentation.openNote == false)
    #expect(request.presentation.openNoteOverride == false)
    #expect(request.presentation.newWindow == false)
    #expect(request.presentation.newWindowOverride == false)
    #expect(request.presentation.edit == false)
}

@Test
func createInteractiveNoteFallsBackToInboxTagsWhenSelectedNoteHasNoTags() async throws {
    let transport = CLIUtilityRecordingWriteTransport(selectedNoteResult: .success("selected-note"))
    let readStore = CLIUtilityReadStore(
        noteByID: [
            "selected-note": makeCLIUtilityNote(
                id: "selected-note",
                title: "Context",
                body: "Body",
                tags: []
            ),
        ],
        notesByTitle: [:]
    )
    let service = BearService(
        configuration: makeCLIUtilityConfiguration(token: "secret-token"),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceCLIUtilityTests")
    )

    try await withTemporaryCLIUtilityTemplate("{{content}}\n\n{{tags}}\n") {
        _ = try await service.createInteractiveNote(
            at: try #require(makeCLIUtilityDate(year: 2024, month: 3, day: 28, hour: 17, minute: 5)),
            timeZone: TimeZone(secondsFromGMT: 0)
        )
    }

    let request = try #require(await transport.createdRequests.first)
    #expect(request.tags == ["0-inbox", "daily"])
}

@Test
func createInteractiveNoteDropsImplicitParentTagsFromSelectedNote() async throws {
    let transport = CLIUtilityRecordingWriteTransport(selectedNoteResult: .success("selected-note"))
    let readStore = CLIUtilityReadStore(
        noteByID: [
            "selected-note": makeCLIUtilityNote(
                id: "selected-note",
                title: "Context",
                body: "Body",
                tags: ["parent", "parent/child", "areas/focus", "standalone"]
            ),
        ],
        notesByTitle: [:]
    )
    let service = BearService(
        configuration: makeCLIUtilityConfiguration(token: "secret-token"),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceCLIUtilityTests")
    )

    try await withTemporaryCLIUtilityTemplate("{{content}}\n\n{{tags}}\n") {
        _ = try await service.createInteractiveNote(
            at: try #require(makeCLIUtilityDate(year: 2024, month: 3, day: 28, hour: 17, minute: 5)),
            timeZone: TimeZone(secondsFromGMT: 0)
        )
    }

    let request = try #require(await transport.createdRequests.first)
    #expect(request.tags == ["parent/child", "areas/focus", "standalone"])
}

@Test
func applyTemplateToTargetsUsesSelectedNoteWhenNoExplicitSelectorIsPassed() async throws {
    let transport = CLIUtilityRecordingWriteTransport(selectedNoteResult: .success("selected-note"))
    let readStore = CLIUtilityReadStore(
        noteByID: [
            "selected-note": makeCLIUtilityNote(
                id: "selected-note",
                title: "Context",
                body: "Body\n\n#project-x\n\n#review"
            ),
        ],
        notesByTitle: [:]
    )
    let service = BearService(
        configuration: makeCLIUtilityConfiguration(token: "secret-token"),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceCLIUtilityTests")
    )

    try await withTemporaryCLIUtilityTemplate("{{content}}\n\n{{tags}}\n") {
        _ = try await service.applyTemplateToTargets([.selected])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.noteID == "selected-note")
    #expect(await transport.selectedNoteResolutionCount == 1)
}

@Test
func trashNoteTargetsResolvesSelectedAndExplicitSelectors() async throws {
    let selected = makeCLIUtilityNote(id: "selected-note", title: "Selected", body: "Body")
    let inbox = makeCLIUtilityNote(id: "note-1", title: "Inbox", body: "Body")
    let transport = CLIUtilityRecordingWriteTransport(selectedNoteResult: .success("selected-note"))
    let readStore = CLIUtilityReadStore(
        noteByID: [
            "selected-note": selected,
            "note-1": inbox,
        ],
        notesByTitle: [
            "inbox": [inbox],
        ]
    )
    let service = BearService(
        configuration: makeCLIUtilityConfiguration(token: "secret-token"),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceCLIUtilityTests")
    )

    let receipts = try await service.trashNoteTargets([.selected, .selector("Inbox")])

    #expect(receipts.map(\.noteID) == ["selected-note", "note-1"])
    #expect(await transport.trashedNoteIDs == ["selected-note", "note-1"])
    #expect(await transport.selectedNoteResolutionCount == 1)
}

@Test
func archiveNoteTargetsResolvesSelectedAndExplicitSelectors() async throws {
    let selected = makeCLIUtilityNote(id: "selected-note", title: "Selected", body: "Body")
    let inbox = makeCLIUtilityNote(id: "note-1", title: "Inbox", body: "Body")
    let transport = CLIUtilityRecordingWriteTransport(selectedNoteResult: .success("selected-note"))
    let readStore = CLIUtilityReadStore(
        noteByID: [
            "selected-note": selected,
            "note-1": inbox,
        ],
        notesByTitle: [
            "inbox": [inbox],
        ]
    )
    let service = BearService(
        configuration: makeCLIUtilityConfiguration(token: "secret-token"),
        readStore: readStore,
        writeTransport: transport,
        logger: Logger(label: "BearServiceCLIUtilityTests")
    )

    let receipts = try await service.archiveNoteTargets([.selected, .selector("Inbox")])

    #expect(receipts.map(\.noteID) == ["selected-note", "note-1"])
    #expect(await transport.archivedNoteIDs == ["selected-note", "note-1"])
    #expect(await transport.archiveShowWindowValues == [true, true])
    #expect(await transport.selectedNoteResolutionCount == 1)
}

private func makeCLIUtilityConfiguration(
    token: String? = nil,
    openNoteInEditModeByDefault: Bool = true,
    createOpensNoteByDefault: Bool = true,
    openUsesNewWindowByDefault: Bool = true,
    createAddsInboxTagsByDefault: Bool = true,
    tagsMergeMode: BearConfiguration.TagsMergeMode = .append
) -> BearConfiguration {
    BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        inboxTags: ["0-inbox", "daily"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        openNoteInEditModeByDefault: openNoteInEditModeByDefault,
        createOpensNoteByDefault: createOpensNoteByDefault,
        openUsesNewWindowByDefault: openUsesNewWindowByDefault,
        createAddsInboxTagsByDefault: createAddsInboxTagsByDefault,
        tagsMergeMode: tagsMergeMode,
        defaultDiscoveryLimit: 20,
        maxDiscoveryLimit: 100,
        defaultSnippetLength: 280,
        maxSnippetLength: 1_000,
        backupRetentionDays: 30,
        token: token
    )
}

private func makeCLIUtilityDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar.date(
        from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
    )
}

private func makeCLIUtilityNote(
    id: String,
    title: String,
    body: String,
    tags: [String] = ["0-inbox"]
) -> BearNote {
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
    let modifiedAt = Date(timeIntervalSince1970: 1_710_000_500)

    return BearNote(
        ref: NoteRef(identifier: id),
        revision: NoteRevision(version: 3, createdAt: createdAt, modifiedAt: modifiedAt),
        title: title,
        body: body,
        rawText: BearText.composeRawText(title: title, body: body),
        tags: tags,
        archived: false,
        trashed: false,
        encrypted: false
    )
}

private final class CLIUtilityReadStore: @unchecked Sendable, BearReadStore {
    private let noteByID: [String: BearNote]
    private let notesByTitle: [String: [BearNote]]

    init(noteByID: [String: BearNote], notesByTitle: [String: [BearNote]]) {
        self.noteByID = noteByID
        self.notesByTitle = notesByTitle
    }

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func note(id: String) throws -> BearNote? { noteByID[id] }
    func notes(withIDs ids: [String]) throws -> [BearNote] { ids.compactMap { noteByID[$0] } }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }

    func notes(titled title: String, location: BearNoteLocation) throws -> [BearNote] {
        let matches = notesByTitle[title.lowercased()] ?? []
        return matches.filter { note in
            switch location {
            case .notes:
                return note.archived == false && note.trashed == false
            case .archive:
                return note.archived && note.trashed == false
            }
        }
    }
}

private actor CLIUtilityRecordingWriteTransport: BearWriteTransport {
    struct ReplaceCall: Sendable {
        let noteID: String
        let fullText: String
    }

    private(set) var createdRequests: [CreateNoteRequest] = []
    private(set) var replaceCalls: [ReplaceCall] = []
    private(set) var archivedNoteIDs: [String] = []
    private(set) var archiveShowWindowValues: [Bool] = []
    private(set) var trashedNoteIDs: [String] = []
    private(set) var selectedNoteResolutionCount = 0
    private let selectedNoteResult: Result<String, any Error>

    init(selectedNoteResult: Result<String, any Error>) {
        self.selectedNoteResult = selectedNoteResult
    }

    func resolveSelectedNoteID(token _: String) async throws -> String {
        selectedNoteResolutionCount += 1
        return try selectedNoteResult.get()
    }

    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        createdRequests.append(request)
        return MutationReceipt(noteID: "created-note", title: request.title, status: "created", modifiedAt: nil)
    }

    func insertText(_ request: InsertTextRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func replaceAll(noteID: String, fullText: String, presentation: BearPresentationOptions) async throws -> MutationReceipt {
        replaceCalls.append(ReplaceCall(noteID: noteID, fullText: fullText))
        return MutationReceipt(noteID: noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func addFile(_ request: AddFileRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func open(_ request: OpenNoteRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "opened", modifiedAt: nil)
    }

    func openTag(_ request: OpenTagRequest) async throws -> TagMutationReceipt {
        TagMutationReceipt(tag: request.tag, newTag: nil, status: "opened")
    }

    func renameTag(_ request: RenameTagRequest) async throws -> TagMutationReceipt {
        TagMutationReceipt(tag: request.name, newTag: request.newName, status: "renamed")
    }

    func deleteTag(_ request: DeleteTagRequest) async throws -> TagMutationReceipt {
        TagMutationReceipt(tag: request.name, newTag: nil, status: "deleted")
    }

    func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        archivedNoteIDs.append(noteID)
        archiveShowWindowValues.append(showWindow)
        return MutationReceipt(noteID: noteID, title: nil, status: "archived", modifiedAt: nil)
    }

    func trash(noteID: String) async throws -> MutationReceipt {
        trashedNoteIDs.append(noteID)
        return MutationReceipt(noteID: noteID, title: nil, status: "trashed", modifiedAt: nil)
    }
}

private func withTemporaryCLIUtilityTemplate<T: Sendable>(_ template: String, operation: @Sendable () async throws -> T) async throws -> T {
    try await withSharedCLIUtilityTemplateFileLock {
        let templateURL = BearPaths.noteTemplateURL
        let fileManager = FileManager.default
        let originalTemplate = fileManager.fileExists(atPath: templateURL.path) ? try String(contentsOf: templateURL) : nil

        try fileManager.createDirectory(at: BearPaths.configDirectoryURL, withIntermediateDirectories: true)
        try template.write(to: templateURL, atomically: true, encoding: .utf8)
        defer {
            if let originalTemplate {
                try? originalTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
            } else {
                try? fileManager.removeItem(at: templateURL)
            }
        }

        return try await operation()
    }
}

private func withSharedCLIUtilityTemplateFileLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    let fileManager = FileManager.default
    let lockURL = fileManager.temporaryDirectory.appendingPathComponent("bear-mcp-tests-template.lock", isDirectory: true)

    while true {
        do {
            try fileManager.createDirectory(at: lockURL, withIntermediateDirectories: false)
            defer { try? fileManager.removeItem(at: lockURL) }
            return try await operation()
        } catch CocoaError.fileWriteFileExists {
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
