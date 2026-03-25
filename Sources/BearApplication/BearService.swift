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
        snippetLength: Int?
    ) throws -> [NoteSummary] {
        let resolvedLimit = resolvedDiscoveryLimit(limit)
        logger.info("Searching Bear notes.", metadata: ["location": "\(location.rawValue)", "limit": "\(resolvedLimit)"])
        let notes = try readStore.searchNotes(
            NoteSearchQuery(
                query: query,
                location: location,
                limit: resolvedLimit
            )
        )
        return try makeDiscoverySummaries(notes: notes, snippetLength: snippetLength)
    }

    public func getNotes(ids: [String]) throws -> [BearNote] {
        try readStore.notes(withIDs: ids)
    }

    public func listTags() throws -> [TagSummary] {
        try readStore.listTags()
    }

    public func getNotesByTag(
        tags: [String],
        location: BearNoteLocation,
        limit: Int?,
        snippetLength: Int?
    ) throws -> [NoteSummary] {
        let notes = try readStore.notes(
            matchingAnyTags: tags,
            location: location,
            limit: resolvedDiscoveryLimit(limit)
        )
        return try makeDiscoverySummaries(notes: notes, snippetLength: snippetLength)
    }

    public func getActiveNotes(
        location: BearNoteLocation,
        limit: Int?,
        snippetLength: Int?
    ) throws -> [NoteSummary] {
        let activeTags = configuration.activeTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !activeTags.isEmpty else {
            throw BearError.configuration("The active notes list is empty. Add tags to ~/.config/bear-mcp/config.json first.")
        }

        let notes = try readStore.notes(
            matchingAnyTags: activeTags,
            location: location,
            limit: resolvedDiscoveryLimit(limit)
        )
        return try makeDiscoverySummaries(notes: notes, snippetLength: snippetLength)
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
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                continue
            }
            let key = normalized.lowercased()
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
        let source = templateContent(for: note, template: template) ?? note.body
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
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

    private func templateContent(for note: BearNote, template: String?) -> String? {
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

        let prefix = String(rendered[..<range.lowerBound]).replacingOccurrences(of: "\r\n", with: "\n")
        let suffix = String(rendered[range.upperBound...]).replacingOccurrences(of: "\r\n", with: "\n")
        let body = note.body.replacingOccurrences(of: "\r\n", with: "\n")

        guard body.hasPrefix(prefix), body.hasSuffix(suffix) else {
            return nil
        }

        let start = body.index(body.startIndex, offsetBy: prefix.count)
        let end = body.index(body.endIndex, offsetBy: -suffix.count)
        return String(body[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
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
}
