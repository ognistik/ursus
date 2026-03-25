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
            .init(tools: ToolCatalog.tools)
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
        case "bear_search_notes":
            let query = try MCPArgumentDecoder.string(params.arguments, "query")
            let location = try MCPArgumentDecoder.location(params.arguments)
            let limit = MCPArgumentDecoder.optionalInt(params.arguments, "limit")
            let snippetLength = MCPArgumentDecoder.optionalInt(params.arguments, "snippet_length")
            let cursor = MCPArgumentDecoder.optionalString(params.arguments, "cursor")
            let results = try service.searchNotes(query: query, location: location, limit: limit, snippetLength: snippetLength, cursor: cursor)
            return try jsonResult(results)

        case "bear_get_notes":
            let selectors = MCPArgumentDecoder.stringArray(params.arguments, "notes")
            let location = try MCPArgumentDecoder.location(params.arguments)
            let notes = try service.getNotes(selectors: selectors, location: location)
            return try jsonResult(notes)

        case "bear_list_tags":
            return try jsonResult(try service.listTags())

        case "bear_get_notes_by_tag":
            let tags = MCPArgumentDecoder.stringArray(params.arguments, "tags")
            let location = try MCPArgumentDecoder.location(params.arguments)
            let limit = MCPArgumentDecoder.optionalInt(params.arguments, "limit")
            let snippetLength = MCPArgumentDecoder.optionalInt(params.arguments, "snippet_length")
            let cursor = MCPArgumentDecoder.optionalString(params.arguments, "cursor")
            return try jsonResult(try service.getNotesByTag(tags: tags, location: location, limit: limit, snippetLength: snippetLength, cursor: cursor))

        case "bear_get_notes_by_active_tags":
            let location = try MCPArgumentDecoder.location(params.arguments)
            let limit = MCPArgumentDecoder.optionalInt(params.arguments, "limit")
            let snippetLength = MCPArgumentDecoder.optionalInt(params.arguments, "snippet_length")
            let cursor = MCPArgumentDecoder.optionalString(params.arguments, "cursor")
            return try jsonResult(try service.getNotesByActiveTags(location: location, limit: limit, snippetLength: snippetLength, cursor: cursor))

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
            let defaults = BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: configuration.openNoteInEditModeByDefault)
            let requests = try MCPArgumentDecoder.objectArray(params.arguments, "operations").map { object in
                InsertTextRequest(
                    noteID: try requiredString(object, "note_id"),
                    text: try requiredString(object, "text"),
                    position: try MCPArgumentDecoder.position(object, default: .bottom),
                    presentation: MCPArgumentDecoder.presentation(object, defaults: defaults),
                    expectedVersion: object["expected_version"]?.intValue
                )
            }
            return try jsonResult(try await service.insertText(requests))

        case "bear_replace_note_body":
            let defaults = BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: configuration.openNoteInEditModeByDefault)
            let requests = try MCPArgumentDecoder.objectArray(params.arguments, "operations").map { object in
                ReplaceNoteBodyRequest(
                    noteID: try requiredString(object, "note_id"),
                    mode: try MCPArgumentDecoder.replaceMode(object),
                    oldString: object["old_string"]?.stringValue,
                    newString: try requiredString(object, "new_string"),
                    presentation: MCPArgumentDecoder.presentation(object, defaults: defaults),
                    expectedVersion: object["expected_version"]?.intValue
                )
            }
            return try jsonResult(try await service.replaceNoteBody(requests))

        case "bear_add_files":
            let defaults = BearPresentationOptions(openNote: false, newWindow: false, showWindow: true, edit: configuration.openNoteInEditModeByDefault)
            let requests = try MCPArgumentDecoder.objectArray(params.arguments, "operations").map { object in
                AddFileRequest(
                    noteID: try requiredString(object, "note_id"),
                    filePath: try requiredString(object, "file_path"),
                    position: try MCPArgumentDecoder.position(object, default: .bottom),
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
                    noteID: try requiredString(object, "note_id"),
                    presentation: MCPArgumentDecoder.presentation(object, defaults: defaults)
                )
            }
            return try jsonResult(try await service.openNotes(requests))

        case "bear_archive_notes":
            let noteIDs = MCPArgumentDecoder.stringArray(params.arguments, "note_ids")
            return try jsonResult(try await service.archiveNotes(noteIDs))

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

    private static func renderError(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

private enum ToolCatalog {
    static let tools: [Tool] = [
        Tool(
            name: "bear_search_notes",
            description: "Search Bear notes by query and return a paged set of compact note summaries. Omit location unless the user explicitly asks for archived notes.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(discoveryProperties([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Search text to match against note titles and note text."),
                    ]),
                ])),
                "required": .array([.string("query")]),
            ])
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
                        "description": .string("Optional. Omit unless the user explicitly asks for archived notes. Defaults to 'notes'."),
                    ]),
                ]),
                "required": .array([.string("notes")]),
            ])
        ),
        Tool(
            name: "bear_list_tags",
            description: "List tags from the local Bear database.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
        ),
        Tool(
            name: "bear_get_notes_by_tag",
            description: "Fetch a paged set of compact note summaries for notes that belong to one or more Bear tags. Omit location unless the user explicitly asks for archived notes.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(discoveryProperties([
                    "tags": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                    ]),
                ])),
                "required": .array([.string("tags")]),
            ])
        ),
        Tool(
            name: "bear_get_notes_by_active_tags",
            description: "Fetch a paged set of compact note summaries for notes that match the configured active tags. Omit location unless the user explicitly asks for archived notes.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(discoveryProperties([:])),
            ])
        ),
        batchedMutationTool(
            name: "bear_create_notes",
            description: "Create one or more Bear notes. `content` must be a non-empty string. Pass `tags` only for tags the user explicitly requested. Omit `use_only_request_tags`, `open_note`, and `new_window` unless the user explicitly asks to override configured defaults for this request. Omitted does not mean false: omission means use config defaults, while an explicit boolean forces behavior for this request. If the user only asks to add tag X, pass `tags` and do not send `use_only_request_tags`. If the user does not mention opening, do not send `open_note` at all.",
            operationProperties: [
                "title": .object(["type": .string("string")]),
                "content": .object([
                    "type": .string("string"),
                    "description": .string("Required non-empty note content."),
                ]),
                "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "use_only_request_tags": .object([
                    "type": .string("boolean"),
                    "description": .string("Optional per-request override for note creation. Omit this field unless the user explicitly asks to replace the configured tag-merging behavior. Omission means use the configured default tagsMergeMode. `true` forces use of only the supplied request tags instead of configured active tags. `false` forces configured active tags to be appended. If the user only asks to add specific tags, pass those tags and omit this field."),
                ]),
                "open_note": optionalPresentationBoolean(description: "Optional per-request override for whether Bear opens the created note. Omit this field unless the user explicitly asks to override the configured create-note open behavior. Omission means use the configured default. `true` forces open. `false` forces closed. If the user does not mention opening, do not send this field."),
                "new_window": optionalPresentationBoolean(description: "Optional override for window presentation. Omit this field unless the user explicitly asks for a separate or floating Bear window, or otherwise asks to override the configured window behavior. If omitted, the configured default applies. This only matters when the created note is opened."),
            ],
            required: ["title", "content"],
            presentationProperties: [:]
        ),
        batchedMutationTool(
            name: "bear_insert_text",
            description: "Insert text at the top or bottom of one or more Bear notes. Omit optional presentation flags unless you are intentionally overriding config defaults for this request.",
            operationProperties: [
                "note_id": .object(["type": .string("string")]),
                "text": .object(["type": .string("string")]),
                "position": .object(["type": .string("string"), "enum": .array([.string("top"), .string("bottom")])]),
                "expected_version": .object(["type": .string("integer")]),
                "open_note": optionalPresentationBoolean(description: "Optional override. Omit this field to keep the tool's default closed behavior for inserts."),
                "new_window": optionalPresentationBoolean(description: "Optional override. Omit this field to use the configured open-window behavior when the note is opened. Use true when the user asks for a separate or floating Bear window."),
            ],
            required: ["note_id", "text"],
            presentationProperties: [:]
        ),
        batchedMutationTool(
            name: "bear_replace_note_body",
            description: "Compute a replacement against the full Bear note markdown and write it back with Bear's replace_all mode. Omit optional presentation flags unless you are intentionally overriding config defaults for this request.",
            operationProperties: [
                "note_id": .object(["type": .string("string")]),
                "mode": .object(["type": .string("string"), "enum": .array([.string("exact"), .string("all"), .string("entire_body")])]),
                "old_string": .object(["type": .string("string")]),
                "new_string": .object(["type": .string("string")]),
                "expected_version": .object(["type": .string("integer")]),
                "open_note": optionalPresentationBoolean(description: "Optional override. Omit this field to keep the tool's default closed behavior for replacements."),
                "new_window": optionalPresentationBoolean(description: "Optional override. Omit this field to use the configured open-window behavior when the note is opened. Use true when the user asks for a separate or floating Bear window."),
            ],
            required: ["note_id", "new_string"],
            presentationProperties: [:]
        ),
        batchedMutationTool(
            name: "bear_add_files",
            description: "Attach one or more local files to Bear notes. Omit optional presentation flags unless you are intentionally overriding config defaults for this request.",
            operationProperties: [
                "note_id": .object(["type": .string("string")]),
                "file_path": .object(["type": .string("string")]),
                "position": .object(["type": .string("string"), "enum": .array([.string("top"), .string("bottom")])]),
                "expected_version": .object(["type": .string("integer")]),
                "open_note": optionalPresentationBoolean(description: "Optional override. Omit this field to keep the tool's default closed behavior for file attachments."),
                "new_window": optionalPresentationBoolean(description: "Optional override. Omit this field to use the configured open-window behavior when the note is opened. Use true when the user asks for a separate or floating Bear window."),
            ],
            required: ["note_id", "file_path"],
            presentationProperties: [:]
        ),
        batchedMutationTool(
            name: "bear_open_notes",
            description: "Open Bear notes in the Bear UI. Omit optional presentation flags unless you are intentionally overriding config defaults for this request.",
            operationProperties: [
                "note_id": .object(["type": .string("string")]),
                "new_window": optionalPresentationBoolean(description: "Optional override. Omit this field to use the configured open-window behavior. Use true when the user asks for a separate or floating Bear window."),
            ],
            required: ["note_id"],
            presentationProperties: [:]
        ),
        Tool(
            name: "bear_archive_notes",
            description: "Archive one or more Bear notes.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "note_ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                    ]),
                ]),
                "required": .array([.string("note_ids")]),
            ])
        ),
    ]

    private static func discoveryProperties(_ base: [String: Value]) -> [String: Value] {
        var properties = base
        properties["location"] = .object([
            "type": .string("string"),
            "enum": .array([.string("notes"), .string("archive")]),
            "description": .string("Optional. Omit unless the user explicitly asks for archived notes. Defaults to 'notes'."),
        ])
        properties["limit"] = .object([
            "type": .string("integer"),
            "description": .string("Optional number of summaries to return. Uses the configured default when omitted and is capped server-side."),
        ])
        properties["snippet_length"] = .object([
            "type": .string("integer"),
            "description": .string("Optional snippet length in characters. Uses the configured default when omitted and is capped server-side."),
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
}
