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

    public func searchNotes(query: String, scope: BearScope, limit: Int) throws -> [NoteSearchHit] {
        logger.info("Searching Bear notes.", metadata: ["scope": "\(scope.rawValue)", "limit": "\(limit)"])
        return try readStore.searchNotes(
            NoteSearchQuery(
                query: query,
                scope: scope,
                includeArchived: true,
                includeTrashed: false,
                limit: limit
            )
        )
    }

    public func getNotes(ids: [String]) throws -> [BearNote] {
        try readStore.notes(withIDs: ids)
    }

    public func listTags() throws -> [TagSummary] {
        try readStore.listTags()
    }

    public func getNotesByTag(tags: [String]) throws -> [BearNote] {
        var notesByID: [String: BearNote] = [:]

        for tag in tags {
            for note in try readStore.notes(matchingTag: tag) {
                notesByID[note.ref.identifier] = note
            }
        }

        return notesByID.values.sorted { $0.revision.modifiedAt > $1.revision.modifiedAt }
    }

    public func getScopeNotes(scope: BearScope) throws -> [BearNote] {
        try readStore.notes(inScope: scope, activeTags: configuration.activeTags)
    }

    public func createNotes(_ requests: [CreateNoteRequest]) async throws -> [MutationReceipt] {
        let noteTemplate = try loadTemplate(at: BearPaths.noteTemplateURL)

        var receipts: [MutationReceipt] = []
        for request in requests {
            let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = mergedCreateTags(request.tags)
            let sanitizedContent = sanitizedCreateContent(title: title, content: request.content)
            let content = configuration.templateManagementEnabled
                ? TemplateRenderer.renderDocument(
                    context: TemplateContext(title: title, content: sanitizedContent, tags: tags),
                    template: noteTemplate
                )
                : sanitizedContent

            BearDebugLog.append(
                "create.rendered title='\(title)' config.activeTags=\(configuration.activeTags) config.createAddsActiveTagsByDefault=\(configuration.createAddsActiveTagsByDefault) config.createRequestTagsMode=\(configuration.createRequestTagsMode.rawValue) config.openUsesNewWindowByDefault=\(configuration.openUsesNewWindowByDefault) tags=\(tags) content=\(content.debugDescription)"
            )

            let effective = CreateNoteRequest(
                title: title,
                content: content,
                tags: tags,
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

    private func mergedCreateTags(_ requestTags: [String]) -> [String] {
        let baseTags: [String]
        if configuration.createAddsActiveTagsByDefault {
            switch configuration.createRequestTagsMode {
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
