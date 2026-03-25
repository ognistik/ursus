import BearCore
import Foundation
import Logging

public final class BearService: @unchecked Sendable {
    private let configuration: BearConfiguration
    private let readStore: BearReadStore
    private let writeTransport: BearWriteTransport
    private let logger: Logger

    public init(
        configuration: BearConfiguration,
        readStore: BearReadStore,
        writeTransport: BearWriteTransport,
        logger: Logger
    ) {
        self.configuration = configuration
        self.readStore = readStore
        self.writeTransport = writeTransport
        self.logger = logger
    }

    public func searchNotes(
        query: String,
        location: BearNoteLocation,
        limit: Int?,
        snippetLength: Int?,
        cursor: String?
    ) throws -> NoteSummaryPage {
        let resolvedLimit = resolvedDiscoveryLimit(limit)
        let filterKey = searchFilterKey(query)
        let resolvedCursor = try resolveCursor(
            token: cursor,
            kind: .searchNotes,
            location: location,
            filterKey: filterKey
        )
        logger.info("Searching Bear notes.", metadata: ["location": "\(location.rawValue)", "limit": "\(resolvedLimit)"])
        let batch = try readStore.searchNotes(
            NoteSearchQuery(
                query: query,
                location: location,
                paging: DiscoveryPaging(limit: resolvedLimit, cursor: resolvedCursor)
            )
        )
        return try makeDiscoveryPage(
            batch: batch,
            kind: .searchNotes,
            location: location,
            filterKey: filterKey,
            limit: resolvedLimit,
            snippetLength: snippetLength
        )
    }

    public func getNotes(selectors: [String], location: BearNoteLocation) throws -> [BearFetchedNote] {
        let noteTemplate = try loadTemplate(at: BearPaths.noteTemplateURL)
        let trimmedSelectors = selectors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        var seen: Set<String> = []
        var notes: [BearFetchedNote] = []

        for selector in trimmedSelectors {
            if let exactIDMatch = try readStore.note(id: selector), noteMatchesLocation(exactIDMatch, location: location) {
                if seen.insert(exactIDMatch.ref.identifier).inserted {
                    notes.append(try fetchedNote(from: exactIDMatch, template: noteTemplate))
                }
                continue
            }

            let titleMatches = try readStore.notes(titled: selector, location: location)
                .sorted(by: noteSortOrder)

            for note in titleMatches where seen.insert(note.ref.identifier).inserted {
                notes.append(try fetchedNote(from: note, template: noteTemplate))
            }
        }

        return notes
    }

    public func listTags(
        location: BearNoteLocation = .notes,
        query: String? = nil,
        underTag: String? = nil
    ) throws -> [TagSummary] {
        try readStore.listTags(
            ListTagsQuery(
                location: location,
                query: normalizedListTagsQuery(query),
                underTag: normalizedUnderTag(underTag)
            )
        )
    }

    public func getNotesByTag(
        tags: [String],
        location: BearNoteLocation,
        limit: Int?,
        snippetLength: Int?,
        cursor: String?
    ) throws -> NoteSummaryPage {
        let normalizedTags = tags.map(BearTag.normalizedName).filter { !$0.isEmpty }
        let resolvedLimit = resolvedDiscoveryLimit(limit)
        let filterKey = tagFilterKey(normalizedTags)
        let resolvedCursor = try resolveCursor(
            token: cursor,
            kind: .notesByTag,
            location: location,
            filterKey: filterKey
        )
        let batch = try readStore.notes(
            matchingAnyTags: TagNotesQuery(
                tags: normalizedTags,
                location: location,
                paging: DiscoveryPaging(limit: resolvedLimit, cursor: resolvedCursor)
            )
        )
        return try makeDiscoveryPage(
            batch: batch,
            kind: .notesByTag,
            location: location,
            filterKey: filterKey,
            limit: resolvedLimit,
            snippetLength: snippetLength
        )
    }

    public func getNotesByActiveTags(
        location: BearNoteLocation,
        limit: Int?,
        snippetLength: Int?,
        cursor: String?
    ) throws -> NoteSummaryPage {
        let activeTags = configuration.activeTags
            .map(BearTag.normalizedName)
            .filter { !$0.isEmpty }

        guard !activeTags.isEmpty else {
            throw BearError.configuration("The active notes list is empty. Add tags to ~/.config/bear-mcp/config.json first.")
        }

        let resolvedLimit = resolvedDiscoveryLimit(limit)
        let filterKey = activeTagsFilterKey()
        let resolvedCursor = try resolveCursor(
            token: cursor,
            kind: .notesByActiveTags,
            location: location,
            filterKey: filterKey
        )
        let batch = try readStore.notes(
            matchingAnyTags: TagNotesQuery(
                tags: activeTags,
                location: location,
                paging: DiscoveryPaging(limit: resolvedLimit, cursor: resolvedCursor)
            )
        )
        return try makeDiscoveryPage(
            batch: batch,
            kind: .notesByActiveTags,
            location: location,
            filterKey: filterKey,
            limit: resolvedLimit,
            snippetLength: snippetLength
        )
    }

    public func createNotes(_ requests: [CreateNoteRequest]) async throws -> [MutationReceipt] {
        let noteTemplate = try loadTemplate(at: BearPaths.noteTemplateURL)

        var receipts: [MutationReceipt] = []
        for request in requests {
            let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = mergedCreateTags(request.tags, useOnlyRequestTagsOverride: request.useOnlyRequestTags)
            let sanitizedContent = sanitizedCreateContent(title: title, content: request.content)
            let content = configuration.templateManagementEnabled
                ? TemplateRenderer.renderDocument(
                    context: TemplateContext(title: title, content: sanitizedContent, tags: tags),
                    template: noteTemplate
                )
                : sanitizedContent

            BearDebugLog.append(
                "create.rendered title='\(title)' config.activeTags=\(configuration.activeTags) config.createAddsActiveTagsByDefault=\(configuration.createAddsActiveTagsByDefault) config.tagsMergeMode=\(configuration.tagsMergeMode.rawValue) request.useOnlyRequestTags=\(request.useOnlyRequestTags.map(String.init(describing:)) ?? "nil") config.openUsesNewWindowByDefault=\(configuration.openUsesNewWindowByDefault) tags=\(tags) content=\(content.debugDescription)"
            )

            let effective = CreateNoteRequest(
                title: title,
                content: content,
                tags: tags,
                useOnlyRequestTags: request.useOnlyRequestTags,
                presentation: request.presentation
            )
            receipts.append(try await writeTransport.create(effective))
        }
        return receipts
    }

    public func insertText(_ requests: [InsertTextRequest]) async throws -> [MutationReceipt] {
        try await mutateEach(requests) { request in
            if let expected = request.expectedVersion {
                try self.assertVersion(noteID: request.noteID, expectedVersion: expected)
            }
            return try await self.writeTransport.insertText(request)
        }
    }

    public func replaceNoteBody(_ requests: [ReplaceNoteBodyRequest]) async throws -> [MutationReceipt] {
        try await mutateEach(requests) { request in
            let note = try self.loadNote(id: request.noteID)
            if let expected = request.expectedVersion, note.revision.version != expected {
                throw BearError.mutationConflict("Note \(request.noteID) changed from version \(expected) to \(note.revision.version).")
            }

            let updatedText = try self.updatedRawText(note: note, request: request)
            return try await self.writeTransport.replaceAll(
                noteID: request.noteID,
                fullText: updatedText,
                presentation: request.presentation
            )
        }
    }

    public func addFiles(_ requests: [AddFileRequest]) async throws -> [MutationReceipt] {
        try await mutateEach(requests) { request in
            if let expected = request.expectedVersion {
                try self.assertVersion(noteID: request.noteID, expectedVersion: expected)
            }
            return try await self.writeTransport.addFile(request)
        }
    }

    public func openNotes(_ requests: [OpenNoteRequest]) async throws -> [MutationReceipt] {
        try await mutateEach(requests) { request in
            try await self.writeTransport.open(request)
        }
    }

    public func openTag(_ tag: String) async throws -> TagMutationReceipt {
        try await writeTransport.openTag(
            OpenTagRequest(tag: try normalizedTagName(tag, fieldName: "tag"))
        )
    }

    public func renameTags(_ requests: [RenameTagRequest]) async throws -> [TagMutationReceipt] {
        try await mutateEach(requests) { request in
            try await self.writeTransport.renameTag(
                RenameTagRequest(
                    name: try self.normalizedTagName(request.name, fieldName: "name"),
                    newName: try self.normalizedTagName(request.newName, fieldName: "new_name"),
                    showWindow: request.showWindow
                )
            )
        }
    }

    public func archiveNotes(_ noteIDs: [String]) async throws -> [MutationReceipt] {
        try await mutateEach(noteIDs) { noteID in
            try await self.writeTransport.archive(noteID: noteID, showWindow: true)
        }
    }

    private func updatedRawText(note: BearNote, request: ReplaceNoteBodyRequest) throws -> String {
        switch request.mode {
        case .entireBody:
            return request.newString
        case .exact:
            guard let oldString = request.oldString else {
                throw BearError.invalidInput("replace mode 'exact' requires old_string.")
            }
            let occurrences = note.rawText.components(separatedBy: oldString).count - 1
            guard occurrences == 1 else {
                throw BearError.ambiguous("Exact replace in note \(request.noteID) matched \(occurrences) times.")
            }
            return note.rawText.replacingOccurrences(of: oldString, with: request.newString)
        case .all:
            guard let oldString = request.oldString else {
                throw BearError.invalidInput("replace mode 'all' requires old_string.")
            }
            guard note.rawText.contains(oldString) else {
                throw BearError.notFound("String not found in note \(request.noteID).")
            }
            return note.rawText.replacingOccurrences(of: oldString, with: request.newString)
        }
    }

    private func loadNote(id: String) throws -> BearNote {
        guard let note = try readStore.note(id: id) else {
            throw BearError.notFound("Bear note not found: \(id)")
        }
        return note
    }

    private func assertVersion(noteID: String, expectedVersion: Int) throws {
        let note = try loadNote(id: noteID)
        guard note.revision.version == expectedVersion else {
            throw BearError.mutationConflict("Note \(noteID) changed from version \(expectedVersion) to \(note.revision.version).")
        }
    }

    private func loadTemplate(at url: URL) throws -> String? {
        guard configuration.templateManagementEnabled else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try String(contentsOf: url)
    }

    private func mergedCreateTags(_ requestTags: [String], useOnlyRequestTagsOverride: Bool?) -> [String] {
        let baseTags: [String]
        if configuration.createAddsActiveTagsByDefault {
            let mergeMode: BearConfiguration.TagsMergeMode
            if let useOnlyRequestTagsOverride {
                mergeMode = useOnlyRequestTagsOverride ? .replace : .append
            } else {
                mergeMode = configuration.tagsMergeMode
            }

            switch mergeMode {
            case .append:
                baseTags = configuration.activeTags + requestTags
            case .replace:
                baseTags = requestTags.isEmpty ? configuration.activeTags : requestTags
            }
        } else {
            baseTags = requestTags
        }

        var seen: Set<String> = []
        var merged: [String] = []

        for tag in baseTags {
            let normalized = BearTag.normalizedName(tag)
            guard !normalized.isEmpty else {
                continue
            }
            let key = BearTag.deduplicationKey(normalized)
            guard seen.insert(key).inserted else {
                continue
            }
            merged.append(normalized)
        }

        return merged
    }

    private func sanitizedCreateContent(title: String, content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let markdownTitle = "# \(title)"

        if trimmed == markdownTitle {
            return ""
        }

        if trimmed.hasPrefix(markdownTitle + "\n\n") {
            return String(trimmed.dropFirst(markdownTitle.count + 2))
        }

        if trimmed.hasPrefix(markdownTitle + "\n") {
            return String(trimmed.dropFirst(markdownTitle.count + 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private func makeDiscoveryPage(
        batch: DiscoveryNoteBatch,
        kind: DiscoveryKind,
        location: BearNoteLocation,
        filterKey: String,
        limit: Int,
        snippetLength: Int?
    ) throws -> NoteSummaryPage {
        let summaries = try makeDiscoverySummaries(notes: batch.notes, snippetLength: snippetLength)
        let nextCursor: String?
        if batch.hasMore, let lastNote = batch.notes.last {
            nextCursor = try DiscoveryCursorCoder.encode(
                DiscoveryCursor(
                    kind: kind,
                    location: location,
                    filterKey: filterKey,
                    lastModifiedAt: lastNote.revision.modifiedAt,
                    lastNoteID: lastNote.ref.identifier
                )
            )
        } else {
            nextCursor = nil
        }

        return NoteSummaryPage(
            items: summaries,
            page: DiscoveryPageInfo(
                limit: limit,
                returned: summaries.count,
                hasMore: batch.hasMore,
                nextCursor: nextCursor
            )
        )
    }

    private func makeDiscoverySummaries(notes: [BearNote], snippetLength: Int?) throws -> [NoteSummary] {
        let resolvedSnippetLength = resolvedSnippetLength(snippetLength)
        let noteTemplate = try loadTemplate(at: BearPaths.noteTemplateURL)

        return notes.map { note in
            NoteSummary(
                noteID: note.ref.identifier,
                title: note.title,
                snippet: discoverySnippet(for: note, template: noteTemplate, limit: resolvedSnippetLength),
                tags: note.tags,
                createdAt: note.revision.createdAt,
                modifiedAt: note.revision.modifiedAt,
                archived: note.archived
            )
        }
    }

    private func discoverySnippet(for note: BearNote, template: String?, limit: Int) -> String {
        let source = renderedContent(for: note, template: template)
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard normalized.count > limit else {
            return normalized
        }

        let cutoff = normalized.index(normalized.startIndex, offsetBy: limit)
        let prefix = String(normalized[..<cutoff])
        let nextCharacter = cutoff < normalized.endIndex ? normalized[cutoff] : nil
        let boundaryIndex = nextCharacter?.isWhitespace == false ? prefix.lastIndex(where: { $0.isWhitespace }) : nil
        let base = String(prefix[..<(boundaryIndex ?? prefix.endIndex)]).trimmingCharacters(in: .whitespacesAndNewlines)
        return base + "…"
    }

    private func fetchedNote(from note: BearNote, template: String?) throws -> BearFetchedNote {
        if note.encrypted {
            return BearFetchedNote(
                noteID: note.ref.identifier,
                title: note.title,
                content: "",
                tags: note.tags,
                createdAt: note.revision.createdAt,
                modifiedAt: note.revision.modifiedAt,
                version: note.revision.version,
                attachments: [],
                encrypted: true
            )
        }

        return BearFetchedNote(
            noteID: note.ref.identifier,
            title: note.title,
            content: renderedContent(for: note, template: template),
            tags: note.tags,
            createdAt: note.revision.createdAt,
            modifiedAt: note.revision.modifiedAt,
            version: note.revision.version,
            attachments: try readStore.attachments(noteID: note.ref.identifier)
        )
    }

    private func renderedContent(for note: BearNote, template: String?) -> String {
        let normalizedBody = canonicalBody(for: note)
        return templateContent(for: note, template: template, normalizedBody: normalizedBody) ?? normalizedBody
    }

    private func templateContent(for note: BearNote, template: String?, normalizedBody: String? = nil) -> String? {
        guard let template else {
            return nil
        }

        let marker = "__BEAR_MCP_CONTENT_SENTINEL__"
        guard template.components(separatedBy: "{{content}}").count == 2 else {
            return nil
        }

        let rendered = TemplateRenderer.renderDocument(
            context: TemplateContext(title: note.title, content: marker, tags: note.tags),
            template: template
        )
        guard let range = rendered.range(of: marker) else {
            return nil
        }

        let prefix = String(rendered[..<range.lowerBound])
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let suffix = String(rendered[range.upperBound...])
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let body = (normalizedBody ?? canonicalBody(for: note))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard body.hasPrefix(prefix), body.hasSuffix(suffix) else {
            return nil
        }

        let start = body.index(body.startIndex, offsetBy: prefix.count)
        let end = body.index(body.endIndex, offsetBy: -suffix.count)
        return String(body[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func canonicalBody(for note: BearNote) -> String {
        let normalized = note.rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let titleLine = "# \(note.title)"

        let firstLine: String
        let remainder: String
        if let newlineIndex = normalized.firstIndex(of: "\n") {
            firstLine = String(normalized[..<newlineIndex])
            remainder = String(normalized[normalized.index(after: newlineIndex)...])
        } else {
            firstLine = normalized
            remainder = ""
        }

        guard firstLine == titleLine else {
            return normalized
        }

        return remainder.trimmingCharacters(in: .newlines)
    }

    private func noteMatchesLocation(_ note: BearNote, location: BearNoteLocation) -> Bool {
        guard !note.trashed else {
            return false
        }

        switch location {
        case .notes:
            return note.archived == false
        case .archive:
            return note.archived
        }
    }

    private func noteSortOrder(_ lhs: BearNote, _ rhs: BearNote) -> Bool {
        if lhs.revision.modifiedAt != rhs.revision.modifiedAt {
            return lhs.revision.modifiedAt > rhs.revision.modifiedAt
        }
        return lhs.ref.identifier > rhs.ref.identifier
    }

    private func resolveCursor(
        token: String?,
        kind: DiscoveryKind,
        location: BearNoteLocation,
        filterKey: String
    ) throws -> DiscoveryCursor? {
        guard let token else {
            return nil
        }

        let cursor: DiscoveryCursor
        do {
            cursor = try DiscoveryCursorCoder.decode(token)
        } catch {
            throw BearError.invalidInput("Invalid discovery cursor.")
        }

        guard cursor.version == DiscoveryCursor.currentVersion else {
            throw BearError.invalidInput("Unsupported discovery cursor version '\(cursor.version)'.")
        }
        guard cursor.kind == kind, cursor.location == location, cursor.filterKey == filterKey else {
            throw BearError.invalidInput("Discovery cursor does not match this request.")
        }
        return cursor
    }

    private func searchFilterKey(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedListTagsQuery(_ query: String?) -> String? {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedUnderTag(_ underTag: String?) -> String? {
        let normalized = BearTag.normalizedParentPath(underTag ?? "")
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedTagName(_ tag: String, fieldName: String) throws -> String {
        let normalized = BearTag.normalizedName(tag)
        guard !normalized.isEmpty else {
            throw BearError.invalidInput("Missing required string argument '\(fieldName)'.")
        }
        return normalized
    }

    private func tagFilterKey(_ tags: [String]) -> String {
        tags.sorted().joined(separator: "\u{1F}")
    }

    private func activeTagsFilterKey() -> String {
        "active"
    }

    private func resolvedDiscoveryLimit(_ override: Int?) -> Int {
        clampedValue(
            override ?? configuration.defaultDiscoveryLimit,
            fallback: configuration.defaultDiscoveryLimit,
            maximum: configuration.maxDiscoveryLimit
        )
    }

    private func resolvedSnippetLength(_ override: Int?) -> Int {
        clampedValue(
            override ?? configuration.defaultSnippetLength,
            fallback: configuration.defaultSnippetLength,
            maximum: configuration.maxSnippetLength
        )
    }

    private func clampedValue(_ value: Int, fallback: Int, maximum: Int) -> Int {
        let resolvedMaximum = max(1, maximum)
        let resolvedFallback = max(1, min(fallback, resolvedMaximum))
        return max(1, min(value > 0 ? value : resolvedFallback, resolvedMaximum))
    }

    private func mutateEach<Input>(
        _ inputs: [Input],
        operation: (Input) async throws -> MutationReceipt
    ) async throws -> [MutationReceipt] {
        var receipts: [MutationReceipt] = []
        for input in inputs {
            receipts.append(try await operation(input))
        }
        return receipts
    }

    private func mutateEach<Input>(
        _ inputs: [Input],
        operation: (Input) async throws -> TagMutationReceipt
    ) async throws -> [TagMutationReceipt] {
        var receipts: [TagMutationReceipt] = []
        for input in inputs {
            receipts.append(try await operation(input))
        }
        return receipts
    }
}
