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

    public func findNotesByInboxTags(_ operations: [FindNotesByInboxTagsOperation]) throws -> FindNotesBatchResult {
        guard !operations.isEmpty else {
            throw BearError.invalidInput("Missing required array argument 'operations'.")
        }

        return try findNotes(
            operations.map { operation in
                FindNotesOperation(
                    id: operation.id,
                    inboxTagsMode: operation.match,
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

    public func resolveSelectedNoteID() async throws -> String {
        if let noteID = try await writeTransport.resolveSelectedNoteIDUsingInstalledApp() {
            return noteID
        }

        guard let token = BearSelectedNoteTokenResolver.resolve(configuration: configuration)?.value else {
            throw BearError.invalidInput("Selected-note targeting requires a configured Bear API token.")
        }

        return try await writeTransport.resolveSelectedNoteID(token: token)
    }

    public func resolveNoteTargets(_ targets: [NoteTarget]) async throws -> [String] {
        var resolvedSelectedNoteID: String?
        var resolvedTargets: [String] = []
        resolvedTargets.reserveCapacity(targets.count)

        for target in targets {
            switch target {
            case .selector(let selector):
                resolvedTargets.append(selector)
            case .selected:
                if let resolvedSelectedNoteID {
                    resolvedTargets.append(resolvedSelectedNoteID)
                    continue
                }

                let noteID = try await resolveSelectedNoteID()
                resolvedSelectedNoteID = noteID
                resolvedTargets.append(noteID)
            }
        }

        return resolvedTargets
    }

    public func resolveConcreteNoteIDs(_ targets: [NoteTarget]) async throws -> [String] {
        let resolvedTargets = try await resolveNoteTargets(targets)
        return try resolvedTargets.map { try self.resolveNoteSelector($0).ref.identifier }
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
                "create.rendered title='\(title)' config.inboxTags=\(configuration.inboxTags) config.createAddsInboxTagsByDefault=\(configuration.createAddsInboxTagsByDefault) config.tagsMergeMode=\(configuration.tagsMergeMode.rawValue) request.useOnlyRequestTags=\(request.useOnlyRequestTags.map(String.init(describing:)) ?? "nil") config.openUsesNewWindowByDefault=\(configuration.openUsesNewWindowByDefault) tags=\(tags) content=\(content.debugDescription)"
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

    public func createInteractiveNote(at date: Date = Date(), timeZone: TimeZone? = nil) async throws -> MutationReceipt {
        let seedTags = await interactiveCreateSeedTags()
        let receipts = try await createNotes([
            CreateNoteRequest(
                title: interactiveNoteTitle(for: date, timeZone: timeZone ?? self.timeZone),
                content: "",
                tags: seedTags,
                useOnlyRequestTags: true,
                presentation: BearPresentationOptions(
                    openNote: true,
                    newWindow: false,
                    newWindowOverride: false,
                    showWindow: true,
                    edit: true
                )
            ),
        ])

        guard let receipt = receipts.first else {
            throw BearError.unsupported("Interactive note creation did not produce a mutation receipt.")
        }

        return receipt
    }

    public func insertText(_ requests: [InsertTextRequest]) async throws -> [MutationReceipt] {
        let noteTemplate = try loadTemplate(at: BearPaths.noteTemplateURL)

        return try await mutateEach(requests) { request in
            let note = try self.resolveNoteSelector(request.noteID)
            if let expected = request.expectedVersion, note.revision.version != expected {
                throw BearError.mutationConflict("Note \(request.noteID) changed from version \(expected) to \(note.revision.version).")
            }

            try self.validateRelativeInsertionRequest(position: request.position, target: request.target)
            let plan = self.replaceContentPlan(for: note, template: noteTemplate)

            if let target = request.target {
                let updatedContent = try self.contentByInserting(
                    request.text,
                    into: plan.content,
                    target: target
                )
                try await self.captureBackupIfNeeded(for: note, reason: .insertText)
                let updatedRawText = self.rawTextByReplacingEditableContent(
                    in: note,
                    plan: plan,
                    newContent: updatedContent,
                    template: noteTemplate
                )
                return try await self.writeTransport.replaceAll(
                    noteID: note.ref.identifier,
                    fullText: updatedRawText,
                    presentation: request.presentation
                )
            }

            try await self.captureBackupIfNeeded(for: note, reason: .insertText)
            guard let templateMatch = plan.templateMatch else {
                return try await self.writeTransport.insertText(
                    InsertTextRequest(
                        noteID: note.ref.identifier,
                        text: request.text,
                        position: self.resolvedInsertPosition(request.position),
                        presentation: request.presentation,
                        expectedVersion: request.expectedVersion
                    )
                )
            }

            let updatedContent = self.insertedContent(
                byApplying: request.text,
                to: templateMatch.content,
                position: self.resolvedInsertPosition(request.position)
            )
            let updatedBody = self.renderedTemplateBody(
                title: note.title,
                content: updatedContent,
                literalTags: templateMatch.literalTags,
                template: noteTemplate
            )
            let updatedRawText = self.composeRawTextPreservingStyle(for: note, title: note.title, body: updatedBody)

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

            try self.validateRelativeInsertionRequest(position: request.position, target: request.target)
            let plan = self.replaceContentPlan(for: note, template: noteTemplate)

            if let target = request.target {
                let anchor = self.makeAttachmentAnchor()
                let anchoredContent = try self.contentByInserting(
                    self.attachmentAnchorMarkdown(anchor),
                    into: plan.content,
                    target: target
                )
                try await self.captureBackupIfNeeded(for: note, reason: .addFile)
                return try await self.addFileUsingAnchorFlow(
                    note: note,
                    plan: plan,
                    template: noteTemplate,
                    request: request,
                    updatedContent: anchoredContent,
                    anchor: anchor
                )
            }

            try await self.captureBackupIfNeeded(for: note, reason: .addFile)
            guard let templateMatch = plan.templateMatch else {
                return try await self.writeTransport.addFile(
                    AddFileRequest(
                        noteID: note.ref.identifier,
                        filePath: request.filePath,
                        header: request.header,
                        position: self.resolvedInsertPosition(request.position),
                        presentation: request.presentation,
                        expectedVersion: request.expectedVersion
                    )
                )
            }

            let anchor = self.makeAttachmentAnchor()
            let anchoredContent = self.insertedContent(
                byApplying: self.attachmentAnchorMarkdown(anchor),
                to: templateMatch.content,
                position: self.resolvedInsertPosition(request.position)
            )
            return try await self.addFileUsingAnchorFlow(
                note: note,
                plan: plan,
                template: noteTemplate,
                request: request,
                updatedContent: anchoredContent,
                anchor: anchor
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

    public func deleteTags(_ requests: [DeleteTagRequest]) async throws -> [TagMutationReceipt] {
        try await mutateEach(requests) { request in
            let normalizedName = try self.normalizedTagName(request.name, fieldName: "name")
            guard let existingTag = try self.exactTag(named: normalizedName) else {
                return TagMutationReceipt(tag: normalizedName, newTag: nil, status: "not_found")
            }

            return try await self.writeTransport.deleteTag(
                DeleteTagRequest(
                    name: existingTag.name,
                    showWindow: request.showWindow
                )
            )
        }
    }

    public func addTags(_ requests: [NoteTagsRequest]) async throws -> [NoteTagMutationReceipt] {
        let noteTemplate = try loadTemplate(at: BearPaths.noteTemplateURL)

        return try await mutateEach(requests) { request in
            let note = try self.resolveNoteSelector(request.noteID)
            if let expected = request.expectedVersion, note.revision.version != expected {
                throw BearError.mutationConflict("Note \(request.noteID) changed from version \(expected) to \(note.revision.version).")
            }

            let outcome = try self.noteTagMutationOutcome(
                note: note,
                requestTags: request.tags,
                template: noteTemplate,
                mode: .add
            )

            guard let updatedRawText = outcome.updatedRawText else {
                return NoteTagMutationReceipt(
                    noteID: note.ref.identifier,
                    title: note.title,
                    status: "unchanged",
                    modifiedAt: note.revision.modifiedAt,
                    addedTags: outcome.addedTags,
                    removedTags: outcome.removedTags,
                    skippedTags: outcome.skippedTags
                )
            }

            try await self.captureBackupIfNeeded(for: note, reason: .updateTags)
            let receipt = try await self.writeTransport.replaceAll(
                noteID: note.ref.identifier,
                fullText: updatedRawText,
                presentation: request.presentation
            )

            return NoteTagMutationReceipt(
                noteID: note.ref.identifier,
                title: receipt.title ?? note.title,
                status: receipt.status,
                modifiedAt: receipt.modifiedAt ?? note.revision.modifiedAt,
                addedTags: outcome.addedTags,
                removedTags: outcome.removedTags,
                skippedTags: outcome.skippedTags
            )
        }
    }

    public func removeTags(_ requests: [NoteTagsRequest]) async throws -> [NoteTagMutationReceipt] {
        let noteTemplate = try loadTemplate(at: BearPaths.noteTemplateURL)

        return try await mutateEach(requests) { request in
            let note = try self.resolveNoteSelector(request.noteID)
            if let expected = request.expectedVersion, note.revision.version != expected {
                throw BearError.mutationConflict("Note \(request.noteID) changed from version \(expected) to \(note.revision.version).")
            }

            let outcome = try self.noteTagMutationOutcome(
                note: note,
                requestTags: request.tags,
                template: noteTemplate,
                mode: .remove
            )

            guard let updatedRawText = outcome.updatedRawText else {
                return NoteTagMutationReceipt(
                    noteID: note.ref.identifier,
                    title: note.title,
                    status: "unchanged",
                    modifiedAt: note.revision.modifiedAt,
                    addedTags: outcome.addedTags,
                    removedTags: outcome.removedTags,
                    skippedTags: outcome.skippedTags
                )
            }

            try await self.captureBackupIfNeeded(for: note, reason: .updateTags)
            let receipt = try await self.writeTransport.replaceAll(
                noteID: note.ref.identifier,
                fullText: updatedRawText,
                presentation: request.presentation
            )

            return NoteTagMutationReceipt(
                noteID: note.ref.identifier,
                title: receipt.title ?? note.title,
                status: receipt.status,
                modifiedAt: receipt.modifiedAt ?? note.revision.modifiedAt,
                addedTags: outcome.addedTags,
                removedTags: outcome.removedTags,
                skippedTags: outcome.skippedTags
            )
        }
    }

    public func applyTemplate(_ requests: [ApplyTemplateRequest]) async throws -> [ApplyTemplateReceipt] {
        let loadedTemplate = try loadTemplateFileIfPresent(at: BearPaths.noteTemplateURL)

        return try await mutateEach(requests) { request in
            let note = try self.resolveNoteSelector(request.noteID)
            if let expected = request.expectedVersion, note.revision.version != expected {
                throw BearError.mutationConflict("Note \(request.noteID) changed from version \(expected) to \(note.revision.version).")
            }

            let template = try self.requiredApplyTemplate(loadedTemplate: loadedTemplate, noteTitle: note.title)
            let outcome = try self.applyTemplateOutcome(note: note, template: template)

            guard let updatedRawText = outcome.updatedRawText else {
                return ApplyTemplateReceipt(
                    noteID: note.ref.identifier,
                    title: note.title,
                    status: "unchanged",
                    modifiedAt: note.revision.modifiedAt,
                    appliedTags: outcome.appliedTags
                )
            }

            try await self.captureBackupIfNeeded(for: note, reason: .applyTemplate)
            let receipt = try await self.writeTransport.replaceAll(
                noteID: note.ref.identifier,
                fullText: updatedRawText,
                presentation: request.presentation
            )

            return ApplyTemplateReceipt(
                noteID: note.ref.identifier,
                title: receipt.title ?? note.title,
                status: "applied",
                modifiedAt: receipt.modifiedAt ?? note.revision.modifiedAt,
                appliedTags: outcome.appliedTags
            )
        }
    }

    public func applyTemplateToTargets(_ targets: [NoteTarget]) async throws -> [ApplyTemplateReceipt] {
        let noteIDs = try await resolveConcreteNoteIDs(targets)
        guard !noteIDs.isEmpty else {
            throw BearError.invalidInput("Apply-template CLI requires one or more note targets.")
        }

        return try await applyTemplate(
            noteIDs.map { noteID in
                ApplyTemplateRequest(
                    noteID: noteID,
                    presentation: BearPresentationOptions(
                        openNote: false,
                        newWindow: false,
                        showWindow: false,
                        edit: false
                    ),
                    expectedVersion: nil
                )
            }
        )
    }

    public func trashNoteTargets(_ targets: [NoteTarget]) async throws -> [MutationReceipt] {
        let noteIDs = try await resolveConcreteNoteIDs(targets)
        guard !noteIDs.isEmpty else {
            throw BearError.invalidInput("Delete-note CLI requires one or more note targets.")
        }

        return try await mutateEach(noteIDs) { noteID in
            try await self.writeTransport.trash(noteID: noteID)
        }
    }

    public func archiveNoteTargets(_ targets: [NoteTarget]) async throws -> [MutationReceipt] {
        let noteIDs = try await resolveConcreteNoteIDs(targets)
        guard !noteIDs.isEmpty else {
            throw BearError.invalidInput("Archive-note CLI requires one or more note targets.")
        }

        return try await mutateEach(noteIDs) { noteID in
            try await self.writeTransport.archive(noteID: noteID, showWindow: true)
        }
    }

    public func archiveNotes(_ noteSelectors: [String]) async throws -> [MutationReceipt] {
        try await archiveNoteTargets(noteSelectors.map(NoteTarget.selector))
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

    public func deleteBackups(_ requests: [DeleteBackupRequest]) async throws -> [DeleteBackupReceipt] {
        try await mutateEach(requests) { request in
            let mode = try self.resolvedBackupDeleteMode(request)
            guard let backupStore = self.backupStore else {
                return DeleteBackupReceipt(
                    noteID: mode.noteID,
                    snapshotID: mode.snapshotID,
                    deletedCount: 0,
                    status: "not_found"
                )
            }

            let deletedCount: Int
            switch mode.kind {
            case .snapshot:
                deletedCount = try await backupStore.delete(
                    snapshotID: mode.snapshotID ?? "",
                    noteID: mode.noteID
                )
            case .note:
                deletedCount = try await backupStore.deleteAll(noteID: mode.noteID ?? "")
            }

            return DeleteBackupReceipt(
                noteID: mode.noteID,
                snapshotID: mode.snapshotID,
                deletedCount: deletedCount,
                status: deletedCount > 0 ? "deleted" : "not_found"
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
            return rawTextByReplacingEditableContent(in: note, plan: plan, newContent: request.newString, template: template)
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
            return rawTextByReplacingEditableContent(in: note, plan: plan, newContent: updatedContent, template: template)
        }
    }

    private func exactTag(named normalizedName: String) throws -> TagSummary? {
        for location in [BearNoteLocation.notes, .archive] {
            let matches = try readStore.listTags(
                ListTagsQuery(location: location, query: normalizedName, underTag: nil)
            )
            if let match = matches.first(where: { BearTag.normalizedName($0.name) == normalizedName }) {
                return match
            }
        }

        return nil
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

    private func resolvedBackupDeleteMode(_ request: DeleteBackupRequest) throws -> ResolvedBackupDelete {
        let noteID = try resolvedBackupNoteID(request.noteID)
        let snapshotID = normalizedOptionalString(request.snapshotID)

        if let snapshotID {
            return ResolvedBackupDelete(
                kind: .snapshot,
                noteID: noteID,
                snapshotID: snapshotID
            )
        }

        guard request.deleteAll, let noteID else {
            throw BearError.invalidInput(
                "Delete backup operations require either `snapshot_id`, or `note` with `delete_all: true`."
            )
        }

        return ResolvedBackupDelete(
            kind: .note,
            noteID: noteID,
            snapshotID: nil
        )
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
        return try loadTemplateFileIfPresent(at: url)
    }

    private func loadTemplateFileIfPresent(at url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try String(contentsOf: url)
    }

    private func mergedCreateTags(_ requestTags: [String], useOnlyRequestTagsOverride: Bool?) -> [String] {
        let baseTags: [String]
        if configuration.createAddsInboxTagsByDefault {
            let mergeMode: BearConfiguration.TagsMergeMode
            if let useOnlyRequestTagsOverride {
                mergeMode = useOnlyRequestTagsOverride ? .replace : .append
            } else {
                mergeMode = configuration.tagsMergeMode
            }

            switch mergeMode {
            case .append:
                baseTags = configuration.inboxTags + requestTags
            case .replace:
                baseTags = requestTags.isEmpty ? configuration.inboxTags : requestTags
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

    private func interactiveCreateSeedTags() async -> [String] {
        do {
            let selectedNoteID = try await resolveSelectedNoteID()
            guard let selectedNote = try readStore.note(id: selectedNoteID), !selectedNote.tags.isEmpty else {
                return []
            }
            return BearTag.removingImplicitParentTags(from: selectedNote.tags)
        } catch {
            BearDebugLog.append("cli.new-note.selected-tags-fallback reason=\(Self.renderOperationError(error))")
            return []
        }
    }

    private func interactiveNoteTitle(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyMMdd - hh:mm a"
        return formatter.string(from: date)
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
        if let template, let templateMatch = plan.templateMatch {
            let updatedBody = renderedTemplateBody(
                title: newTitle,
                content: plan.content,
                literalTags: templateMatch.literalTags,
                template: template
            )
            return composeRawTextPreservingStyle(for: note, title: newTitle, body: updatedBody)
        }

        return composeRawTextPreservingStyle(for: note, title: newTitle, body: plan.content)
    }

    private func rawTextByReplacingEditableContent(
        in note: BearNote,
        plan: ReplaceContentPlan,
        newContent: String,
        template: String?
    ) -> String {
        let updatedBody: String
        if let template, let templateMatch = plan.templateMatch {
            updatedBody = renderedTemplateBody(
                title: note.title,
                content: newContent,
                literalTags: templateMatch.literalTags,
                template: template
            )
        } else {
            updatedBody = newContent
        }

        return composeRawTextPreservingStyle(for: note, title: note.title, body: updatedBody)
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

        guard let descriptor = templatePattern(for: template, title: note.title) else {
            return nil
        }

        let body = normalizedLineEndings(normalizedBody ?? canonicalBody(for: note))
        let matchRange = NSRange(location: 0, length: body.utf16.count)
        guard let match = descriptor.regex.firstMatch(in: body, options: [], range: matchRange) else {
            return nil
        }

        let utf16Body = body as NSString
        let contentRange = match.range(at: descriptor.contentCaptureIndex)
        let content = contentRange.location == NSNotFound
            ? ""
            : utf16Body.substring(with: contentRange)
        let literalTags: [String]
        if let tagsCaptureIndex = descriptor.tagsCaptureIndex {
            let tagsRange = match.range(at: tagsCaptureIndex)
            literalTags = tagsRange.location == NSNotFound
                ? []
                : BearTag.extractNormalizedNames(
                    from: utf16Body.substring(with: tagsRange)
                )
        } else {
            literalTags = []
        }

        return TemplateBodyMatch(
            content: content,
            literalTags: literalTags,
            hasTagPlaceholder: descriptor.tagsCaptureIndex != nil
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

    private func resolvedInsertPosition(_ explicitPosition: InsertPosition?) -> InsertPosition {
        explicitPosition ?? configuration.defaultInsertPosition.asInsertPosition
    }

    private func validateRelativeInsertionRequest(position: InsertPosition?, target: RelativeTextTarget?) throws {
        guard target != nil, position != nil else {
            return
        }

        throw BearError.invalidInput("Provide either `position` or `target`, not both, for a single insertion request.")
    }

    private func contentByInserting(
        _ insertedText: String,
        into content: String,
        target: RelativeTextTarget
    ) throws -> String {
        let normalizedContent = normalizedLineEndings(content)
        let matchRange = try insertionTargetRange(in: normalizedContent, target: target)
        let prefix = String(normalizedContent[..<matchRange.lowerBound])
        let matched = String(normalizedContent[matchRange])
        let suffix = String(normalizedContent[matchRange.upperBound...])

        switch target.placement {
        case .before:
            return prefix
                + insertionBoundary(from: prefix, to: insertedText)
                + insertedText
                + insertionBoundary(from: insertedText, to: matched)
                + matched
                + suffix
        case .after:
            return prefix
                + matched
                + insertionBoundary(from: matched, to: insertedText)
                + insertedText
                + insertionBoundary(from: insertedText, to: suffix)
                + suffix
        }
    }

    private func insertionTargetRange(in content: String, target: RelativeTextTarget) throws -> Range<String.Index> {
        switch target.targetKind {
        case .string:
            return try stringTargetRange(in: content, targetText: target.text)
        case .heading:
            return try headingTargetRange(in: content, headingText: target.text)
        }
    }

    private func stringTargetRange(in content: String, targetText: String) throws -> Range<String.Index> {
        guard !targetText.isEmpty else {
            throw BearError.invalidInput("Relative insertion target text must not be empty.")
        }

        var matches: [Range<String.Index>] = []
        var searchStart = content.startIndex
        while searchStart < content.endIndex,
              let range = content.range(of: targetText, range: searchStart..<content.endIndex) {
            matches.append(range)
            searchStart = range.upperBound
        }

        if matches.isEmpty {
            throw BearError.notFound("Relative insertion target was not found in editable content.")
        }
        if matches.count > 1 {
            throw BearError.ambiguous("Relative insertion target matched \(matches.count) times in editable content.")
        }

        return matches[0]
    }

    private func headingTargetRange(in content: String, headingText: String) throws -> Range<String.Index> {
        let normalizedNeedle = normalizedHeadingLookupKey(headingText)
        guard !normalizedNeedle.isEmpty else {
            throw BearError.invalidInput("Relative heading target text must not be empty.")
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var cursor = content.startIndex
        var matches: [Range<String.Index>] = []

        for line in lines {
            let lineString = String(line)
            let lineStart = cursor
            let lineEnd = content.index(lineStart, offsetBy: lineString.count)
            if let matchedHeadingText = markdownHeadingText(from: lineString),
               normalizedHeadingLookupKey(matchedHeadingText) == normalizedNeedle {
                matches.append(lineStart..<lineEnd)
            }

            cursor = lineEnd
            if cursor < content.endIndex {
                cursor = content.index(after: cursor)
            }
        }

        if matches.isEmpty {
            throw BearError.notFound("Relative heading target '\(headingText)' was not found in editable content.")
        }
        if matches.count > 1 {
            throw BearError.ambiguous("Relative heading target '\(headingText)' matched \(matches.count) headings in editable content.")
        }

        return matches[0]
    }

    private func markdownHeadingText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else {
            return nil
        }

        let hashes = trimmed.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else {
            return nil
        }

        let remainder = trimmed.dropFirst(hashes.count)
        guard remainder.first == " " || remainder.first == "\t" else {
            return nil
        }

        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedHeadingLookupKey(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func insertionBoundary(from leading: String, to trailing: String) -> String {
        guard !leading.isEmpty, !trailing.isEmpty else {
            return ""
        }
        guard leading.last != "\n", trailing.first != "\n" else {
            return ""
        }
        return "\n"
    }

    private func addFileUsingAnchorFlow(
        note: BearNote,
        plan: ReplaceContentPlan,
        template: String?,
        request: AddFileRequest,
        updatedContent: String,
        anchor: AttachmentAnchor
    ) async throws -> MutationReceipt {
        let internalPresentation = BearPresentationOptions(
            openNote: false,
            newWindow: false,
            showWindow: false,
            edit: false
        )
        let anchoredRawText = self.rawTextByReplacingEditableContent(
            in: note,
            plan: plan,
            newContent: updatedContent,
            template: template
        )

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
        let latestPlan = self.replaceContentPlan(for: latestNote, template: template)
        let cleanedContent = try self.removingAttachmentAnchor(anchor.markdown, from: latestPlan.content)
        let cleanedRawText = self.rawTextByReplacingEditableContent(
            in: latestNote,
            plan: latestPlan,
            newContent: cleanedContent,
            template: template
        )

        return try await self.writeTransport.replaceAll(
            noteID: note.ref.identifier,
            fullText: cleanedRawText,
            presentation: request.presentation
        )
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

    private func renderedTemplateBody(
        title: String,
        content: String,
        literalTags: [String],
        template: String?
    ) -> String {
        TemplateRenderer.renderDocument(
            context: TemplateContext(title: title, content: content, tags: literalTags),
            template: template
        )
    }

    private func composeRawTextPreservingStyle(for note: BearNote, title: String, body: String) -> String {
        BearText.composeRawText(
            title: title,
            body: body,
            separator: preservedTitleBodySeparator(for: note)
        )
    }

    private func preservedTitleBodySeparator(for note: BearNote) -> String {
        let normalizedRawText = normalizedLineEndings(note.rawText)
        let titleLine = "# \(note.title)"

        guard normalizedRawText.hasPrefix(titleLine) else {
            return "\n\n"
        }

        let separatorStart = normalizedRawText.index(normalizedRawText.startIndex, offsetBy: titleLine.count)
        var cursor = separatorStart
        while cursor < normalizedRawText.endIndex, normalizedRawText[cursor] == "\n" {
            cursor = normalizedRawText.index(after: cursor)
        }

        let separator = String(normalizedRawText[separatorStart..<cursor])
        return separator.isEmpty ? "\n\n" : separator
    }

    private func noteTagMutationOutcome(
        note: BearNote,
        requestTags: [String],
        template: String?,
        mode: NoteTagMutationMode
    ) throws -> NoteTagMutationOutcome {
        let requestedTags = normalizedTags(requestTags)
        guard !requestedTags.isEmpty else {
            throw BearError.invalidInput("Each tag mutation operation requires at least one non-empty tag.")
        }

        let effectiveKeys = Set(note.tags.map(BearTag.deduplicationKey))
        let canonicalBody = canonicalBody(for: note)
        let templateMatch = templateBodyMatch(for: note, template: template, normalizedBody: canonicalBody)
        let literalTags = templateMatch?.hasTagPlaceholder == true
            ? templateMatch?.literalTags ?? []
            : BearTag.extractNormalizedNames(from: canonicalBody)
        let literalKeys = Set(literalTags.map(BearTag.deduplicationKey))

        switch mode {
        case .add:
            var addedTags: [String] = []
            var skippedTags: [String] = []

            for tag in requestedTags {
                let key = BearTag.deduplicationKey(tag)
                if literalKeys.contains(key) || effectiveKeys.contains(key) {
                    skippedTags.append(tag)
                } else {
                    addedTags.append(tag)
                }
            }

            guard !addedTags.isEmpty else {
                return NoteTagMutationOutcome(
                    updatedRawText: nil,
                    addedTags: [],
                    removedTags: [],
                    skippedTags: skippedTags
                )
            }

            let updatedBody = try bodyByAddingTags(
                addedTags,
                to: note,
                canonicalBody: canonicalBody,
                template: template,
                templateMatch: templateMatch,
                templateLiteralTags: literalTags
            )

            let updatedRawText = composeRawTextPreservingStyle(for: note, title: note.title, body: updatedBody)
            return NoteTagMutationOutcome(
                updatedRawText: updatedRawText == note.rawText ? nil : updatedRawText,
                addedTags: addedTags,
                removedTags: [],
                skippedTags: skippedTags
            )

        case .remove:
            var removedTags: [String] = []
            var skippedTags: [String] = []
            let removableKeys = Set(requestedTags.map(BearTag.deduplicationKey))
            let removableLiteralTags = BearTag.extractNormalizedNames(from: canonicalBody)
            let removableLiteralKeys = Set(removableLiteralTags.map(BearTag.deduplicationKey))

            for tag in requestedTags {
                let key = BearTag.deduplicationKey(tag)
                if removableLiteralKeys.contains(key) {
                    removedTags.append(tag)
                } else if effectiveKeys.contains(key) {
                    skippedTags.append(tag)
                } else {
                    skippedTags.append(tag)
                }
            }

            guard !removedTags.isEmpty else {
                return NoteTagMutationOutcome(
                    updatedRawText: nil,
                    addedTags: [],
                    removedTags: [],
                    skippedTags: skippedTags
                )
            }

            let updatedBody = rawBodyByRemovingTags(removableKeys, from: canonicalBody)

            let updatedRawText = composeRawTextPreservingStyle(for: note, title: note.title, body: updatedBody)
            return NoteTagMutationOutcome(
                updatedRawText: updatedRawText == note.rawText ? nil : updatedRawText,
                addedTags: [],
                removedTags: removedTags,
                skippedTags: skippedTags
            )
        }
    }

    private func bodyByAddingTags(
        _ tagsToAdd: [String],
        to note: BearNote,
        canonicalBody: String,
        template: String?,
        templateMatch: TemplateBodyMatch?,
        templateLiteralTags: [String]
    ) throws -> String {
        if let templateMatch {
            guard templateMatch.hasTagPlaceholder else {
                throw invalidTagTemplateError(missingFile: false)
            }

            guard let template else {
                throw invalidTagTemplateError(missingFile: true)
            }

            return renderedTemplateBody(
                title: note.title,
                content: templateMatch.content,
                literalTags: templateLiteralTags + tagsToAdd,
                template: template
            )
        }

        let normalizedBody = normalizedLineEndings(canonicalBody)
        if let cluster = firstTagCluster(in: normalizedBody) {
            return bodyByExtendingTagCluster(cluster, in: normalizedBody, with: tagsToAdd)
        }

        if configuration.templateManagementEnabled {
            let template = try requiredTagTemplateForNonTemplatedAdd(loadedTemplate: template, noteTitle: note.title)
            return renderedTemplateBody(
                title: note.title,
                content: normalizedBody,
                literalTags: tagsToAdd,
                template: template
            )
        }

        return rawBodyByInsertingTagLine(
            TemplateRenderer.renderTags(tagsToAdd),
            into: normalizedBody,
            position: configuration.defaultInsertPosition.asInsertPosition
        )
    }

    private func applyTemplateOutcome(note: BearNote, template: String) throws -> ApplyTemplateOutcome {
        let canonicalBody = canonicalBody(for: note)
        let templateMatch = templateBodyMatch(for: note, template: template, normalizedBody: canonicalBody)
        let editableContent = templateMatch?.content ?? canonicalBody
        let normalizedContent = normalizedLineEndings(editableContent)
        let migratedClusters = allTagClusters(in: normalizedContent)
        let mergedTags = mergedTemplateTags(
            existingTags: templateMatch?.literalTags ?? [],
            migratedClusters: migratedClusters
        )
        let cleanedContent = removingTagClusters(migratedClusters, from: normalizedContent)
        let updatedBody = renderedTemplateBody(
            title: note.title,
            content: cleanedContent,
            literalTags: mergedTags,
            template: template
        )
        let updatedRawText = composeRawTextPreservingStyle(for: note, title: note.title, body: updatedBody)

        return ApplyTemplateOutcome(
            updatedRawText: updatedRawText == note.rawText ? nil : updatedRawText,
            appliedTags: mergedTags
        )
    }

    private func bodyByExtendingTagCluster(_ cluster: TagCluster, in body: String, with tagsToAdd: [String]) -> String {
        let updatedLine = TemplateRenderer.renderTags(cluster.tags + tagsToAdd)
        return replacingLines(
            in: body,
            lineRange: cluster.lineRange,
            with: updatedLine.isEmpty ? [] : [updatedLine]
        )
    }

    private func rawBodyByInsertingTagLine(_ renderedTags: String, into body: String, position: InsertPosition) -> String {
        let normalizedBody = normalizedLineEndings(body)
        guard !renderedTags.isEmpty else {
            return normalizedBody
        }

        let trimmedBody = normalizedBody.trimmingCharacters(in: .whitespacesAndNewlines)
        switch position {
        case .top:
            return joinedContent(renderedTags, trimmedBody)
        case .bottom:
            return joinedContent(trimmedBody, renderedTags)
        }
    }

    private func requiredTagTemplateForNonTemplatedAdd(loadedTemplate: String?, noteTitle: String) throws -> String {
        guard let template = loadedTemplate else {
            throw invalidTagTemplateError(missingFile: true)
        }

        guard let descriptor = templatePattern(for: template, title: noteTitle), descriptor.tagsCaptureIndex != nil else {
            throw invalidTagTemplateError(missingFile: false)
        }

        return template
    }

    private func requiredApplyTemplate(loadedTemplate: String?, noteTitle: String) throws -> String {
        guard let template = loadedTemplate else {
            throw BearError.configuration(
                "The `bear_apply_template` tool requires ~/.config/bear-mcp/template.md, but the file is missing. Restore the current template before applying it to notes."
            )
        }

        guard let descriptor = templatePattern(for: template, title: noteTitle), descriptor.tagsCaptureIndex != nil else {
            throw BearError.configuration(
                "The `bear_apply_template` tool requires ~/.config/bear-mcp/template.md to provide valid `{{content}}` and `{{tags}}` slots. Fix the template before applying it to notes."
            )
        }

        return template
    }

    private func invalidTagTemplateError(missingFile: Bool) -> BearError {
        if missingFile {
            return BearError.configuration(
                "Template management is enabled, but ~/.config/bear-mcp/template.md is missing. Restore a template with a `{{tags}}` slot before adding tags to this note."
            )
        }

        return BearError.configuration(
            "Template management is enabled, but ~/.config/bear-mcp/template.md does not provide a valid `{{tags}}` slot. Fix the template before adding tags to this note."
        )
    }

    private func rawBodyByRemovingTags(_ removableKeys: Set<String>, from body: String) -> String {
        let normalizedBody = normalizedLineEndings(body)
        let removableTokens = BearTag.extractTokens(from: normalizedBody)
            .filter { removableKeys.contains(BearTag.deduplicationKey($0.normalizedName)) }

        guard !removableTokens.isEmpty else {
            return normalizedBody
        }

        let mutable = NSMutableString(string: normalizedBody)
        for token in removableTokens.sorted(by: { $0.utf16Range.lowerBound > $1.utf16Range.lowerBound }) {
            let range = NSRange(location: token.utf16Range.lowerBound, length: token.utf16Range.count)
            mutable.replaceCharacters(in: range, with: "")
        }

        return cleanedTagEditedText(mutable as String)
    }

    private func firstTagCluster(in text: String) -> TagCluster? {
        allTagClusters(in: text).first
    }

    private func allTagClusters(in text: String) -> [TagCluster] {
        let lines = normalizedLineEndings(text).components(separatedBy: "\n")
        var lineIndex = 0
        var clusters: [TagCluster] = []

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            guard isTagOnlyLine(line) else {
                lineIndex += 1
                continue
            }

            let start = lineIndex
            var tags: [String] = []
            while lineIndex < lines.count, isTagOnlyLine(lines[lineIndex]) {
                tags += BearTag.extractNormalizedNames(from: lines[lineIndex])
                lineIndex += 1
            }

            clusters.append(TagCluster(lineRange: start..<lineIndex, tags: normalizedTags(tags)))
        }

        return clusters
    }

    private func isTagOnlyLine(_ line: String) -> Bool {
        let tokens = BearTag.extractTokens(from: line)
        guard !tokens.isEmpty else {
            return false
        }

        let stripped = removingAllTagTokens(from: line)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func removingAllTagTokens(from text: String) -> String {
        let mutable = NSMutableString(string: text)
        for token in BearTag.extractTokens(from: text).sorted(by: { $0.utf16Range.lowerBound > $1.utf16Range.lowerBound }) {
            let range = NSRange(location: token.utf16Range.lowerBound, length: token.utf16Range.count)
            mutable.replaceCharacters(in: range, with: "")
        }
        return mutable as String
    }

    private func replacingLines(in text: String, lineRange: Range<Int>, with replacementLines: [String]) -> String {
        var lines = normalizedLineEndings(text).components(separatedBy: "\n")
        lines.replaceSubrange(lineRange, with: replacementLines)
        return lines.joined(separator: "\n")
    }

    private func removingTagClusters(_ clusters: [TagCluster], from text: String) -> String {
        guard !clusters.isEmpty else {
            return cleanedTagEditedText(text)
        }

        var lines = normalizedLineEndings(text).components(separatedBy: "\n")
        for cluster in clusters.sorted(by: { $0.lineRange.lowerBound > $1.lineRange.lowerBound }) {
            lines.removeSubrange(cluster.lineRange)
        }
        return cleanedTagEditedText(lines.joined(separator: "\n"))
    }

    private func mergedTemplateTags(existingTags: [String], migratedClusters: [TagCluster]) -> [String] {
        var seen: Set<String> = []
        var merged: [String] = []

        for tag in existingTags + migratedClusters.flatMap(\.tags) {
            let key = BearTag.deduplicationKey(tag)
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            merged.append(tag)
        }

        return merged
    }

    private func cleanedTagEditedText(_ text: String) -> String {
        let lines = normalizedLineEndings(text)
            .components(separatedBy: "\n")
            .map { line in
                line
                    .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }

        var collapsed: [String] = []
        var previousWasBlank = false

        for line in lines {
            if line.isEmpty {
                guard !previousWasBlank else {
                    continue
                }
                previousWasBlank = true
                collapsed.append("")
            } else {
                previousWasBlank = false
                collapsed.append(line)
            }
        }

        while collapsed.first?.isEmpty == true {
            collapsed.removeFirst()
        }
        while collapsed.last?.isEmpty == true {
            collapsed.removeLast()
        }

        return collapsed.joined(separator: "\n")
    }

    private func templatePattern(for template: String, title: String) -> TemplatePattern? {
        let normalizedTemplate = normalizedLineEndings(template)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let contentMatches = normalizedTemplate.components(separatedBy: "{{content}}").count - 1
        let tagsMatches = normalizedTemplate.components(separatedBy: "{{tags}}").count - 1

        guard contentMatches == 1, tagsMatches <= 1 else {
            return nil
        }

        let placeholderPattern = #"\{\{title\}\}|\{\{content\}\}|\{\{tags\}\}"#
        guard let placeholderRegex = try? NSRegularExpression(pattern: placeholderPattern) else {
            return nil
        }

        let nsTemplate = normalizedTemplate as NSString
        let fullRange = NSRange(location: 0, length: nsTemplate.length)
        let matches = placeholderRegex.matches(in: normalizedTemplate, options: [], range: fullRange)
        let lastMatchUpperBound = matches.last.map { $0.range.location + $0.range.length }

        var pattern = "(?s)\\A"
        var cursor = 0
        var captureIndex = 1
        var contentCaptureIndex: Int?
        var tagsCaptureIndex: Int?

        for match in matches {
            let literal = nsTemplate.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let placeholder = nsTemplate.substring(with: match.range)
            switch placeholder {
            case "{{title}}":
                pattern += NSRegularExpression.escapedPattern(for: literal)
                pattern += NSRegularExpression.escapedPattern(for: title)
            case "{{content}}":
                contentCaptureIndex = captureIndex
                let isTerminalContentPlaceholder = lastMatchUpperBound == nsTemplate.length
                    && match.range.location + match.range.length == nsTemplate.length

                if isTerminalContentPlaceholder, literal.hasSuffix("\n") {
                    let literalWithoutTrailingNewline = String(literal.dropLast())
                    pattern += NSRegularExpression.escapedPattern(for: literalWithoutTrailingNewline)
                    pattern += "(?:\\n(.*?))?"
                } else {
                    pattern += NSRegularExpression.escapedPattern(for: literal)
                    pattern += "(.*?)"
                }
                captureIndex += 1
            case "{{tags}}":
                pattern += NSRegularExpression.escapedPattern(for: literal)
                tagsCaptureIndex = captureIndex
                pattern += "(.*?)"
                captureIndex += 1
            default:
                pattern += NSRegularExpression.escapedPattern(for: literal)
                break
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsTemplate.length {
            pattern += NSRegularExpression.escapedPattern(
                for: nsTemplate.substring(with: NSRange(location: cursor, length: nsTemplate.length - cursor))
            )
        }
        pattern += "\\z"

        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let contentCaptureIndex
        else {
            return nil
        }

        return TemplatePattern(
            regex: regex,
            contentCaptureIndex: contentCaptureIndex,
            tagsCaptureIndex: tagsCaptureIndex
        )
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
        let content: String
        let literalTags: [String]
        let hasTagPlaceholder: Bool
    }

    private struct ReplaceContentPlan {
        let content: String
        let templateMatch: TemplateBodyMatch?
    }

    private struct AttachmentAnchor {
        let title: String
        let markdown: String
    }

    private struct TagCluster {
        let lineRange: Range<Int>
        let tags: [String]
    }

    private struct TemplatePattern {
        let regex: NSRegularExpression
        let contentCaptureIndex: Int
        let tagsCaptureIndex: Int?
    }

    private struct NoteTagMutationOutcome {
        let updatedRawText: String?
        let addedTags: [String]
        let removedTags: [String]
        let skippedTags: [String]
    }

    private struct ApplyTemplateOutcome {
        let updatedRawText: String?
        let appliedTags: [String]
    }

    private enum NoteTagMutationMode {
        case add
        case remove
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
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = BearTag.normalizedName(trimmed)
        return normalized.isEmpty ? trimmed : normalized
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

        if let inboxTagsMode = operation.inboxTagsMode {
            let inboxTags = normalizedTags(configuration.inboxTags)
            guard !inboxTags.isEmpty else {
                throw BearError.configuration("The inbox tag list is empty. Add tags to ~/.config/bear-mcp/config.json first.")
            }

            switch inboxTagsMode {
            case .any:
                tagsAny = normalizedTags(tagsAny + inboxTags)
            case .all:
                tagsAll = normalizedTags(tagsAll + inboxTags)
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

private struct ResolvedBackupDelete {
    enum Kind {
        case snapshot
        case note
    }

    let kind: Kind
    let noteID: String?
    let snapshotID: String?
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
