import BearApplication
import BearCore
import Foundation
import MCP

public final class UrsusMCPServer: Sendable {
    private let service: BearService
    private let configuration: BearConfiguration
    private let selectedNoteTokenConfigured: Bool

    public init(
        service: BearService,
        configuration: BearConfiguration,
        selectedNoteTokenConfigured: Bool? = nil
    ) {
        self.service = service
        self.configuration = configuration
        self.selectedNoteTokenConfigured = selectedNoteTokenConfigured ?? BearSelectedNoteTokenResolver.configured()
    }

    public func makeServer() async -> Server {
        let server = Server(
            name: "ursus",
            version: "0.1.0",
            capabilities: .init(
                resources: .init(listChanged: false),
                tools: .init(listChanged: false)
            )
        )

        await registerHandlers(on: server)
        return server
    }

    private func registerHandlers(on server: Server) async {
        await server.withMethodHandler(ListResources.self) { _ in
            .init(resources: [])
        }

        await server.withMethodHandler(ListResourceTemplates.self) { _ in
            .init(templates: [])
        }

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: Self.toolCatalog(
                configuration: self.configuration,
                selectedNoteTokenConfigured: self.selectedNoteTokenConfigured
            ))
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                return try await self.handleToolCall(params)
            } catch {
                return .init(content: [.text(text: Self.renderError(error), annotations: nil, _meta: nil)], isError: true)
            }
        }
    }

    private func handleToolCall(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        if let toolName = BearToolName(rawValue: params.name), !configuration.isToolEnabled(toolName) {
            throw BearError.invalidInput("Bear tool '\(params.name)' is disabled in config.json.")
        }

        switch params.name {
        case "bear_find_notes":
            let operations = try requiredObjectArray(params.arguments, "operations").map(decodeFindNotesOperation)
            return try jsonResult(try service.findNotes(operations))

        case "bear_get_notes":
            let selectors = try await resolvedRequiredNoteSelectors(params.arguments)
            let location = try MCPArgumentDecoder.location(params.arguments)
            let includeAttachmentText = try MCPArgumentDecoder.optionalBool(params.arguments, "include_attachment_text") ?? false
            let notes = try service.getNotes(
                selectors: selectors,
                location: location,
                includeAttachmentText: includeAttachmentText
            )
            return try jsonResult(notes)

        case "bear_list_tags":
            let location = try MCPArgumentDecoder.location(params.arguments)
            let query = MCPArgumentDecoder.optionalString(params.arguments, "query")
            let underTag = MCPArgumentDecoder.optionalString(params.arguments, "under_tag")
            return try jsonResult(try service.listTags(location: location, query: query, underTag: underTag))

        case "bear_find_notes_by_tag":
            let operations = try requiredObjectArray(params.arguments, "operations").map(decodeFindNotesByTagOperation)
            return try jsonResult(try service.findNotesByTag(operations))

        case "bear_find_notes_by_inbox_tags":
            let operations = try requiredObjectArray(params.arguments, "operations").map(decodeFindNotesByInboxTagsOperation)
            return try jsonResult(try service.findNotesByInboxTags(operations))

        case "bear_create_backups":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedRequiredBackupNoteSelectors(operationObjects)
            let requests = resolvedNoteSelectors.map(CreateBackupRequest.init(noteID:))
            return try jsonResult(try await service.createBackups(requests))

        case "bear_list_backups":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedRequiredBackupNoteSelectors(operationObjects)
            let operations = zip(operationObjects, resolvedNoteSelectors).map { object, resolvedNoteSelector in
                ListBackupsOperation(
                    id: MCPArgumentDecoder.optionalString(object, "id"),
                    noteID: resolvedNoteSelector,
                    from: MCPArgumentDecoder.optionalString(object, "from"),
                    to: MCPArgumentDecoder.optionalString(object, "to"),
                    cursor: MCPArgumentDecoder.optionalString(object, "cursor")
                )
            }
            return try jsonResult(try await service.listBackups(operations))

        case "bear_compare_backup":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedRequiredBackupNoteSelectors(operationObjects)
            let operations = try zip(operationObjects, resolvedNoteSelectors).map { object, resolvedNoteSelector in
                CompareBackupOperation(
                    id: MCPArgumentDecoder.optionalString(object, "id"),
                    noteID: resolvedNoteSelector,
                    snapshotID: try requiredString(object, "snapshot_id")
                )
            }
            return try jsonResult(try await service.compareBackups(operations))

        case "bear_delete_backups":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedOptionalNoteSelectors(operationObjects)
            let requests = try zip(operationObjects, resolvedNoteSelectors).map { object, resolvedNoteSelector in
                DeleteBackupRequest(
                    noteID: resolvedNoteSelector,
                    snapshotID: MCPArgumentDecoder.optionalString(object, "snapshot_id"),
                    deleteAll: try MCPArgumentDecoder.optionalBool(object, "delete_all") ?? false
                )
            }
            return try jsonResult(try await service.deleteBackups(requests))

        case "bear_open_tag":
            let tag = try MCPArgumentDecoder.string(params.arguments, "tag")
            return try jsonResult(try await service.openTag(tag))

        case "bear_rename_tags":
            let requests = try requiredObjectArray(params.arguments, "operations").map { object in
                RenameTagRequest(
                    name: try requiredString(object, "name"),
                    newName: try requiredString(object, "new_name")
                )
            }
            return try jsonResult(try await service.renameTags(requests))

        case "bear_delete_tags":
            let requests = try requiredObjectArray(params.arguments, "operations").map { object in
                DeleteTagRequest(
                    name: try requiredString(object, "name")
                )
            }
            return try jsonResult(try await service.deleteTags(requests))

        case "bear_add_tags":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedRequiredNoteSelectors(operationObjects)
            let requests = try zip(operationObjects, resolvedNoteSelectors).map { object, resolvedNoteSelector in
                NoteTagsRequest(
                    noteID: resolvedNoteSelector,
                    tags: try requiredStringArray(object, "tags")
                )
            }
            return try jsonResult(try await service.addTags(requests))

        case "bear_remove_tags":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedRequiredNoteSelectors(operationObjects)
            let requests = try zip(operationObjects, resolvedNoteSelectors).map { object, resolvedNoteSelector in
                NoteTagsRequest(
                    noteID: resolvedNoteSelector,
                    tags: try requiredStringArray(object, "tags")
                )
            }
            return try jsonResult(try await service.removeTags(requests))

        case "bear_apply_template":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedRequiredNoteSelectors(operationObjects)
            let requests = zip(operationObjects, resolvedNoteSelectors).map { object, resolvedNoteSelector in
                ApplyTemplateRequest(
                    noteID: resolvedNoteSelector
                )
            }
            return try jsonResult(try await service.applyTemplate(requests))

        case "bear_create_notes":
            let defaults = BearPresentationOptions(
                openNote: configuration.createOpensNoteByDefault,
                newWindow: configuration.openUsesNewWindowByDefault,
                showWindow: true,
                edit: true
            )
            let requests = try requiredObjectArray(params.arguments, "operations").map { object in
                CreateNoteRequest(
                    title: try requiredString(object, "title"),
                    content: try requiredString(object, "content"),
                    tags: object["tags"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                    useOnlyRequestTags: try MCPArgumentDecoder.optionalBool(object, "use_only_request_tags"),
                    presentation: try MCPArgumentDecoder.createNotePresentation(object, defaults: defaults)
                )
            }
            return try jsonResult(try await service.createNotes(requests))

        case "bear_insert_text":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedRequiredNoteSelectors(operationObjects)
            let requests = try zip(operationObjects, resolvedNoteSelectors).map { object, resolvedNoteSelector in
                InsertTextRequest(
                    noteID: resolvedNoteSelector,
                    text: try requiredString(object, "text"),
                    position: try MCPArgumentDecoder.optionalPosition(object),
                    target: try MCPArgumentDecoder.relativeTextTarget(object)
                )
            }
            return try jsonResult(try await service.insertText(requests))

        case "bear_replace_content":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedRequiredNoteSelectors(operationObjects)
            let requests = try zip(operationObjects, resolvedNoteSelectors).map { object, resolvedNoteSelector in
                ReplaceContentRequest(
                    noteID: resolvedNoteSelector,
                    kind: try MCPArgumentDecoder.replaceContentKind(object),
                    oldString: object["old_string"]?.stringValue,
                    occurrence: try MCPArgumentDecoder.replaceStringOccurrence(object),
                    newString: try requiredPresentString(object, "new_string")
                )
            }
            return try jsonResult(try await service.replaceContent(requests))

        case "bear_add_files":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedRequiredNoteSelectors(operationObjects)
            let requests = try zip(operationObjects, resolvedNoteSelectors).map { object, resolvedNoteSelector in
                AddFileRequest(
                    noteID: resolvedNoteSelector,
                    filePath: try requiredString(object, "file_path"),
                    position: try MCPArgumentDecoder.optionalPosition(object),
                    target: try MCPArgumentDecoder.relativeTextTarget(object)
                )
            }
            return try jsonResult(try await service.addFiles(requests))

        case "bear_open_notes":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedRequiredNoteSelectors(operationObjects)
            let requests = try zip(operationObjects, resolvedNoteSelectors).map { object, resolvedNoteSelector in
                OpenNoteRequest(
                    noteID: resolvedNoteSelector,
                    presentation: try MCPArgumentDecoder.openNotePresentation(
                        object,
                        defaultNewWindow: configuration.openUsesNewWindowByDefault
                    )
                )
            }
            return try jsonResult(try await service.openNotes(requests))

        case "bear_archive_notes":
            let noteSelectors = try await resolvedRequiredNoteSelectors(params.arguments)
            return try jsonResult(try await service.archiveNotes(noteSelectors))

        case "bear_restore_notes":
            let operationObjects = try requiredObjectArray(params.arguments, "operations")
            let resolvedNoteSelectors = try await resolvedRequiredNoteSelectors(operationObjects)
            let requests = zip(operationObjects, resolvedNoteSelectors).map { object, resolvedNoteSelector in
                RestoreBackupRequest(
                    noteID: resolvedNoteSelector,
                    snapshotID: MCPArgumentDecoder.optionalString(object, "snapshot_id")
                )
            }
            return try jsonResult(try await service.restoreBackups(requests))

        default:
            throw BearError.invalidInput("Unknown Bear tool '\(params.name)'.")
        }
    }

    private func jsonResult<T: Encodable>(_ value: T) throws -> CallTool.Result {
        let encoder = BearJSON.makeEncoder()
        let data = try encoder.encode(value)
        let text = String(decoding: data, as: UTF8.self)
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private func requiredString(_ object: [String: Value], _ key: String) throws -> String {
        guard let value = object[key]?.stringValue, !value.isEmpty else {
            throw BearError.invalidInput("Missing required string argument '\(key)'.")
        }
        return value
    }

    private func requiredPresentString(_ object: [String: Value], _ key: String) throws -> String {
        guard let value = object[key]?.stringValue else {
            throw BearError.invalidInput("Missing required string argument '\(key)'.")
        }
        return value
    }

    private func requiredObjectArray(_ arguments: [String: Value]?, _ key: String) throws -> [[String: Value]] {
        guard let rawValue = arguments?[key], let rawArray = rawValue.arrayValue else {
            throw BearError.invalidInput("Missing required array argument '\(key)'.")
        }
        guard !rawArray.isEmpty else {
            throw BearError.invalidInput("`\(key)` must contain at least one operation object.")
        }

        var objects: [[String: Value]] = []
        objects.reserveCapacity(rawArray.count)

        for value in rawArray {
            guard let object = value.objectValue else {
                throw BearError.invalidInput("`\(key)` must contain only operation objects.")
            }
            objects.append(object)
        }

        return objects
    }

    private func requiredStringArray(_ object: [String: Value], _ key: String) throws -> [String] {
        guard let rawValue = object[key], let rawArray = rawValue.arrayValue else {
            throw BearError.invalidInput("Missing required array argument '\(key)'.")
        }

        var strings: [String] = []
        strings.reserveCapacity(rawArray.count)

        for value in rawArray {
            guard let string = value.stringValue else {
                throw BearError.invalidInput("`\(key)` must contain only strings.")
            }
            strings.append(string)
        }

        return strings
    }

    private func decodeFindNotesOperation(_ object: [String: Value]) throws -> FindNotesOperation {
        FindNotesOperation(
            id: MCPArgumentDecoder.optionalString(object, "id"),
            text: MCPArgumentDecoder.optionalString(object, "text"),
            textMode: try MCPArgumentDecoder.findTextMode(object),
            textNot: MCPArgumentDecoder.stringArray(object, "text_not"),
            searchFields: try MCPArgumentDecoder.findSearchFields(object),
            tagsAny: MCPArgumentDecoder.stringArray(object, "tags_any"),
            tagsAll: MCPArgumentDecoder.stringArray(object, "tags_all"),
            tagsNone: MCPArgumentDecoder.stringArray(object, "tags_none"),
            hasPinned: try MCPArgumentDecoder.optionalBool(object, "has_pinned"),
            hasTodos: try MCPArgumentDecoder.optionalBool(object, "has_todos"),
            hasAttachments: try MCPArgumentDecoder.optionalBool(object, "has_attachments"),
            hasTags: try MCPArgumentDecoder.optionalBool(object, "has_tags"),
            inboxTagsMode: try MCPArgumentDecoder.optionalFindTagMatchMode(object, key: "inbox_tags_mode"),
            dateField: try MCPArgumentDecoder.optionalFindDateField(object, key: "date_field"),
            from: MCPArgumentDecoder.optionalString(object, "from"),
            to: MCPArgumentDecoder.optionalString(object, "to"),
            location: try MCPArgumentDecoder.location(object),
            cursor: MCPArgumentDecoder.optionalString(object, "cursor")
        )
    }

    private func resolvedRequiredNoteSelectors(_ arguments: [String: Value]?) async throws -> [String] {
        try await service.resolveNoteTargets(requiredNoteTargets(arguments))
    }

    private func resolvedRequiredNoteSelectors(_ objects: [[String: Value]]) async throws -> [String] {
        let noteTargets = try objects.map(requiredNoteTarget)
        return try await service.resolveNoteTargets(noteTargets)
    }

    private func resolvedRequiredBackupNoteSelectors(_ objects: [[String: Value]]) async throws -> [String] {
        let noteTargets = try objects.map(requiredBackupNoteTarget)
        return try await service.resolveNoteTargets(noteTargets)
    }

    private func resolvedOptionalNoteSelectors(_ objects: [[String: Value]]) async throws -> [String?] {
        let noteTargets = try objects.map(optionalNoteTarget)
        let concreteTargets = noteTargets.compactMap { $0 }
        let resolvedTargets = try await service.resolveNoteTargets(concreteTargets)

        var iterator = resolvedTargets.makeIterator()
        return noteTargets.map { target in
            guard target != nil else {
                return nil
            }

            return iterator.next()
        }
    }

    private func requiredNoteTargets(_ arguments: [String: Value]?) throws -> [NoteTarget] {
        let selected = try MCPArgumentDecoder.optionalBool(arguments, "selected") ?? false
        let selectors = MCPArgumentDecoder.stringArray(arguments, "notes")
        let legacySelectors = MCPArgumentDecoder.stringArray(arguments, "note_ids")
        let allSelectors = selectors.isEmpty ? legacySelectors : selectors

        if selected && !allSelectors.isEmpty {
            throw BearError.invalidInput("`notes` and `selected` are mutually exclusive.")
        }

        if selected {
            return [.selected]
        }

        guard !allSelectors.isEmpty else {
            throw BearError.invalidInput("Missing required array argument 'notes'.")
        }

        return allSelectors.map(NoteTarget.selector)
    }

    private func requiredNoteTarget(_ object: [String: Value]) throws -> NoteTarget {
        guard let noteTarget = try optionalNoteTarget(object) else {
            throw BearError.invalidInput("Provide exactly one of `note` or `selected: true`.")
        }

        return noteTarget
    }

    private func requiredBackupNoteTarget(_ object: [String: Value]) throws -> NoteTarget {
        guard let noteTarget = try optionalBackupNoteTarget(object) else {
            throw BearError.invalidInput("Provide exactly one of `note` or `selected: true`.")
        }

        return noteTarget
    }

    private func optionalBackupNoteTarget(_ object: [String: Value]) throws -> NoteTarget? {
        let note = object["note"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelector = note?.isEmpty == false ? note : nil
        let selected = try MCPArgumentDecoder.optionalBool(object, "selected") ?? false

        if selected && normalizedSelector != nil {
            throw BearError.invalidInput("`note` and `selected` are mutually exclusive.")
        }

        if selected {
            guard selectedNoteTokenConfigured else {
                throw BearError.invalidInput("Selected-note targeting requires a configured Bear API token.")
            }
            return .selected
        }

        guard let normalizedSelector else {
            return nil
        }

        return .selector(normalizedSelector)
    }

    private func optionalNoteTarget(_ object: [String: Value]) throws -> NoteTarget? {
        let note = object["note"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyNoteID = object["note_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelector: String? = {
            if let note, !note.isEmpty {
                return note
            }
            if let legacyNoteID, !legacyNoteID.isEmpty {
                return legacyNoteID
            }
            return nil
        }()
        let selected = try MCPArgumentDecoder.optionalBool(object, "selected") ?? false

        if selected && normalizedSelector != nil {
            throw BearError.invalidInput("`note` and `selected` are mutually exclusive.")
        }

        if selected {
            guard selectedNoteTokenConfigured else {
                throw BearError.invalidInput("Selected-note targeting requires a configured Bear API token.")
            }
            return .selected
        }

        guard let normalizedSelector else {
            return nil
        }

        return .selector(normalizedSelector)
    }

    private func decodeFindNotesByTagOperation(_ object: [String: Value]) throws -> FindNotesByTagOperation {
        FindNotesByTagOperation(
            id: MCPArgumentDecoder.optionalString(object, "id"),
            tags: try requiredStringArray(object, "tags"),
            tagMatch: try MCPArgumentDecoder.findTagMatchMode(object, key: "tag_match"),
            location: try MCPArgumentDecoder.location(object),
            cursor: MCPArgumentDecoder.optionalString(object, "cursor")
        )
    }

    private func decodeFindNotesByInboxTagsOperation(_ object: [String: Value]) throws -> FindNotesByInboxTagsOperation {
        FindNotesByInboxTagsOperation(
            id: MCPArgumentDecoder.optionalString(object, "id"),
            match: try MCPArgumentDecoder.findTagMatchMode(object, key: "match"),
            location: try MCPArgumentDecoder.location(object),
            cursor: MCPArgumentDecoder.optionalString(object, "cursor")
        )
    }

    private static func renderError(_ error: any Swift.Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    static func toolCatalog(
        configuration: BearConfiguration,
        selectedNoteTokenConfigured: Bool? = nil
    ) -> [Tool] {
        ToolCatalog.makeTools(
            configuration: configuration,
            selectedNoteSupported: selectedNoteTokenConfigured ?? BearSelectedNoteTokenResolver.configured()
        ).filter { tool in
            guard let toolName = BearToolName(rawValue: tool.name) else {
                return true
            }

            return configuration.isToolEnabled(toolName)
        }
    }
}

private enum ToolCatalog {
    static func makeTools(configuration: BearConfiguration, selectedNoteSupported: Bool) -> [Tool] {
        [
            batchedDiscoveryTool(
                name: "bear_find_notes",
                description: "Find Bear notes with text, tag, inbox-tag, and date filters and return compact summaries. Use `bear_list_tags` first when the exact tag name is uncertain. Discovery excludes trash.",
                operationProperties: findNotesOperationProperties(configuration: configuration),
                required: []
            ),
            Tool(
                name: "bear_get_notes",
                description: "Fetch full Bear note records for one or more selectors. Use this only when current note content, attachment metadata, or other full-note fields are needed. Attachment OCR/search text is omitted unless `include_attachment_text` is `true`. Do not call it only to resolve a selector before a note-targeting mutation; those tools already resolve selectors server-side. Selectors are matched as exact note ids first, then exact case-insensitive titles.\(selectedNoteDescriptionSuffix(selectedNoteSupported))",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object(getNotesInputProperties(configuration: configuration, selectedNoteSupported: selectedNoteSupported)),
                    "required": .array(getNotesRequiredFields(selectedNoteSupported: selectedNoteSupported).map(Value.string)),
                ])
            ),
            Tool(
                name: "bear_list_tags",
                description: "List Bear tags for the selected note location. Use this as the discovery step when another tag tool needs a canonical tag name. `query` filters tag names by case-insensitive substring, and `under_tag` returns descendants under a parent tag path.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "location": .object([
                            "type": .string("string"),
                            "enum": .array([.string("notes"), .string("archive")]),
                            "description": .string(omitUnlessDescription(defaultClause: "the default `notes`", overrideWhen: "the user explicitly asks for archived tags")),
                        ]),
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Optional case-insensitive substring filter for tag names. Wrapped or unwrapped tag text is normalized before searching."),
                        ]),
                        "under_tag": .object([
                            "type": .string("string"),
                            "description": .string("Optional parent tag path. Returns descendant tags under the normalized parent path, excluding the parent tag itself."),
                        ]),
                    ]),
                ])
            ),
            batchedDiscoveryTool(
                name: "bear_find_notes_by_tag",
                description: "Find Bear notes by one or more Bear tags and return compact summaries. Use `bear_list_tags` first when the exact tag name is uncertain. Use `bear_open_tag` instead when the goal is UI navigation to one tag. Discovery excludes trash.",
                operationProperties: findNotesByTagOperationProperties(configuration: configuration),
                required: ["tags"]
            ),
            batchedDiscoveryTool(
                name: "bear_find_notes_by_inbox_tags",
                description: "Find Bear notes by the configured inbox tags and return compact summaries. Current inbox tags: \(formattedTagList(configuration.inboxTags)). Discovery excludes trash. Each operation object may be empty to use the configured inbox tags with default matching and note location.",
                operationProperties: findNotesByInboxTagsOperationProperties(configuration: configuration),
                required: []
            ),
            batchedMutationTool(
                name: "bear_create_backups",
                description: "Create one or more saved backup snapshots for Bear notes. Each operation targets exactly one note via `note` or `selected: true`, reuses the same manual capture flow as the CLI, and returns compact backup receipts.",
                operationProperties: [
                    "note": noteSelectorProperty(selectedNoteSupported: selectedNoteSupported),
                ].merging(selectedNoteOperationProperty(selectedNoteSupported: selectedNoteSupported), uniquingKeysWith: { current, _ in current }),
                required: requiredNoteFields(selectedNoteSupported: selectedNoteSupported),
                presentationProperties: [:]
            ),
            batchedDiscoveryTool(
                name: "bear_list_backups",
                description: "List saved backup snapshots for one Bear note and return compact note-scoped summaries with pagination. Optional `from` and `to` filters apply to the backup creation timestamp. Use this before `bear_restore_notes` so snapshot restores are explicit rather than blind.",
                operationProperties: backupListOperationProperties(selectedNoteSupported: selectedNoteSupported),
                required: requiredNoteFields(selectedNoteSupported: selectedNoteSupported)
            ),
            batchedDiscoveryTool(
                name: "bear_compare_backup",
                description: "Compare one saved backup snapshot against the current Bear note without returning full note bodies by default. Each operation requires exactly one note target plus `snapshot_id`, and returns compact metadata plus bounded diff hunks.",
                operationProperties: [
                    "id": .object(["type": .string("string")]),
                    "note": noteSelectorProperty(selectedNoteSupported: selectedNoteSupported),
                    "snapshot_id": .object([
                        "type": .string("string"),
                        "description": .string("Required backup snapshot identifier to compare against the current note."),
                    ]),
                ].merging(selectedNoteOperationProperty(selectedNoteSupported: selectedNoteSupported), uniquingKeysWith: { current, _ in current }),
                required: requiredNoteFields(selectedNoteSupported: selectedNoteSupported, trailing: ["snapshot_id"])
            ),
            batchedMutationTool(
                name: "bear_delete_backups",
                description: "Delete one or more saved backup snapshots. Use `bear_list_backups` first so deletion targets are explicit. Each operation uses exactly one mode. Provide `snapshot_id` to delete one exact backup. Delete all backups for one note by providing exactly one note target plus `delete_all: true`, and omitting `snapshot_id`.",
                operationProperties: [
                    "note": optionalNoteSelectorProperty(configuration: configuration, selectedNoteSupported: selectedNoteSupported, descriptionPrefix: "Use this only for note-scoped delete-all mode, or to scope a `snapshot_id` delete to one note. In delete-all mode, provide exactly one of `note` or `selected: true`."),
                    "snapshot_id": .object([
                        "type": .string("string"),
                        "description": .string("Delete one exact backup by snapshot id. This is the minimal single-backup mode. Omit `snapshot_id` when using note-scoped `delete_all: true`."),
                    ]),
                    "delete_all": .object([
                        "type": .string("boolean"),
                        "description": .string("Use this only for note-scoped bulk delete mode to remove all saved backups for that note. Set `true` only with exactly one note target, and omit `snapshot_id` in that mode."),
                    ]),
                ].merging(
                    selectedNoteOperationProperty(
                        selectedNoteSupported: selectedNoteSupported,
                        description: "Alternative to `note` for note-scoped delete-all mode, or to scope a `snapshot_id` delete to the currently selected Bear note. In delete-all mode, provide exactly one of `note` or `selected: true`. Set `true` only when the user explicitly means the currently selected Bear note."
                    ),
                    uniquingKeysWith: { current, _ in current }
                ),
                required: [],
                presentationProperties: [:]
            ),
            Tool(
                name: "bear_open_tag",
                description: "Open Bear's UI for a single known tag name. Use `bear_list_tags` first if the exact tag name is uncertain. Use `bear_find_notes_by_tag` instead when the goal is to read compact note summaries rather than navigate the Bear UI.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "tag": .object([
                            "type": .string("string"),
                            "description": .string("Required canonical tag name to open in Bear."),
                        ]),
                    ]),
                    "required": .array([.string("tag")]),
                ])
            ),
            batchedMutationTool(
                name: "bear_rename_tags",
                description: "Rename one or more Bear tags across the entire Bear app. This is a global tag rename, not a single-note edit. Use `bear_list_tags` first to confirm the existing canonical tag names.",
                operationProperties: [
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Existing canonical tag name to rename across Bear."),
                    ]),
                    "new_name": .object([
                        "type": .string("string"),
                        "description": .string("Replacement canonical tag name to apply across Bear."),
                    ]),
                ],
                required: ["name", "new_name"],
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_delete_tags",
                description: "Delete one or more Bear tags across the entire Bear app. This removes the tag globally rather than only from one note. Use `bear_list_tags` first to confirm the exact canonical tag names.",
                operationProperties: [
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Existing canonical tag name to delete across Bear."),
                    ]),
                ],
                required: ["name"],
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_add_tags",
                description: "Add one or more tags to specific Bear notes. This affects only the targeted notes; it does not rename or delete tags globally. Do not call `bear_get_notes` only to resolve the note selector; this tool already resolves selectors server-side. Use `bear_get_notes` first only when the exact current tags are actually needed.",
                operationProperties: [
                    "note": noteSelectorProperty(selectedNoteSupported: selectedNoteSupported),
                    "tags": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Required tags to add to this one note. Inputs may be wrapped or unwrapped; tags are normalized before writing."),
                    ]),
                ].merging(selectedNoteOperationProperty(selectedNoteSupported: selectedNoteSupported), uniquingKeysWith: { current, _ in current }),
                required: requiredNoteFields(selectedNoteSupported: selectedNoteSupported, trailing: ["tags"]),
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_remove_tags",
                description: "Remove one or more literal tags from specific Bear notes without deleting the tag globally from Bear. Do not call `bear_get_notes` only to resolve the note selector; this tool already resolves selectors server-side. Use `bear_get_notes` first only when the exact current literal tags are actually needed. The server removes matching literal tag tokens anywhere in the editable note body, including template tag slots when present, and then cleans up whitespace.",
                operationProperties: [
                    "note": noteSelectorProperty(selectedNoteSupported: selectedNoteSupported),
                    "tags": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Required tags to remove from this one note only. Inputs may be wrapped or unwrapped; tags are normalized before matching."),
                    ]),
                ].merging(selectedNoteOperationProperty(selectedNoteSupported: selectedNoteSupported), uniquingKeysWith: { current, _ in current }),
                required: requiredNoteFields(selectedNoteSupported: selectedNoteSupported, trailing: ["tags"]),
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_apply_template",
                description: "Apply the current template to one or more Bear notes and normalize tag-only clusters into the template `{{tags}}` slot. It preserves inline prose hashtags, returns compact receipts, and fails clearly if `template.md` is missing or invalid.",
                operationProperties: [
                    "note": noteSelectorProperty(selectedNoteSupported: selectedNoteSupported),
                ].merging(selectedNoteOperationProperty(selectedNoteSupported: selectedNoteSupported), uniquingKeysWith: { current, _ in current }),
                required: requiredNoteFields(selectedNoteSupported: selectedNoteSupported),
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_create_notes",
                description: "Create one or more Bear notes. `content` must be a non-empty string. Pass `tags` only for tags the user explicitly requested. Defaults: `open_note` = \(formattedBool(configuration.createOpensNoteByDefault)); `new_window` = \(formattedBool(configuration.openUsesNewWindowByDefault)) when opened; configured inbox tags = \(formattedTagList(configuration.inboxTags)); omitted tag-merge behavior \(formattedCreateTagMergeBehavior(configuration)). If the user only asks to add a tag, pass `tags` and omit `use_only_request_tags`. If the user explicitly says whether the note should open, send `open_note` with that exact intent.",
                operationProperties: [
                    "title": .object(["type": .string("string")]),
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("Required non-empty editable note body. Do not repeat `title` inside `content` or prepend a heading that duplicates it."),
                    ]),
                    "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                    "use_only_request_tags": .object([
                        "type": .string("boolean"),
                        "description": .string("\(omitUnlessDescription(defaultClause: "the current tag-merge behavior", overrideWhen: "the user explicitly asks to change tag merging for this request")) `true` uses only the supplied request tags. `false` appends configured inbox tags. Omitted behavior: \(formattedCreateTagMergeBehavior(configuration)). If the user only asks to add specific tags, pass `tags` and omit `use_only_request_tags`."),
                    ]),
                    "open_note": optionalPresentationBoolean(description: "\(omitUnlessDescription(defaultClause: "the default \(formattedBool(configuration.createOpensNoteByDefault))", overrideWhen: "the user explicitly states whether the created note should open")) `true` forces open and `false` forces closed."),
                    "new_window": optionalPresentationBoolean(description: omitUnlessDescription(defaultClause: "the default when the created note is opened: \(formattedBool(configuration.openUsesNewWindowByDefault))", overrideWhen: "the user explicitly asks for a separate or floating Bear window")),
                ],
                required: ["title", "content"],
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_insert_text",
                description: "Insert text into one or more Bear notes. `note` accepts a selector matched as exact note id first, then exact case-insensitive title. For each operation, use exactly one note target: `note` or `selected: true`. Provide `text`. Use exactly one insertion mode: relative `target`, or `position`/default-position mode. If `target` is present, omit `position` and insert before or after a matching heading or exact editable-content string. If `target` is omitted, `position` controls top or bottom placement; if `position` is also omitted, `position` = `\(configuration.defaultInsertPosition.rawValue)`.",
                operationProperties: [
                    "note": noteSelectorProperty(selectedNoteSupported: selectedNoteSupported),
                    "text": .object([
                        "type": .string("string"),
                        "description": .string("Required text to insert into the target note."),
                    ]),
                    "position": .object([
                        "type": .string("string"),
                        "enum": .array([.string("top"), .string("bottom")]),
                        "description": .string("Use this only when `target` is omitted. Set `top` or `bottom` to control placement in editable content. Omit `position` when `target` is present. Omit to use the current session default `\(configuration.defaultInsertPosition.rawValue)` when no `target` is provided."),
                    ]),
                    "target": relativeTargetProperty(),
                ].merging(selectedNoteOperationProperty(selectedNoteSupported: selectedNoteSupported), uniquingKeysWith: { current, _ in current }),
                required: requiredNoteFields(selectedNoteSupported: selectedNoteSupported, trailing: ["text"]),
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_replace_content",
                description: "Replace Bear note content while preserving note structure. For each operation, provide exactly one note target: `note` or `selected: true`. Provide `kind` and `new_string`. For `kind: string`, also provide `old_string` and `occurrence`. For `kind: title` and `kind: body`, omit `old_string` and `occurrence`. Do not call `bear_get_notes` only to resolve the note selector; this tool already resolves selectors server-side. Use `bear_get_notes` first when the exact current text is not already known.",
                operationProperties: [
                    "note": noteSelectorProperty(selectedNoteSupported: selectedNoteSupported),
                    "kind": .object([
                        "type": .string("string"),
                        "enum": .array([.string("title"), .string("body"), .string("string")]),
                        "description": .string("Required replacement kind. `title` replaces only the note title. `body` replaces the full editable body. `string` replaces exact text within the editable body only."),
                    ]),
                    "old_string": .object([
                        "type": .string("string"),
                        "description": .string("Use this only with `kind: string`; it is required in that mode. Pass the exact existing text to match within the editable body. Omit `old_string` for `kind: title` and `kind: body`."),
                    ]),
                    "occurrence": .object([
                        "type": .string("string"),
                        "enum": .array([.string("one"), .string("all")]),
                        "description": .string("Use this only with `kind: string`; it is required in that mode. `one` replaces one exact match. `all` replaces every exact match in the editable body. Omit `occurrence` for `kind: title` and `kind: body`."),
                    ]),
                    "new_string": .object([
                        "type": .string("string"),
                        "description": .string("Required replacement text. For `kind: title`, this is the full new title and must not be empty. For `kind: body`, this is the full replacement editable body and may be empty. For `kind: string`, this is the replacement for matched text and may be empty."),
                    ]),
                ].merging(selectedNoteOperationProperty(selectedNoteSupported: selectedNoteSupported), uniquingKeysWith: { current, _ in current }),
                required: requiredNoteFields(selectedNoteSupported: selectedNoteSupported, trailing: ["kind", "new_string"]),
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_add_files",
                description: "Attach one or more local files to Bear notes. `note` accepts a selector matched as exact note id first, then exact case-insensitive title. For each operation, use exactly one note target: `note` or `selected: true`. Provide `file_path`. Use exactly one insertion mode: relative `target`, or `position`/default-position mode. If `target` is present, omit `position` and insert before or after a matching heading or exact editable-content string. If `target` is omitted, `position` controls top or bottom placement; if `position` is also omitted, `position` = `\(configuration.defaultInsertPosition.rawValue)`.",
                operationProperties: [
                    "note": noteSelectorProperty(selectedNoteSupported: selectedNoteSupported),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string("Required local file path to attach to the target note."),
                    ]),
                    "position": .object([
                        "type": .string("string"),
                        "enum": .array([.string("top"), .string("bottom")]),
                        "description": .string("Use this only when `target` is omitted. Set `top` or `bottom` to control placement in editable content. Omit `position` when `target` is present. Omit to use the current session default `\(configuration.defaultInsertPosition.rawValue)` when no `target` is provided."),
                    ]),
                    "target": relativeTargetProperty(),
                ].merging(selectedNoteOperationProperty(selectedNoteSupported: selectedNoteSupported), uniquingKeysWith: { current, _ in current }),
                required: requiredNoteFields(selectedNoteSupported: selectedNoteSupported, trailing: ["file_path"]),
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_open_notes",
                description: "Open Bear notes in the Bear UI. `note` accepts a selector matched as exact note id first, then exact case-insensitive title; ambiguous title matches must be disambiguated with the note id. Default: `new_window` = \(formattedBool(configuration.openUsesNewWindowByDefault)).",
                operationProperties: [
                    "note": noteSelectorProperty(selectedNoteSupported: selectedNoteSupported),
                    "new_window": optionalPresentationBoolean(description: omitUnlessDescription(defaultClause: "the default \(formattedBool(configuration.openUsesNewWindowByDefault))", overrideWhen: "the user explicitly asks for a separate or floating Bear window")),
                ].merging(selectedNoteOperationProperty(selectedNoteSupported: selectedNoteSupported), uniquingKeysWith: { current, _ in current }),
                required: requiredNoteFields(selectedNoteSupported: selectedNoteSupported),
                presentationProperties: [:]
            ),
            Tool(
                name: "bear_archive_notes",
                description: "Archive one or more Bear notes. `notes` accepts selectors matched as exact note ids first, then exact case-insensitive titles; ambiguous title matches must be disambiguated with the note id.\(selectedNoteDescriptionSuffix(selectedNoteSupported))",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object(archiveNotesInputProperties(selectedNoteSupported: selectedNoteSupported)),
                    "required": .array(archiveNotesRequiredFields(selectedNoteSupported: selectedNoteSupported).map(Value.string)),
                ])
            ),
            batchedMutationTool(
                name: "bear_restore_notes",
                description: "Restore one or more Bear notes from saved backup snapshots. Use `bear_list_backups` first when you need to inspect available snapshots before restoring. If `snapshot_id` is omitted, the most recent backup for that note is restored.",
                operationProperties: [
                    "note": noteSelectorProperty(selectedNoteSupported: selectedNoteSupported),
                    "snapshot_id": .object([
                        "type": .string("string"),
                        "description": .string("Optional backup snapshot identifier. Omit to restore the most recent snapshot for the selected note."),
                    ]),
                ].merging(selectedNoteOperationProperty(selectedNoteSupported: selectedNoteSupported), uniquingKeysWith: { current, _ in current }),
                required: requiredNoteFields(selectedNoteSupported: selectedNoteSupported),
                presentationProperties: [:]
            ),
        ]
    }

    private static func batchedDiscoveryTool(
        name: String,
        description: String,
        operationProperties: [String: Value],
        required: [String]
    ) -> Tool {
        Tool(
            name: name,
            description: batchedToolDescription(description),
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "operations": .object([
                        "type": .string("array"),
                        "description": .string("Required non-empty array of operation objects."),
                        "minItems": .int(1),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object(operationProperties),
                            "required": .array(required.map(Value.string)),
                        ]),
                    ]),
                ]),
                "required": .array([.string("operations")]),
            ])
        )
    }

    private static func findNotesOperationProperties(configuration: BearConfiguration) -> [String: Value] {
        discoveryOperationProperties([
            "id": .object(["type": .string("string")]),
            "text": .object([
                "type": .string("string"),
                "description": .string("Optional text to find inside note titles, bodies, or attachments."),
            ]),
            "text_mode": .object([
                "type": .string("string"),
                "enum": .array([.string("substring"), .string("any_terms"), .string("all_terms")]),
            ]),
            "text_not": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
            ]),
            "search_fields": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("string"),
                    "enum": .array([.string("title"), .string("body"), .string("attachments")]),
                ]),
            ]),
            "tags_any": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
            ]),
            "tags_all": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
            ]),
            "tags_none": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
            ]),
            "has_pinned": .object([
                "type": .string("boolean"),
                "description": .string("Optional presence filter. Set true to return only pinned notes, or false to return only unpinned notes."),
            ]),
            "has_todos": .object([
                "type": .string("boolean"),
                "description": .string("Optional presence filter over open todos only. Set true to require at least one open todo, or false to require none."),
            ]),
            "has_attachments": .object([
                "type": .string("boolean"),
                "description": .string("Optional presence filter. Set true to return only notes with attachments, or false to return only notes without attachments."),
            ]),
            "has_tags": .object([
                "type": .string("boolean"),
                "description": .string("Optional presence filter. Set true to return only tagged notes, or false to return only notes without tags."),
            ]),
            "inbox_tags_mode": .object([
                "type": .string("string"),
                "enum": .array([.string("any"), .string("all")]),
                "description": .string("Optional inbox-tag filter against the current configured inbox tags \(formattedTagList(configuration.inboxTags))."),
            ]),
            "date_field": .object([
                "type": .string("string"),
                "enum": .array([.string("created_at"), .string("modified_at")]),
            ]),
            "from": .object([
                "type": .string("string"),
                "description": .string("Optional inclusive start date bound. Accepts ISO 8601, YYYY-MM-DD, or supported past/present natural-language phrases such as 'last week'."),
            ]),
            "to": .object([
                "type": .string("string"),
                "description": .string("Optional inclusive end date bound. Accepts ISO 8601, YYYY-MM-DD, or supported past/present natural-language phrases such as 'today'."),
            ]),
        ])
    }

    private static func findNotesByTagOperationProperties(configuration: BearConfiguration) -> [String: Value] {
        discoveryOperationProperties([
            "id": .object(["type": .string("string")]),
            "tags": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
            ]),
            "tag_match": .object([
                "type": .string("string"),
                "enum": .array([.string("any"), .string("all")]),
            ]),
        ])
    }

    private static func findNotesByInboxTagsOperationProperties(configuration: BearConfiguration) -> [String: Value] {
        discoveryOperationProperties([
            "id": .object(["type": .string("string")]),
            "match": .object([
                "type": .string("string"),
                "enum": .array([.string("any"), .string("all")]),
                "description": .string("Optional matching mode over the current configured inbox tags \(formattedTagList(configuration.inboxTags))."),
            ]),
        ])
    }

    private static func backupListOperationProperties(selectedNoteSupported: Bool) -> [String: Value] {
        var properties: [String: Value] = [
            "id": .object(["type": .string("string")]),
            "note": noteSelectorProperty(selectedNoteSupported: selectedNoteSupported),
            "from": .object([
                "type": .string("string"),
                "description": .string("Optional inclusive start date bound for the backup creation timestamp. Accepts ISO 8601, YYYY-MM-DD, or supported past/present natural-language phrases such as 'today'."),
            ]),
            "to": .object([
                "type": .string("string"),
                "description": .string("Optional inclusive end date bound for the backup creation timestamp. Accepts ISO 8601, YYYY-MM-DD, or supported past/present natural-language phrases such as 'today'."),
            ]),
            "cursor": .object([
                "type": .string("string"),
                "description": .string("Optional opaque pagination cursor returned by a previous backup page. Omit for the first page and pass back `nextCursor` to continue with the same note-scoped date-filtered query and the configured server page size."),
            ]),
        ]

        if supportsSelectedNote(selectedNoteSupported) {
            properties["selected"] = selectedNoteProperty(
                selectedNoteSupported: selectedNoteSupported,
                description: "Alternative to `note`. Set `true` only when the user explicitly means the currently selected Bear note."
            )
        }

        return properties
    }

    private static func discoveryOperationProperties(_ base: [String: Value]) -> [String: Value] {
        var properties = base
        properties["location"] = .object([
            "type": .string("string"),
            "enum": .array([.string("notes"), .string("archive")]),
            "description": .string(omitUnlessDescription(defaultClause: "the default `notes`", overrideWhen: "the user explicitly asks for archived notes")),
        ])
        properties["cursor"] = .object([
            "type": .string("string"),
            "description": .string("Optional opaque pagination cursor returned by a previous discovery page. Omit for the first page and pass back `nextCursor` to continue with the configured server defaults."),
        ])
        return properties
    }

    private static func batchedMutationTool(
        name: String,
        description: String,
        operationProperties: [String: Value],
        required: [String],
        presentationProperties: [String: Value] = [:]
    ) -> Tool {
        return Tool(
            name: name,
            description: batchedToolDescription(description),
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "operations": .object([
                        "type": .string("array"),
                        "description": .string("Required non-empty array of operation objects."),
                        "minItems": .int(1),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object(operationProperties.merging(presentationProperties, uniquingKeysWith: { current, _ in current })),
                            "required": .array(required.map(Value.string)),
                        ]),
                    ]),
                ]),
                "required": .array([.string("operations")]),
            ])
        )
    }

    private static func batchedToolDescription(_ description: String) -> String {
        "\(description) `operations` must be a non-empty array of operation objects."
    }

    private static func optionalPresentationBoolean(description: String) -> Value {
        .object([
            "type": .string("boolean"),
            "description": .string(description),
        ])
    }

    private static func noteSelectorProperty(selectedNoteSupported: Bool) -> Value {
        .object([
            "type": .string("string"),
            "description": .string("\(supportsSelectedNote(selectedNoteSupported) ? "Use this to target one note by exact note id or exact case-insensitive title across notes and archive. Use exactly one of `note` or `selected: true`. " : "Use this to target one note by exact note id or exact case-insensitive title across notes and archive. This field is required. ")If multiple titles match, use the note id. Do not call `bear_get_notes` only to resolve this selector; note-targeting tools already resolve selectors server-side."),
        ])
    }

    private static func optionalNoteSelectorProperty(configuration: BearConfiguration, selectedNoteSupported: Bool, descriptionPrefix: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string("\(descriptionPrefix) Use this to target one note by exact note id or exact case-insensitive title. If multiple titles match, use the note id. Do not call `bear_get_notes` only to resolve this selector; note-targeting tools already resolve selectors server-side."),
        ])
    }

    private static func selectedNoteProperty(selectedNoteSupported: Bool, description: String? = nil) -> Value {
        return .object([
            "type": .string("boolean"),
            "description": .string(description ?? "Alternative to `note`. Set `true` only when the user explicitly means the currently selected Bear note."),
        ])
    }

    private static func selectedNoteOperationProperty(selectedNoteSupported: Bool, description: String? = nil) -> [String: Value] {
        guard supportsSelectedNote(selectedNoteSupported) else {
            return [:]
        }

        return ["selected": selectedNoteProperty(selectedNoteSupported: selectedNoteSupported, description: description)]
    }

    private static func relativeTargetProperty() -> Value {
        .object([
            "type": .string("object"),
            "description": .string("Use this insertion mode instead of `position`. Provide `text` and `placement` to insert before or after a matching heading or exact editable-content string. Omit `position` when `target` is present."),
            "properties": .object([
                "text": .object([
                    "type": .string("string"),
                    "description": .string("Required target text. For `target_kind: heading`, provide the visible heading text without needing to include Markdown `#` markers. For `target_kind: string`, pass the exact editable-content string to match."),
                ]),
                "target_kind": .object([
                    "type": .string("string"),
                    "enum": .array([.string("heading"), .string("string")]),
                    "description": .string("Optional target kind. Omitted defaults to `string`. Use `heading` for heading-title matching inside editable content."),
                ]),
                "placement": .object([
                    "type": .string("string"),
                    "enum": .array([.string("before"), .string("after")]),
                    "description": .string("Required relative placement for the insertion target."),
                ]),
            ]),
            "required": .array([.string("text"), .string("placement")]),
        ])
    }

    private static func omitUnlessDescription(defaultClause: String, overrideWhen: String) -> String {
        "Optional. Omit to use \(defaultClause). Do not send unless \(overrideWhen)."
    }

    private static func formattedBool(_ value: Bool) -> String {
        value ? "`true`" : "`false`"
    }

    private static func supportsSelectedNote(_ selectedNoteSupported: Bool) -> Bool {
        selectedNoteSupported
    }

    private static func selectedNoteDescriptionSuffix(_ selectedNoteSupported: Bool) -> String {
        guard supportsSelectedNote(selectedNoteSupported) else {
            return ""
        }

        return " As an alternative to explicit selectors, pass `selected: true` to target the currently selected Bear note."
    }

    private static func requiredNoteFields(selectedNoteSupported: Bool, trailing: [String] = []) -> [String] {
        supportsSelectedNote(selectedNoteSupported) ? trailing : ["note"] + trailing
    }

    private static func getNotesInputProperties(configuration: BearConfiguration, selectedNoteSupported: Bool) -> [String: Value] {
        var properties: [String: Value] = [
            "notes": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string("\(supportsSelectedNote(selectedNoteSupported) ? "Use this to target one or more notes by exact note id or exact case-insensitive title. Provide exactly one of `notes` or `selected: true`. " : "Use this to target one or more notes by exact note id or exact case-insensitive title. This field is required. ")Selectors are matched as exact note ids first, then exact case-insensitive titles."),
            ]),
            "location": .object([
                "type": .string("string"),
                "enum": .array([.string("notes"), .string("archive")]),
                "description": .string(omitUnlessDescription(defaultClause: "the default `notes`", overrideWhen: "the user explicitly asks for archived notes")),
            ]),
            "include_attachment_text": .object([
                "type": .string("boolean"),
                "description": .string("Optional. Omit to use the default `false`. Set `true` to include attachment OCR/search text in `attachments[].searchText`; otherwise full fetch returns attachment metadata only."),
            ]),
        ]

        if supportsSelectedNote(selectedNoteSupported) {
            properties["selected"] = selectedNoteProperty(
                selectedNoteSupported: selectedNoteSupported,
                description: "Alternative to `notes`. Set `true` only when the user explicitly means the currently selected Bear note."
            )
        }

        return properties
    }

    private static func getNotesRequiredFields(selectedNoteSupported: Bool) -> [String] {
        supportsSelectedNote(selectedNoteSupported) ? [] : ["notes"]
    }

    private static func archiveNotesInputProperties(selectedNoteSupported: Bool) -> [String: Value] {
        var properties: [String: Value] = [
            "notes": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string("\(supportsSelectedNote(selectedNoteSupported) ? "Use this to target one or more notes by exact note id or exact case-insensitive title. Provide exactly one of `notes` or `selected: true`. " : "Use this to target one or more notes by exact note id or exact case-insensitive title. This field is required. ")Each selector is matched as exact note id first, then exact case-insensitive title across notes and archive. If a title matches multiple notes, use the note id instead."),
            ]),
        ]

        if supportsSelectedNote(selectedNoteSupported) {
            properties["selected"] = selectedNoteProperty(
                selectedNoteSupported: selectedNoteSupported,
                description: "Alternative to `notes`. Set `true` only when the user explicitly means the currently selected Bear note."
            )
        }

        return properties
    }

    private static func archiveNotesRequiredFields(selectedNoteSupported: Bool) -> [String] {
        supportsSelectedNote(selectedNoteSupported) ? [] : ["notes"]
    }

    private static func formattedTagList(_ tags: [String]) -> String {
        guard !tags.isEmpty else {
            return "none"
        }
        return tags.map { "`\($0)`" }.joined(separator: ", ")
    }

    private static func formattedCreateTagMergeBehavior(_ configuration: BearConfiguration) -> String {
        guard configuration.createAddsInboxTagsByDefault else {
            return "uses only request tags unless explicitly overridden"
        }

        switch configuration.tagsMergeMode {
        case .append:
            return "appends configured inbox tags to request tags"
        case .replace:
            return "uses request tags when any are supplied, otherwise falls back to configured inbox tags"
        }
    }
}
