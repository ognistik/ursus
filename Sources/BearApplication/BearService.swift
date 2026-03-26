import BearCore
import CryptoKit
import Foundation
import Logging

public final class BearService: @unchecked Sendable {
    private let configuration: BearConfiguration
    private let readStore: BearReadStore
    private let writeTransport: BearWriteTransport
    private let backupStore: (any BearBackupStore)?
    private let logger: Logger
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private var timeZone: TimeZone {
        .current
    }

    private var now: Date {
        Date()
    }

    public init(
        configuration: BearConfiguration,
        readStore: BearReadStore,
        writeTransport: BearWriteTransport,
        backupStore: (any BearBackupStore)? = nil,
        logger: Logger
    ) {
        self.configuration = configuration
        self.readStore = readStore
        self.writeTransport = writeTransport
        self.backupStore = backupStore
        self.logger = logger
    }

    private static func renderOperationError(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    public func findNotes(_ operations: [FindNotesOperation]) throws -> FindNotesBatchResult {
        guard !operations.isEmpty else {
            throw BearError.invalidInput("Missing required array argument 'operations'.")
        }

        let results = operations.enumerated().map { index, operation in
            do {
                let page = try executeFindOperation(operation)
                return FindNotesOperationResult(
                    index: index,
                    id: operation.id,
                    items: page.items,
                    page: page.page
                )
            } catch {
                return FindNotesOperationResult(
                    index: index,
                    id: operation.id,
                    error: Self.renderOperationError(error)
                )
            }
        }

        return FindNotesBatchResult(results: results)
    }

    public func findNotesByTag(_ operations: [FindNotesByTagOperation]) throws -> FindNotesBatchResult {
        guard !operations.isEmpty else {
            throw BearError.invalidInput("Missing required array argument 'operations'.")
        }

        return try findNotes(
            operations.map { operation in
                let normalizedTags = operation.tags.map(BearTag.normalizedName).filter { !$0.isEmpty }
                return FindNotesOperation(
                    id: operation.id,
                    tagsAny: operation.tagMatch == .any ? normalizedTags : [],
                    tagsAll: operation.tagMatch == .all ? normalizedTags : [],
                    location: operation.location,
                    limit: operation.limit,
                    snippetLength: operation.snippetLength,
                    cursor: operation.cursor
                )
            }
        )
    }

    public func findNotesByActiveTags(_ operations: [FindNotesByActiveTagsOperation]) throws -> FindNotesBatchResult {
        guard !operations.isEmpty else {
            throw BearError.invalidInput("Missing required array argument 'operations'.")
        }

        return try findNotes(
            operations.map { operation in
                FindNotesOperation(
                    id: operation.id,
                    activeTagsMode: operation.match,
                    location: operation.location,
                    limit: operation.limit,
                    snippetLength: operation.snippetLength,
                    cursor: operation.cursor
                )
            }
        )
    }

    public func listBackups(_ operations: [ListBackupsOperation]) async throws -> ListBackupsBatchResult {
        guard !operations.isEmpty else {
            throw BearError.invalidInput("Missing required array argument 'operations'.")
        }

        let results = try await mutateEach(Array(operations.enumerated())) { entry in
            let (index, operation) = entry
            do {
                let noteID = try self.resolvedBackupNoteID(operation.noteID)
                let items = try await self.backupStore?.list(
                    noteID: noteID,
                    limit: self.resolvedDiscoveryLimit(operation.limit)
                ) ?? []
                return ListBackupsOperationResult(index: index, id: operation.id, items: items)
            } catch {
                return ListBackupsOperationResult(
                    index: index,
                    id: operation.id,
                    error: Self.renderOperationError(error)
                )
            }
        }

        return ListBackupsBatchResult(results: results)
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
        let noteTemplate = try loadTemplate(at: BearPaths.noteTemplateURL)

        return try await mutateEach(requests) { request in
            let note = try self.resolveNoteSelector(request.noteID)
            if let expected = request.expectedVersion, note.revision.version != expected {
                throw BearError.mutationConflict("Note \(request.noteID) changed from version \(expected) to \(note.revision.version).")
            }

            try await self.captureBackupIfNeeded(for: note, reason: .insertText)
            guard let templateMatch = self.templateBodyMatch(for: note, template: noteTemplate) else {
                return try await self.writeTransport.insertText(
                    InsertTextRequest(
                        noteID: note.ref.identifier,
                        text: request.text,
                        position: request.position,
                        presentation: request.presentation,
                        expectedVersion: request.expectedVersion
                    )
                )
            }

            let updatedContent = self.insertedContent(
                byApplying: request.text,
                to: templateMatch.content,
                position: request.position
            )
            let updatedBody = templateMatch.prefix + updatedContent + templateMatch.suffix
            let updatedRawText = BearText.composeRawText(title: note.title, body: updatedBody)

            return try await self.writeTransport.replaceAll(
                noteID: note.ref.identifier,
                fullText: updatedRawText,
                presentation: request.presentation
            )
        }
    }

    public func replaceContent(_ requests: [ReplaceContentRequest]) async throws -> [MutationReceipt] {
        let noteTemplate = try loadTemplate(at: BearPaths.noteTemplateURL)

        return try await mutateEach(requests) { request in
            let note = try self.resolveNoteSelector(request.noteID)
            if let expected = request.expectedVersion, note.revision.version != expected {
                throw BearError.mutationConflict("Note \(request.noteID) changed from version \(expected) to \(note.revision.version).")
            }

            try await self.captureBackupIfNeeded(for: note, reason: .replaceContent)
            let updatedText = try self.updatedRawText(note: note, request: request, template: noteTemplate)
            return try await self.writeTransport.replaceAll(
                noteID: note.ref.identifier,
                fullText: updatedText,
                presentation: request.presentation
            )
        }
    }

    public func addFiles(_ requests: [AddFileRequest]) async throws -> [MutationReceipt] {
        let noteTemplate = try loadTemplate(at: BearPaths.noteTemplateURL)

        return try await mutateEach(requests) { request in
            let note = try self.resolveNoteSelector(request.noteID)
            if let expected = request.expectedVersion, note.revision.version != expected {
                throw BearError.mutationConflict("Note \(request.noteID) changed from version \(expected) to \(note.revision.version).")
            }

            try await self.captureBackupIfNeeded(for: note, reason: .addFile)
            guard let templateMatch = self.templateBodyMatch(for: note, template: noteTemplate) else {
                return try await self.writeTransport.addFile(
                    AddFileRequest(
                        noteID: note.ref.identifier,
                        filePath: request.filePath,
                        header: request.header,
                        position: request.position,
                        presentation: request.presentation,
                        expectedVersion: request.expectedVersion
                    )
                )
            }

            let anchor = self.makeAttachmentAnchor()
            let internalPresentation = BearPresentationOptions(
                openNote: false,
                newWindow: false,
                showWindow: false,
                edit: false
            )
            let anchoredContent = self.insertedContent(
                byApplying: self.attachmentAnchorMarkdown(anchor),
                to: templateMatch.content,
                position: request.position
            )
            let anchoredBody = templateMatch.prefix + anchoredContent + templateMatch.suffix
            let anchoredRawText = BearText.composeRawText(title: note.title, body: anchoredBody)

            let anchorReceipt = try await self.writeTransport.replaceAll(
                noteID: note.ref.identifier,
                fullText: anchoredRawText,
                presentation: internalPresentation
            )
            guard anchorReceipt.status == "updated" else {
                throw BearError.xCallback(
                    "Could not verify temporary attachment anchor insertion for note \(note.ref.identifier)."
                )
            }

            let addFileReceipt = try await self.writeTransport.addFile(
                AddFileRequest(
                    noteID: note.ref.identifier,
                    filePath: request.filePath,
                    header: anchor.title,
                    position: .top,
                    presentation: internalPresentation,
                    expectedVersion: request.expectedVersion
                )
            )
            guard addFileReceipt.status == "updated" else {
                throw BearError.xCallback(
                    "File add could not be verified before attachment anchor cleanup for note \(note.ref.identifier). The temporary header '\(anchor.title)' may remain."
                )
            }

            let latestNote = try self.loadNote(id: note.ref.identifier)
            guard let latestMatch = self.templateBodyMatch(for: latestNote, template: noteTemplate) else {
                throw BearError.xCallback(
                    "Could not reconcile templated content after adding a file to note \(note.ref.identifier)."
                )
            }

            let cleanedContent = try self.removingAttachmentAnchor(anchor.markdown, from: latestMatch.content)
            let cleanedBody = latestMatch.prefix + cleanedContent + latestMatch.suffix
            let cleanedRawText = BearText.composeRawText(title: latestNote.title, body: cleanedBody)

            return try await self.writeTransport.replaceAll(
                noteID: note.ref.identifier,
                fullText: cleanedRawText,
                presentation: request.presentation
            )
        }
    }

    public func openNotes(_ requests: [OpenNoteRequest]) async throws -> [MutationReceipt] {
        try await mutateEach(requests) { request in
            let note = try self.resolveNoteSelector(request.noteID)
            return try await self.writeTransport.open(
                OpenNoteRequest(
                    noteID: note.ref.identifier,
                    presentation: request.presentation
                )
            )
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

    public func archiveNotes(_ noteSelectors: [String]) async throws -> [MutationReceipt] {
        try await mutateEach(noteSelectors) { noteSelector in
            let note = try self.resolveNoteSelector(noteSelector)
            return try await self.writeTransport.archive(noteID: note.ref.identifier, showWindow: true)
        }
    }

    public func restoreBackups(_ requests: [RestoreBackupRequest]) async throws -> [RestoreBackupReceipt] {
        try await mutateEach(requests) { request in
            let note = try self.resolveNoteSelector(request.noteID)
            guard let snapshot = try await self.backupStore?.snapshot(
                noteID: note.ref.identifier,
                snapshotID: request.snapshotID
            ) else {
                if let snapshotID = request.snapshotID {
                    throw BearError.notFound("Backup snapshot '\(snapshotID)' was not found for note \(note.ref.identifier).")
                }
                throw BearError.notFound("No backup snapshots were found for note \(note.ref.identifier).")
            }

            try await self.captureBackupIfNeeded(for: note, reason: .restore)
            let receipt = try await self.writeTransport.replaceAll(
                noteID: note.ref.identifier,
                fullText: snapshot.rawText,
                presentation: request.presentation
            )
            return RestoreBackupReceipt(
                noteID: note.ref.identifier,
                title: receipt.title ?? note.title,
                status: receipt.status,
                modifiedAt: receipt.modifiedAt,
                snapshotID: snapshot.snapshotID
            )
        }
    }

    private func updatedRawText(note: BearNote, request: ReplaceContentRequest, template: String?) throws -> String {
        try validateReplaceContentRequest(request)

        let plan = replaceContentPlan(for: note, template: template)

        switch request.kind {
        case .title:
            let newTitle = request.newString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newTitle.isEmpty else {
                throw BearError.invalidInput("replace kind 'title' requires a non-empty new_string.")
            }
            return try rawTextByReplacingTitle(in: note, plan: plan, newTitle: newTitle, template: template)
        case .body:
            return rawTextByReplacingEditableContent(in: note, plan: plan, newContent: request.newString)
        case .string:
            let oldString = try requiredReplaceString(request.oldString, noteID: request.noteID)
            let occurrence = try requiredReplaceOccurrence(request.occurrence, noteID: request.noteID)
            let updatedContent = try replacedContent(
                in: plan.content,
                noteID: request.noteID,
                oldString: oldString,
                newString: request.newString,
                occurrence: occurrence
            )
            return rawTextByReplacingEditableContent(in: note, plan: plan, newContent: updatedContent)
        }
    }

    private func loadNote(id: String) throws -> BearNote {
        guard let note = try readStore.note(id: id) else {
            throw BearError.notFound("Bear note not found: \(id)")
        }
        return note
    }

    private func captureBackupIfNeeded(
        for note: BearNote,
        reason: BackupReason,
        operationGroupID: String = UUID().uuidString
    ) async throws {
        guard let backupStore else {
            return
        }

        _ = try await backupStore.capture(
            note: note,
            reason: reason,
            operationGroupID: operationGroupID
        )
    }

    private func resolveNoteSelector(_ selector: String) throws -> BearNote {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BearError.invalidInput("Note selector must not be empty.")
        }

        if let exactIDMatch = try readStore.note(id: trimmed) {
            return exactIDMatch
        }

        let titleMatches = try uniqueNotes(
            readStore.notes(titled: trimmed, location: .notes) +
            readStore.notes(titled: trimmed, location: .archive)
        )

        switch titleMatches.count {
        case 0:
            throw BearError.notFound("Bear note not found for selector '\(trimmed)'.")
        case 1:
            return titleMatches[0]
        default:
            throw BearError.ambiguous("Note selector '\(trimmed)' matched \(titleMatches.count) notes. Use the note id.")
        }
    }

    private func resolvedBackupNoteID(_ selector: String?) throws -> String? {
        guard let selector else {
            return nil
        }

        return try resolveNoteSelector(selector).ref.identifier
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

    private func validateReplaceContentRequest(_ request: ReplaceContentRequest) throws {
        switch request.kind {
        case .title, .body:
            if request.oldString != nil {
                throw BearError.invalidInput("replace kind '\(request.kind.rawValue)' does not accept old_string.")
            }
            if request.occurrence != nil {
                throw BearError.invalidInput("replace kind '\(request.kind.rawValue)' does not accept occurrence.")
            }
        case .string:
            break
        }
    }

    private func requiredReplaceString(_ value: String?, noteID: String) throws -> String {
        guard let value else {
            throw BearError.invalidInput("replace kind 'string' requires old_string for note \(noteID).")
        }
        return value
    }

    private func requiredReplaceOccurrence(_ value: ReplaceStringOccurrence?, noteID: String) throws -> ReplaceStringOccurrence {
        guard let value else {
            throw BearError.invalidInput("replace kind 'string' requires occurrence for note \(noteID).")
        }
        return value
    }

    private func replaceContentPlan(for note: BearNote, template: String?) -> ReplaceContentPlan {
        if let templateMatch = templateBodyMatch(for: note, template: template) {
            return ReplaceContentPlan(content: templateMatch.content, templateMatch: templateMatch)
        }

        return ReplaceContentPlan(content: canonicalBody(for: note), templateMatch: nil)
    }

    private func rawTextByReplacingTitle(
        in note: BearNote,
        plan: ReplaceContentPlan,
        newTitle: String,
        template: String?
    ) throws -> String {
        if let template, plan.templateMatch != nil {
            let updatedBody = TemplateRenderer.renderDocument(
                context: TemplateContext(title: newTitle, content: plan.content, tags: note.tags),
                template: template
            )
            return BearText.composeRawText(title: newTitle, body: updatedBody)
        }

        return BearText.composeRawText(title: newTitle, body: plan.content)
    }

    private func rawTextByReplacingEditableContent(
        in note: BearNote,
        plan: ReplaceContentPlan,
        newContent: String
    ) -> String {
        let updatedBody: String
        if let templateMatch = plan.templateMatch {
            updatedBody = templateMatch.prefix + newContent + templateMatch.suffix
        } else {
            updatedBody = newContent
        }

        return BearText.composeRawText(title: note.title, body: updatedBody)
    }

    private func replacedContent(
        in content: String,
        noteID: String,
        oldString: String,
        newString: String,
        occurrence: ReplaceStringOccurrence
    ) throws -> String {
        switch occurrence {
        case .one:
            let occurrences = content.components(separatedBy: oldString).count - 1
            guard occurrences == 1 else {
                throw BearError.ambiguous("Single content replace in note \(noteID) matched \(occurrences) times.")
            }
        case .all:
            guard content.contains(oldString) else {
                throw BearError.notFound("String not found in editable content for note \(noteID).")
            }
        }

        return content.replacingOccurrences(of: oldString, with: newString)
    }

    private func executeFindOperation(_ operation: FindNotesOperation) throws -> NoteSummaryPage {
        let resolved = try resolveFindOperation(operation)
        logger.info("Finding Bear notes.", metadata: ["location": "\(resolved.query.location.rawValue)", "limit": "\(resolved.limit)"])
        let batch = try readStore.findNotes(resolved.query)
        return try makeDiscoveryPage(
            batch: batch,
            query: resolved.query,
            filterKey: resolved.filterKey,
            limit: resolved.limit,
            snippetLength: operation.snippetLength
        )
    }

    private func makeDiscoveryPage(
        batch: DiscoveryNoteBatch,
        query: FindNotesQuery,
        filterKey: String,
        limit: Int,
        snippetLength: Int?
    ) throws -> NoteSummaryPage {
        let summaries = try makeDiscoverySummaries(
            notes: batch.notes,
            snippetLength: snippetLength,
            query: query
        )
        let nextCursor: String?
        if batch.hasMore, let lastItem = batch.items.last {
            nextCursor = try DiscoveryCursorCoder.encode(
                DiscoveryCursor(
                    kind: .findNotes,
                    location: query.location,
                    filterKey: filterKey,
                    relevanceBucket: lastItem.relevanceBucket,
                    lastModifiedAt: lastItem.note.revision.modifiedAt,
                    lastNoteID: lastItem.note.ref.identifier
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

    private func makeDiscoverySummaries(
        notes: [BearNote],
        snippetLength: Int?,
        query: FindNotesQuery
    ) throws -> [NoteSummary] {
        let resolvedSnippetLength = resolvedSnippetLength(snippetLength)
        let noteTemplate = try loadTemplate(at: BearPaths.noteTemplateURL)

        return try notes.map { note in
            let attachments = try readStore.attachments(noteID: note.ref.identifier)
            return NoteSummary(
                noteID: note.ref.identifier,
                title: note.title,
                snippet: discoverySnippet(for: note, template: noteTemplate, limit: resolvedSnippetLength),
                attachmentSnippet: attachmentSnippet(for: attachments, limit: resolvedSnippetLength),
                matchedFields: matchedFields(for: note, attachments: attachments, query: query),
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

    private func attachmentSnippet(for attachments: [NoteAttachment], limit: Int) -> String? {
        let joined = attachments
            .compactMap(\.searchText)
            .map(normalizedDiscoveryText(_:))
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !joined.isEmpty else {
            return nil
        }

        return truncatedDiscoveryText(joined, limit: limit)
    }

    private func matchedFields(
        for note: BearNote,
        attachments: [NoteAttachment],
        query: FindNotesQuery
    ) -> [FindSearchField]? {
        guard query.text != nil else {
            return nil
        }

        let attachmentText = attachments.compactMap(\.searchText).joined(separator: " ")
        let candidates: [(FindSearchField, String)] = [
            (.title, note.title),
            (.body, canonicalBody(for: note)),
            (.attachments, attachmentText),
        ]

        let fields = query.searchFields.filter { field in
            guard let value = candidates.first(where: { $0.0 == field })?.1, !value.isEmpty else {
                return false
            }
            return positiveTextMatches(value, query: query)
        }

        return fields.isEmpty ? [] : fields
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
        templateBodyMatch(for: note, template: template, normalizedBody: normalizedBody)?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func templateBodyMatch(
        for note: BearNote,
        template: String?,
        normalizedBody: String? = nil
    ) -> TemplateBodyMatch? {
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

        let prefix = normalizedLineEndings(String(rendered[..<range.lowerBound]))
        let suffix = normalizedLineEndings(String(rendered[range.upperBound...]))
        let body = normalizedLineEndings(normalizedBody ?? canonicalBody(for: note))

        guard body.hasPrefix(prefix), body.hasSuffix(suffix) else {
            return nil
        }

        let start = body.index(body.startIndex, offsetBy: prefix.count)
        let end = body.index(body.endIndex, offsetBy: -suffix.count)
        return TemplateBodyMatch(
            prefix: prefix,
            content: String(body[start..<end]),
            suffix: suffix
        )
    }

    private func insertedContent(byApplying insertedText: String, to existingContent: String, position: InsertPosition) -> String {
        switch position {
        case .top:
            return joinedContent(insertedText, existingContent)
        case .bottom:
            return joinedContent(existingContent, insertedText)
        }
    }

    private func makeAttachmentAnchor() -> AttachmentAnchor {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let title = "BEAR_MCP_ATTACHMENT_\(token)"
        return AttachmentAnchor(title: title, markdown: "## \(title)")
    }

    private func attachmentAnchorMarkdown(_ anchor: AttachmentAnchor) -> String {
        anchor.markdown
    }

    private func removingAttachmentAnchor(_ anchorMarkdown: String, from content: String) throws -> String {
        let normalized = normalizedLineEndings(content)
        var lines = normalized.components(separatedBy: "\n")

        guard let index = lines.firstIndex(where: { $0 == anchorMarkdown || $0.hasPrefix(anchorMarkdown) }) else {
            throw BearError.xCallback("Temporary attachment anchor '\(anchorMarkdown)' was not found during cleanup.")
        }

        let remainder = String(lines[index].dropFirst(anchorMarkdown.count))
            .trimmingCharacters(in: .whitespaces)

        if remainder.isEmpty {
            lines.remove(at: index)
        } else {
            lines[index] = remainder
        }

        if index == 0 {
            while lines.first?.isEmpty == true {
                lines.removeFirst()
            }
        }

        return lines.joined(separator: "\n")
    }

    private func joinedContent(_ leading: String, _ trailing: String) -> String {
        guard !leading.isEmpty else {
            return trailing
        }
        guard !trailing.isEmpty else {
            return leading
        }

        let separator = needsBoundaryNewline(between: leading, and: trailing) ? "\n" : ""
        return leading + separator + trailing
    }

    private func needsBoundaryNewline(between leading: String, and trailing: String) -> Bool {
        guard let trailingCharacterOfLeading = leading.last, let leadingCharacterOfTrailing = trailing.first else {
            return false
        }
        return trailingCharacterOfLeading != "\n" && leadingCharacterOfTrailing != "\n"
    }

    private func normalizedLineEndings(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func uniqueNotes(_ notes: [BearNote]) -> [BearNote] {
        var seen: Set<String> = []
        return notes
            .sorted(by: noteSortOrder)
            .filter { note in
                seen.insert(note.ref.identifier).inserted
            }
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

    private struct TemplateBodyMatch {
        let prefix: String
        let content: String
        let suffix: String
    }

    private struct ReplaceContentPlan {
        let content: String
        let templateMatch: TemplateBodyMatch?
    }

    private struct AttachmentAnchor {
        let title: String
        let markdown: String
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

    private func resolveFindOperation(_ operation: FindNotesOperation) throws -> ResolvedFindOperation {
        let text = normalizedOptionalString(operation.text)
        let textNot = normalizedStrings(operation.textNot)
        let searchFields = resolvedSearchFields(operation.searchFields)

        var tagsAny = normalizedTags(operation.tagsAny)
        var tagsAll = normalizedTags(operation.tagsAll)
        let tagsNone = normalizedTags(operation.tagsNone)
        let hasAttachments = operation.hasAttachments
        let hasAttachmentSearchText = operation.hasAttachmentSearchText
        let hasTags = operation.hasTags

        if let activeTagsMode = operation.activeTagsMode {
            let activeTags = normalizedTags(configuration.activeTags)
            guard !activeTags.isEmpty else {
                throw BearError.configuration("The active notes list is empty. Add tags to ~/.config/bear-mcp/config.json first.")
            }

            switch activeTagsMode {
            case .any:
                tagsAny = normalizedTags(tagsAny + activeTags)
            case .all:
                tagsAll = normalizedTags(tagsAll + activeTags)
            }
        }

        let dateField: FindDateField? = (operation.from != nil || operation.to != nil)
            ? (operation.dateField ?? .modifiedAt)
            : operation.dateField
        let from = try parseDateInput(operation.from, bound: .start)
        let to = try parseDateInput(operation.to, bound: .end)

        if let from, let to, from > to {
            throw BearError.invalidInput("The 'from' date must be earlier than or equal to 'to'.")
        }

        guard hasEffectiveFilter(
            text: text,
            textNot: textNot,
            tagsAny: tagsAny,
            tagsAll: tagsAll,
            tagsNone: tagsNone,
            hasAttachments: hasAttachments,
            hasAttachmentSearchText: hasAttachmentSearchText,
            hasTags: hasTags,
            from: from,
            to: to
        ) else {
            throw BearError.invalidInput("Each find operation must include at least one filter.")
        }

        let textMode = operation.textMode
        let textTerms = resolvedTextTerms(text: text, mode: textMode)
        if text != nil, textMode != .substring, textTerms.isEmpty {
            throw BearError.invalidInput("Text filters require at least one non-empty term.")
        }

        let limit = resolvedDiscoveryLimit(operation.limit)
        let filterKey = try findFilterKey(
            text: text,
            textMode: textMode,
            textNot: textNot,
            searchFields: searchFields,
            tagsAny: tagsAny,
            tagsAll: tagsAll,
            tagsNone: tagsNone,
            hasAttachments: hasAttachments,
            hasAttachmentSearchText: hasAttachmentSearchText,
            hasTags: hasTags,
            location: operation.location,
            dateField: dateField,
            from: from,
            to: to
        )
        let cursor = try resolveCursor(
            token: operation.cursor,
            kind: .findNotes,
            location: operation.location,
            filterKey: filterKey
        )

        return ResolvedFindOperation(
            query: FindNotesQuery(
                text: text,
                textMode: textMode,
                textTerms: textTerms,
                textNot: textNot,
                searchFields: searchFields,
                tagsAny: tagsAny,
                tagsAll: tagsAll,
                tagsNone: tagsNone,
                hasAttachments: hasAttachments,
                hasAttachmentSearchText: hasAttachmentSearchText,
                hasTags: hasTags,
                location: operation.location,
                dateField: dateField,
                from: from,
                to: to,
                paging: DiscoveryPaging(limit: limit, cursor: cursor)
            ),
            filterKey: filterKey,
            limit: limit
        )
    }

    private func findFilterKey(
        text: String?,
        textMode: FindTextMode,
        textNot: [String],
        searchFields: [FindSearchField],
        tagsAny: [String],
        tagsAll: [String],
        tagsNone: [String],
        hasAttachments: Bool?,
        hasAttachmentSearchText: Bool?,
        hasTags: Bool?,
        location: BearNoteLocation,
        dateField: FindDateField?,
        from: Date?,
        to: Date?
    ) throws -> String {
        let identity = FindFilterIdentity(
            text: text,
            textMode: textMode,
            textNot: textNot.sorted(),
            searchFields: searchFields.map(\.rawValue).sorted(),
            tagsAny: tagsAny.sorted(),
            tagsAll: tagsAll.sorted(),
            tagsNone: tagsNone.sorted(),
            hasAttachments: hasAttachments,
            hasAttachmentSearchText: hasAttachmentSearchText,
            hasTags: hasTags,
            location: location.rawValue,
            dateField: dateField?.rawValue,
            from: from?.timeIntervalSinceReferenceDate,
            to: to?.timeIntervalSinceReferenceDate
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(identity)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func hasEffectiveFilter(
        text: String?,
        textNot: [String],
        tagsAny: [String],
        tagsAll: [String],
        tagsNone: [String],
        hasAttachments: Bool?,
        hasAttachmentSearchText: Bool?,
        hasTags: Bool?,
        from: Date?,
        to: Date?
    ) -> Bool {
        text != nil
            || !textNot.isEmpty
            || !tagsAny.isEmpty
            || !tagsAll.isEmpty
            || !tagsNone.isEmpty
            || hasAttachments != nil
            || hasAttachmentSearchText != nil
            || hasTags != nil
            || from != nil
            || to != nil
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            guard seen.insert(trimmed.lowercased()).inserted else {
                continue
            }
            normalized.append(trimmed)
        }

        return normalized
    }

    private func normalizedTags(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []

        for value in values {
            let tag = BearTag.normalizedName(value)
            guard !tag.isEmpty else {
                continue
            }
            let key = BearTag.deduplicationKey(tag)
            guard seen.insert(key).inserted else {
                continue
            }
            normalized.append(tag)
        }

        return normalized
    }

    private func resolvedSearchFields(_ fields: [FindSearchField]) -> [FindSearchField] {
        let requested = fields.isEmpty ? [.title, .body, .attachments] : fields
        var seen: Set<FindSearchField> = []
        var normalized: [FindSearchField] = []

        for field in requested {
            guard seen.insert(field).inserted else {
                continue
            }
            normalized.append(field)
        }

        return normalized
    }

    private func resolvedTextTerms(text: String?, mode: FindTextMode) -> [String] {
        guard let text else {
            return []
        }

        switch mode {
        case .substring:
            return [text]
        case .anyTerms, .allTerms:
            return text
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { !$0.isEmpty }
        }
    }

    private func positiveTextMatches(_ value: String, query: FindNotesQuery) -> Bool {
        let haystack = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        switch query.textMode {
        case .substring:
            guard let text = query.text else {
                return false
            }
            let needle = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return haystack.contains(needle)
        case .anyTerms:
            return query.textTerms.contains { term in
                haystack.contains(term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
            }
        case .allTerms:
            return query.textTerms.allSatisfy { term in
                haystack.contains(term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
            }
        }
    }

    private func parseDateInput(_ rawValue: String?, bound: DateRangeBound) throws -> Date? {
        guard let value = normalizedOptionalString(rawValue) else {
            return nil
        }

        if let timestamp = parseISODateTime(value) {
            return timestamp
        }
        if let day = parseDateOnly(value) {
            return bound == .start ? startOfDay(day) : endOfDay(day)
        }
        if let interval = naturalLanguageDateInterval(value) {
            return bound == .start ? interval.start : interval.end
        }

        throw BearError.invalidInput("Could not parse date '\(value)'.")
    }

    private func parseISODateTime(_ value: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        withFractional.timeZone = .current

        if let date = withFractional.date(from: value) {
            return date
        }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        basic.timeZone = .current
        return basic.date(from: value)
    }

    private func parseDateOnly(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func naturalLanguageDateInterval(_ value: String) -> DateInterval? {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized {
        case "today":
            return dayInterval(offset: 0)
        case "yesterday":
            return dayInterval(offset: -1)
        case "this week":
            return shiftedInterval(of: .weekOfYear, by: 0)
        case "last week":
            return shiftedInterval(of: .weekOfYear, by: -1)
        case "this month":
            return shiftedInterval(of: .month, by: 0)
        case "last month":
            return shiftedInterval(of: .month, by: -1)
        case "this year":
            return shiftedInterval(of: .year, by: 0)
        case "last year":
            return shiftedInterval(of: .year, by: -1)
        default:
            return relativeSpanInterval(normalized)
        }
    }

    private func relativeSpanInterval(_ value: String) -> DateInterval? {
        let parts = value.split(whereSeparator: \.isWhitespace)
        guard parts.count == 3,
              let amount = Int(parts[1]),
              amount > 0
        else {
            return nil
        }

        let direction = String(parts[0])
        let rawUnit = String(parts[2])
        let unit: Calendar.Component
        switch rawUnit {
        case "day", "days":
            unit = .day
        case "week", "weeks":
            unit = .weekOfYear
        case "month", "months":
            unit = .month
        default:
            return nil
        }

        switch direction {
        case "last":
            return trailingInterval(unit: unit, amount: amount)
        default:
            return nil
        }
    }

    private func trailingInterval(unit: Calendar.Component, amount: Int) -> DateInterval? {
        switch unit {
        case .day:
            guard let startDate = calendar.date(byAdding: .day, value: -(amount - 1), to: now) else {
                return nil
            }
            return DateInterval(start: startOfDay(startDate), end: endOfDay(now))
        case .weekOfYear, .month:
            guard let startDate = calendar.date(byAdding: unit, value: -(amount - 1), to: now),
                  let startInterval = calendar.dateInterval(of: unit, for: startDate),
                  let currentInterval = calendar.dateInterval(of: unit, for: now)
            else {
                return nil
            }
            return DateInterval(start: startInterval.start, end: endOfInterval(currentInterval))
        default:
            return nil
        }
    }

    private func shiftedInterval(of component: Calendar.Component, by offset: Int) -> DateInterval? {
        guard let date = calendar.date(byAdding: component, value: offset, to: now),
              let interval = calendar.dateInterval(of: component, for: date)
        else {
            return nil
        }
        return DateInterval(start: interval.start, end: endOfInterval(interval))
    }

    private func dayInterval(offset: Int) -> DateInterval? {
        guard let date = calendar.date(byAdding: .day, value: offset, to: now) else {
            return nil
        }
        return DateInterval(start: startOfDay(date), end: endOfDay(date))
    }

    private func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func endOfDay(_ date: Date) -> Date {
        guard let next = calendar.date(byAdding: .day, value: 1, to: startOfDay(date)) else {
            return date
        }
        return next.addingTimeInterval(-1)
    }

    private func endOfInterval(_ interval: DateInterval) -> Date {
        interval.end.addingTimeInterval(-1)
    }

    private func normalizedDiscoveryText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func truncatedDiscoveryText(_ text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }

        let cutoff = text.index(text.startIndex, offsetBy: limit)
        let prefix = String(text[..<cutoff])
        let nextCharacter = cutoff < text.endIndex ? text[cutoff] : nil
        let boundaryIndex = nextCharacter?.isWhitespace == false ? prefix.lastIndex(where: { $0.isWhitespace }) : nil
        let base = String(prefix[..<(boundaryIndex ?? prefix.endIndex)]).trimmingCharacters(in: .whitespacesAndNewlines)
        return base + "…"
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

    private func mutateEach<Input, Output>(
        _ inputs: [Input],
        operation: (Input) async throws -> Output
    ) async throws -> [Output] {
        var receipts: [Output] = []
        for input in inputs {
            receipts.append(try await operation(input))
        }
        return receipts
    }
}

private struct ResolvedFindOperation {
    let query: FindNotesQuery
    let filterKey: String
    let limit: Int
}

private struct FindFilterIdentity: Encodable {
    let text: String?
    let textMode: FindTextMode
    let textNot: [String]
    let searchFields: [String]
    let tagsAny: [String]
    let tagsAll: [String]
    let tagsNone: [String]
    let hasAttachments: Bool?
    let hasAttachmentSearchText: Bool?
    let hasTags: Bool?
    let location: String
    let dateField: String?
    let from: Double?
    let to: Double?
}

private enum DateRangeBound {
    case start
    case end
}
