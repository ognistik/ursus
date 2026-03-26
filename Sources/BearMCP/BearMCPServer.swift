import BearApplication
import BearCore
import Foundation
import MCP

public final class BearMCPServer: Sendable {
    private let service: BearService
    private let configuration: BearConfiguration

    public init(service: BearService, configuration: BearConfiguration) {
        self.service = service
        self.configuration = configuration
    }

    public func makeServer() async -> Server {
        let server = Server(
            name: "bear",
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
            .init(tools: Self.toolCatalog(configuration: self.configuration))
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                return try await self.handleToolCall(params)
            } catch {
                return .init(content: [.text(Self.renderError(error))], isError: true)
            }
        }
    }

    private func handleToolCall(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "bear_find_notes":
            let operations = try requiredObjectArray(params.arguments, "operations").map(decodeFindNotesOperation)
            return try jsonResult(try service.findNotes(operations))

        case "bear_get_notes":
            let selectors = MCPArgumentDecoder.stringArray(params.arguments, "notes")
            let location = try MCPArgumentDecoder.location(params.arguments)
            let notes = try service.getNotes(selectors: selectors, location: location)
            return try jsonResult(notes)

        case "bear_list_tags":
            let location = try MCPArgumentDecoder.location(params.arguments)
            let query = MCPArgumentDecoder.optionalString(params.arguments, "query")
            let underTag = MCPArgumentDecoder.optionalString(params.arguments, "under_tag")
            return try jsonResult(try service.listTags(location: location, query: query, underTag: underTag))

        case "bear_find_notes_by_tag":
            let operations = try requiredObjectArray(params.arguments, "operations").map(decodeFindNotesByTagOperation)
            return try jsonResult(try service.findNotesByTag(operations))

        case "bear_find_notes_by_active_tags":
            let operations = try requiredObjectArray(params.arguments, "operations").map(decodeFindNotesByActiveTagsOperation)
            return try jsonResult(try service.findNotesByActiveTags(operations))

        case "bear_list_backups":
            let operations = try requiredObjectArray(params.arguments, "operations").map { object in
                ListBackupsOperation(
                    id: MCPArgumentDecoder.optionalString(object, "id"),
                    noteID: MCPArgumentDecoder.optionalString(object, "note"),
                    limit: MCPArgumentDecoder.optionalInt(object, "limit")
                )
            }
            return try jsonResult(try await service.listBackups(operations))

        case "bear_open_tag":
            let tag = try MCPArgumentDecoder.string(params.arguments, "tag")
            return try jsonResult(try await service.openTag(tag))

        case "bear_rename_tags":
            let requests = try MCPArgumentDecoder.objectArray(params.arguments, "operations").map { object in
                RenameTagRequest(
                    name: try requiredString(object, "name"),
                    newName: try requiredString(object, "new_name"),
                    showWindow: try MCPArgumentDecoder.optionalBool(object, "show_window")
                )
            }
            return try jsonResult(try await service.renameTags(requests))

        case "bear_create_notes":
            let defaults = BearPresentationOptions(
                openNote: configuration.createOpensNoteByDefault,
                newWindow: configuration.openUsesNewWindowByDefault,
                showWindow: true,
                edit: configuration.openNoteInEditModeByDefault
            )
            let requests = try MCPArgumentDecoder.objectArray(params.arguments, "operations").map { object in
                CreateNoteRequest(
                    title: try requiredString(object, "title"),
                    content: try requiredString(object, "content"),
                    tags: object["tags"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                    useOnlyRequestTags: try MCPArgumentDecoder.optionalBool(object, "use_only_request_tags"),
                    presentation: MCPArgumentDecoder.presentation(object, defaults: defaults)
                )
            }
            return try jsonResult(try await service.createNotes(requests))

        case "bear_insert_text":
            let defaults = BearPresentationOptions(
                openNote: false,
                newWindow: configuration.openUsesNewWindowByDefault,
                showWindow: true,
                edit: configuration.openNoteInEditModeByDefault
            )
            let requests = try MCPArgumentDecoder.objectArray(params.arguments, "operations").map { object in
                InsertTextRequest(
                    noteID: try requiredNoteSelector(object),
                    text: try requiredString(object, "text"),
                    position: try MCPArgumentDecoder.position(object, default: configuration.defaultInsertPosition.asInsertPosition),
                    presentation: MCPArgumentDecoder.presentation(object, defaults: defaults),
                    expectedVersion: object["expected_version"]?.intValue
                )
            }
            return try jsonResult(try await service.insertText(requests))

        case "bear_replace_content":
            let defaults = BearPresentationOptions(
                openNote: false,
                newWindow: configuration.openUsesNewWindowByDefault,
                showWindow: true,
                edit: configuration.openNoteInEditModeByDefault
            )
            let requests = try MCPArgumentDecoder.objectArray(params.arguments, "operations").map { object in
                ReplaceContentRequest(
                    noteID: try requiredNoteSelector(object),
                    kind: try MCPArgumentDecoder.replaceContentKind(object),
                    oldString: object["old_string"]?.stringValue,
                    occurrence: try MCPArgumentDecoder.replaceStringOccurrence(object),
                    newString: try requiredString(object, "new_string"),
                    presentation: MCPArgumentDecoder.presentation(object, defaults: defaults),
                    expectedVersion: object["expected_version"]?.intValue
                )
            }
            return try jsonResult(try await service.replaceContent(requests))

        case "bear_add_files":
            let defaults = BearPresentationOptions(
                openNote: false,
                newWindow: configuration.openUsesNewWindowByDefault,
                showWindow: true,
                edit: configuration.openNoteInEditModeByDefault
            )
            let requests = try MCPArgumentDecoder.objectArray(params.arguments, "operations").map { object in
                AddFileRequest(
                    noteID: try requiredNoteSelector(object),
                    filePath: try requiredString(object, "file_path"),
                    position: try MCPArgumentDecoder.position(object, default: configuration.defaultInsertPosition.asInsertPosition),
                    presentation: MCPArgumentDecoder.presentation(object, defaults: defaults),
                    expectedVersion: object["expected_version"]?.intValue
                )
            }
            return try jsonResult(try await service.addFiles(requests))

        case "bear_open_notes":
            let defaults = BearPresentationOptions(
                openNote: true,
                newWindow: configuration.openUsesNewWindowByDefault,
                showWindow: true,
                edit: configuration.openNoteInEditModeByDefault
            )
            let requests = try MCPArgumentDecoder.objectArray(params.arguments, "operations").map { object in
                OpenNoteRequest(
                    noteID: try requiredNoteSelector(object),
                    presentation: MCPArgumentDecoder.presentation(object, defaults: defaults)
                )
            }
            return try jsonResult(try await service.openNotes(requests))

        case "bear_archive_notes":
            let noteSelectors = try requiredNoteSelectors(params.arguments)
            return try jsonResult(try await service.archiveNotes(noteSelectors))

        case "bear_restore_notes":
            let defaults = BearPresentationOptions(
                openNote: false,
                newWindow: configuration.openUsesNewWindowByDefault,
                showWindow: true,
                edit: configuration.openNoteInEditModeByDefault
            )
            let requests = try MCPArgumentDecoder.objectArray(params.arguments, "operations").map { object in
                RestoreBackupRequest(
                    noteID: try requiredNoteSelector(object),
                    snapshotID: MCPArgumentDecoder.optionalString(object, "snapshot_id"),
                    presentation: MCPArgumentDecoder.presentation(object, defaults: defaults)
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
        return .init(content: [.text(text)], isError: false)
    }

    private func requiredString(_ object: [String: Value], _ key: String) throws -> String {
        guard let value = object[key]?.stringValue, !value.isEmpty else {
            throw BearError.invalidInput("Missing required string argument '\(key)'.")
        }
        return value
    }

    private func requiredNoteSelector(_ object: [String: Value]) throws -> String {
        if let value = object["note"]?.stringValue, !value.isEmpty {
            return value
        }
        if let value = object["note_id"]?.stringValue, !value.isEmpty {
            return value
        }
        throw BearError.invalidInput("Missing required string argument 'note'.")
    }

    private func requiredNoteSelectors(_ arguments: [String: Value]?) throws -> [String] {
        let selectors = MCPArgumentDecoder.stringArray(arguments, "notes")
        if !selectors.isEmpty {
            return selectors
        }

        let legacySelectors = MCPArgumentDecoder.stringArray(arguments, "note_ids")
        if !legacySelectors.isEmpty {
            return legacySelectors
        }

        throw BearError.invalidInput("Missing required array argument 'notes'.")
    }

    private func requiredObjectArray(_ arguments: [String: Value]?, _ key: String) throws -> [[String: Value]] {
        let values = MCPArgumentDecoder.objectArray(arguments, key)
        guard !values.isEmpty else {
            throw BearError.invalidInput("Missing required array argument '\(key)'.")
        }
        return values
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
            hasAttachments: try MCPArgumentDecoder.optionalBool(object, "has_attachments"),
            hasAttachmentSearchText: try MCPArgumentDecoder.optionalBool(object, "has_attachment_search_text"),
            hasTags: try MCPArgumentDecoder.optionalBool(object, "has_tags"),
            activeTagsMode: try MCPArgumentDecoder.optionalFindTagMatchMode(object, key: "active_tags_mode"),
            dateField: try MCPArgumentDecoder.optionalFindDateField(object, key: "date_field"),
            from: MCPArgumentDecoder.optionalString(object, "from"),
            to: MCPArgumentDecoder.optionalString(object, "to"),
            location: try MCPArgumentDecoder.location(object),
            limit: MCPArgumentDecoder.optionalInt(object, "limit"),
            snippetLength: MCPArgumentDecoder.optionalInt(object, "snippet_length"),
            cursor: MCPArgumentDecoder.optionalString(object, "cursor")
        )
    }

    private func decodeFindNotesByTagOperation(_ object: [String: Value]) throws -> FindNotesByTagOperation {
        FindNotesByTagOperation(
            id: MCPArgumentDecoder.optionalString(object, "id"),
            tags: MCPArgumentDecoder.stringArray(object, "tags"),
            tagMatch: try MCPArgumentDecoder.findTagMatchMode(object, key: "tag_match"),
            location: try MCPArgumentDecoder.location(object),
            limit: MCPArgumentDecoder.optionalInt(object, "limit"),
            snippetLength: MCPArgumentDecoder.optionalInt(object, "snippet_length"),
            cursor: MCPArgumentDecoder.optionalString(object, "cursor")
        )
    }

    private func decodeFindNotesByActiveTagsOperation(_ object: [String: Value]) throws -> FindNotesByActiveTagsOperation {
        FindNotesByActiveTagsOperation(
            id: MCPArgumentDecoder.optionalString(object, "id"),
            match: try MCPArgumentDecoder.findTagMatchMode(object, key: "match"),
            location: try MCPArgumentDecoder.location(object),
            limit: MCPArgumentDecoder.optionalInt(object, "limit"),
            snippetLength: MCPArgumentDecoder.optionalInt(object, "snippet_length"),
            cursor: MCPArgumentDecoder.optionalString(object, "cursor")
        )
    }

    private static func renderError(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    static func toolCatalog(configuration: BearConfiguration) -> [Tool] {
        ToolCatalog.makeTools(configuration: configuration)
    }
}

private enum ToolCatalog {
    static func makeTools(configuration: BearConfiguration) -> [Tool] {
        [
            batchedDiscoveryTool(
                name: "bear_find_notes",
                description: "Find Bear notes with text, tag, active-tag, and date filters and return compact summaries. Use `bear_list_tags` first when the exact tag name is uncertain. Omit `location`, `limit`, and `snippet_length` unless the user explicitly asks to override the current session defaults. Discovery excludes trash.",
                operationProperties: findNotesOperationProperties(configuration: configuration),
                required: []
            ),
            Tool(
                name: "bear_get_notes",
                description: "Fetch full Bear note records for one or more selectors. Selectors are matched as exact note ids first, then exact case-insensitive titles. Omit location unless the user explicitly asks for archived notes.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "notes": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                        ]),
                        "location": .object([
                            "type": .string("string"),
                            "enum": .array([.string("notes"), .string("archive")]),
                            "description": .string("Optional. Omit unless the user explicitly asks for archived notes. Defaults to `notes`."),
                        ]),
                    ]),
                    "required": .array([.string("notes")]),
                ])
            ),
            Tool(
                name: "bear_list_tags",
                description: "List Bear tags for the selected note location. Use this as the discovery step when another tag tool needs a canonical tag name. Optional `query` filters tag names by case-insensitive substring, and optional `under_tag` returns descendants under a parent tag path. Omit all filters for the default normal-notes tag list. Omit `location` unless the user explicitly asks for archived tags.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "location": .object([
                            "type": .string("string"),
                            "enum": .array([.string("notes"), .string("archive")]),
                            "description": .string("Optional. Omit unless the user explicitly asks for archived tags. Defaults to `notes`."),
                        ]),
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Optional case-insensitive substring filter for tag names."),
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
                description: "Find Bear notes by one or more Bear tags and return compact summaries. Use `bear_list_tags` first when the exact tag name is uncertain. Use `bear_open_tag` instead when the goal is UI navigation to one tag. Omit `location`, `limit`, and `snippet_length` unless the user explicitly asks to override the current session defaults. Discovery excludes trash.",
                operationProperties: findNotesByTagOperationProperties(configuration: configuration),
                required: ["tags"]
            ),
            batchedDiscoveryTool(
                name: "bear_find_notes_by_active_tags",
                description: "Find Bear notes by the configured active tags and return compact summaries. Current active tags: \(formattedTagList(configuration.activeTags)). Omit `location`, `limit`, and `snippet_length` unless the user explicitly asks to override the current session defaults. Discovery excludes trash.",
                operationProperties: findNotesByActiveTagsOperationProperties(configuration: configuration),
                required: []
            ),
            batchedDiscoveryTool(
                name: "bear_list_backups",
                description: "List saved Bear note backup snapshots and return compact summaries. Use this before `bear_restore_notes` so snapshot restores are explicit rather than blind. Omit `limit` unless the user explicitly asks for a different number of snapshots. `note` is optional; omit it to list recent backups across notes.",
                operationProperties: backupListOperationProperties(configuration: configuration),
                required: []
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
                description: "Rename one or more Bear tags. Use `bear_list_tags` first to confirm the existing canonical tag names. Omit `show_window` unless the user explicitly asks to control whether Bear shows its main window for the rename.",
                operationProperties: [
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Existing tag name to rename."),
                    ]),
                    "new_name": .object([
                        "type": .string("string"),
                        "description": .string("Replacement tag name."),
                    ]),
                    "show_window": optionalPresentationBoolean(description: "Optional. Omit unless the user explicitly asks to control whether Bear shows its main window during the rename."),
                ],
                required: ["name", "new_name"],
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_create_notes",
                description: "Create one or more Bear notes. `content` must be a non-empty string. Pass `tags` only for tags the user explicitly requested. Current create defaults: omitted `open_note` uses \(formattedBool(configuration.createOpensNoteByDefault)); omitted `new_window` uses \(formattedBool(configuration.openUsesNewWindowByDefault)) when the note is opened; configured active tags are \(formattedTagList(configuration.activeTags)); tag merging on omission currently \(formattedCreateTagMergeBehavior(configuration)). Omit `use_only_request_tags`, `open_note`, and `new_window` unless the user explicitly asks to override those defaults for this request. If the user only asks to add tag X, pass `tags` and do not send `use_only_request_tags`. If the user says anything explicit about whether the note should open, send `open_note` with that exact intent. Use `open_note: true` for requests like 'open it' and `open_note: false` for requests like 'do not open it'. Only omit `open_note` when the user does not mention opening at all.",
                operationProperties: [
                    "title": .object(["type": .string("string")]),
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("Required non-empty note content."),
                    ]),
                    "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                    "use_only_request_tags": .object([
                        "type": .string("boolean"),
                        "description": .string("Optional per-request override for note creation. Omit unless the user explicitly asks to change the current tag-merging default. Current omission behavior: \(formattedCreateTagMergeBehavior(configuration)). `true` uses only the supplied request tags instead of configured active tags. `false` appends configured active tags. If the user only asks to add specific tags, pass `tags` and omit `use_only_request_tags`."),
                    ]),
                    "open_note": optionalPresentationBoolean(description: "Optional per-request override for whether Bear opens the created note. Current omission default: \(formattedBool(configuration.createOpensNoteByDefault)). Map any explicit user preference about opening to this field. `true` forces open and `false` forces closed. Omit this field when the user does not mention opening."),
                    "new_window": optionalPresentationBoolean(description: "Optional override for window presentation. Current omission default when the created note is opened: \(formattedBool(configuration.openUsesNewWindowByDefault)). Omit unless the user explicitly asks for a separate or floating Bear window, or otherwise asks to override the configured window behavior."),
                ],
                required: ["title", "content"],
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_insert_text",
                description: "Insert text at the top or bottom of one or more Bear notes. `note` accepts a selector matched as exact note id first, then exact case-insensitive title; ambiguous title matches must be disambiguated with the note id. Current omission defaults: `position` uses `\(configuration.defaultInsertPosition.rawValue)`; `open_note` stays closed unless explicitly requested; `new_window` uses \(formattedBool(configuration.openUsesNewWindowByDefault)) when the note is opened. Omit optional fields unless the user explicitly asks to override those defaults for this request.",
                operationProperties: [
                    "note": noteSelectorProperty(),
                    "text": .object(["type": .string("string")]),
                    "position": .object([
                        "type": .string("string"),
                        "enum": .array([.string("top"), .string("bottom")]),
                        "description": .string("Optional insertion position. Omitted uses the current session default `\(configuration.defaultInsertPosition.rawValue)`."),
                    ]),
                    "expected_version": .object(["type": .string("integer")]),
                    "open_note": optionalPresentationBoolean(description: "Optional override. Current omission default: `false`. Omit this field unless the user explicitly asks to open the note after inserting."),
                    "new_window": optionalPresentationBoolean(description: "Optional override. Current omission default when the note is opened: \(formattedBool(configuration.openUsesNewWindowByDefault)). Use `true` when the user asks for a separate or floating Bear window."),
                ],
                required: ["note", "text"],
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_replace_content",
                description: "Replace Bear note content while preserving note structure. Use `bear_get_notes` first when the user wants a surgical replacement or when the exact current text is not already known. `note` accepts a selector matched as exact note id first, then exact case-insensitive title; ambiguous title matches must be disambiguated with the note id. `kind: title` changes only the title. `kind: body` replaces only the editable note content. `kind: string` replaces text only inside editable content, never inside the title, and should usually be preceded by `bear_get_notes` so `old_string` matches stored content exactly. Current omission defaults: `open_note` stays closed unless explicitly requested, and `new_window` uses \(formattedBool(configuration.openUsesNewWindowByDefault)) when the note is opened. Omit optional presentation flags unless the user explicitly asks to override those defaults for this request.",
                operationProperties: [
                    "note": noteSelectorProperty(),
                    "kind": .object([
                        "type": .string("string"),
                        "enum": .array([.string("title"), .string("body"), .string("string")]),
                        "description": .string("Required replacement kind. Use `title` to replace only the note title, `body` to replace only editable note content, and `string` for surgical text replacement inside editable content."),
                    ]),
                    "old_string": .object([
                        "type": .string("string"),
                        "description": .string("Required for `kind: string`. Pass the exact current text as stored in the note content. Prefer `bear_get_notes` first if uncertain."),
                    ]),
                    "occurrence": .object([
                        "type": .string("string"),
                        "enum": .array([.string("one"), .string("all")]),
                        "description": .string("Required for `kind: string`. Use `one` for a single exact content match and `all` to replace every matching content occurrence."),
                    ]),
                    "new_string": .object([
                        "type": .string("string"),
                        "description": .string("Required replacement text. For `kind: title`, this is the full new title. For `kind: body`, this is the full new editable content. For `kind: string`, this is the replacement text."),
                    ]),
                    "expected_version": .object(["type": .string("integer")]),
                    "open_note": optionalPresentationBoolean(description: "Optional override. Current omission default: `false`. Omit this field unless the user explicitly asks to open the note after replacing."),
                    "new_window": optionalPresentationBoolean(description: "Optional override. Current omission default when the note is opened: \(formattedBool(configuration.openUsesNewWindowByDefault)). Use `true` when the user asks for a separate or floating Bear window."),
                ],
                required: ["note", "kind", "new_string"],
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_add_files",
                description: "Attach one or more local files to Bear notes. `note` accepts a selector matched as exact note id first, then exact case-insensitive title; ambiguous title matches must be disambiguated with the note id. Current omission defaults: `position` uses `\(configuration.defaultInsertPosition.rawValue)`; `open_note` stays closed unless explicitly requested; `new_window` uses \(formattedBool(configuration.openUsesNewWindowByDefault)) when the note is opened. Omit optional fields unless the user explicitly asks to override those defaults for this request.",
                operationProperties: [
                    "note": noteSelectorProperty(),
                    "file_path": .object(["type": .string("string")]),
                    "position": .object([
                        "type": .string("string"),
                        "enum": .array([.string("top"), .string("bottom")]),
                        "description": .string("Optional file insertion position. Omitted uses the current session default `\(configuration.defaultInsertPosition.rawValue)`."),
                    ]),
                    "expected_version": .object(["type": .string("integer")]),
                    "open_note": optionalPresentationBoolean(description: "Optional override. Current omission default: `false`. Omit this field unless the user explicitly asks to open the note after attaching the file."),
                    "new_window": optionalPresentationBoolean(description: "Optional override. Current omission default when the note is opened: \(formattedBool(configuration.openUsesNewWindowByDefault)). Use `true` when the user asks for a separate or floating Bear window."),
                ],
                required: ["note", "file_path"],
                presentationProperties: [:]
            ),
            batchedMutationTool(
                name: "bear_open_notes",
                description: "Open Bear notes in the Bear UI. `note` accepts a selector matched as exact note id first, then exact case-insensitive title; ambiguous title matches must be disambiguated with the note id. Current omission default: `new_window` uses \(formattedBool(configuration.openUsesNewWindowByDefault)). Omit `new_window` unless the user explicitly asks to override that default for this request.",
                operationProperties: [
                    "note": noteSelectorProperty(),
                    "new_window": optionalPresentationBoolean(description: "Optional override. Current omission default: \(formattedBool(configuration.openUsesNewWindowByDefault)). Use `true` when the user asks for a separate or floating Bear window."),
                ],
                required: ["note"],
                presentationProperties: [:]
            ),
            Tool(
                name: "bear_archive_notes",
                description: "Archive one or more Bear notes. `notes` accepts selectors matched as exact note ids first, then exact case-insensitive titles; ambiguous title matches must be disambiguated with the note id.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "notes": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                            "description": .string("Required note selectors. Each selector is matched as exact note id first, then exact case-insensitive title across notes and archive. If a title matches multiple notes, use the note id instead."),
                        ]),
                    ]),
                    "required": .array([.string("notes")]),
                ])
            ),
            batchedMutationTool(
                name: "bear_restore_notes",
                description: "Restore one or more Bear notes from saved backup snapshots. Use `bear_list_backups` first when you need to inspect available snapshots before restoring. If `snapshot_id` is omitted, the most recent backup for that note is restored. Current omission defaults: `open_note` stays closed unless explicitly requested, and `new_window` uses \(formattedBool(configuration.openUsesNewWindowByDefault)) when the note is opened. Omit optional presentation flags unless the user explicitly asks to override those defaults for this request.",
                operationProperties: [
                    "note": noteSelectorProperty(),
                    "snapshot_id": .object([
                        "type": .string("string"),
                        "description": .string("Optional backup snapshot identifier. Omit to restore the most recent snapshot for the selected note."),
                    ]),
                    "open_note": optionalPresentationBoolean(description: "Optional override. Current omission default: `false`. Omit this field unless the user explicitly asks to open the note after restoring."),
                    "new_window": optionalPresentationBoolean(description: "Optional override. Current omission default when the note is opened: \(formattedBool(configuration.openUsesNewWindowByDefault)). Use `true` when the user asks for a separate or floating Bear window."),
                ],
                required: ["note"],
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
            description: description,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "operations": .object([
                        "type": .string("array"),
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
            "has_attachments": .object([
                "type": .string("boolean"),
                "description": .string("Optional presence filter. Set true to return only notes with attachments, or false to return only notes without attachments."),
            ]),
            "has_attachment_search_text": .object([
                "type": .string("boolean"),
                "description": .string("Optional presence filter over attachment indexed/OCR text. Set true to require non-empty attachment search text, or false to require none."),
            ]),
            "has_tags": .object([
                "type": .string("boolean"),
                "description": .string("Optional presence filter. Set true to return only tagged notes, or false to return only notes without tags."),
            ]),
            "active_tags_mode": .object([
                "type": .string("string"),
                "enum": .array([.string("any"), .string("all")]),
                "description": .string("Optional active-tag filter against the current configured active tags \(formattedTagList(configuration.activeTags))."),
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
        ], configuration: configuration)
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
        ], configuration: configuration)
    }

    private static func findNotesByActiveTagsOperationProperties(configuration: BearConfiguration) -> [String: Value] {
        discoveryOperationProperties([
            "id": .object(["type": .string("string")]),
            "match": .object([
                "type": .string("string"),
                "enum": .array([.string("any"), .string("all")]),
                "description": .string("Optional matching mode over the current configured active tags \(formattedTagList(configuration.activeTags))."),
            ]),
        ], configuration: configuration)
    }

    private static func backupListOperationProperties(configuration: BearConfiguration) -> [String: Value] {
        [
            "id": .object(["type": .string("string")]),
            "note": .object([
                "type": .string("string"),
                "description": .string("Optional note selector. Matched as exact note id first, then exact case-insensitive title across notes and archive. If omitted, recent backups across notes are returned."),
            ]),
            "limit": .object([
                "type": .string("integer"),
                "description": .string("Optional number of backup summaries to return. Omit unless the user explicitly asks for a different limit. Omitted uses `\(configuration.defaultDiscoveryLimit)`. Values above `\(configuration.maxDiscoveryLimit)` are capped."),
            ]),
        ]
    }

    private static func discoveryOperationProperties(
        _ base: [String: Value],
        configuration: BearConfiguration
    ) -> [String: Value] {
        var properties = base
        properties["location"] = .object([
            "type": .string("string"),
            "enum": .array([.string("notes"), .string("archive")]),
            "description": .string("Optional. Omit unless the user explicitly asks for archived notes. Defaults to `notes`."),
        ])
        properties["limit"] = .object([
            "type": .string("integer"),
            "description": .string("Optional number of summaries to return. Omit unless the user explicitly asks for a different limit or a continuation flow requires it. Omitted uses `\(configuration.defaultDiscoveryLimit)`. Values above `\(configuration.maxDiscoveryLimit)` are capped."),
        ])
        properties["snippet_length"] = .object([
            "type": .string("integer"),
            "description": .string("Optional snippet length in characters. Omit unless the user explicitly asks for a different snippet size. Omitted uses `\(configuration.defaultSnippetLength)`. Values above `\(configuration.maxSnippetLength)` are capped."),
        ])
        properties["cursor"] = .object([
            "type": .string("string"),
            "description": .string("Optional opaque pagination cursor returned by a previous discovery page. Omit for the first page and pass back `nextCursor` to continue."),
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
            description: description,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "operations": .object([
                        "type": .string("array"),
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

    private static func optionalPresentationBoolean(description: String) -> Value {
        .object([
            "type": .string("boolean"),
            "description": .string(description),
        ])
    }

    private static func noteSelectorProperty() -> Value {
        .object([
            "type": .string("string"),
            "description": .string("Required note selector. Matched as exact note id first, then exact case-insensitive title across notes and archive. If a title matches multiple notes, use the note id instead."),
        ])
    }

    private static func formattedBool(_ value: Bool) -> String {
        value ? "`true`" : "`false`"
    }

    private static func formattedTagList(_ tags: [String]) -> String {
        guard !tags.isEmpty else {
            return "none"
        }
        return tags.map { "`\($0)`" }.joined(separator: ", ")
    }

    private static func formattedCreateTagMergeBehavior(_ configuration: BearConfiguration) -> String {
        guard configuration.createAddsActiveTagsByDefault else {
            return "uses only request tags unless explicitly overridden"
        }

        switch configuration.tagsMergeMode {
        case .append:
            return "appends configured active tags to request tags"
        case .replace:
            return "uses request tags when any are supplied, otherwise falls back to configured active tags"
        }
    }
}
