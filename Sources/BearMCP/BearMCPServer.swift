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
            let scope = try MCPArgumentDecoder.scope(params.arguments)
            let limit = MCPArgumentDecoder.int(params.arguments, "limit", default: 20)
            let results = try service.searchNotes(query: query, scope: scope, limit: limit)
            return try jsonResult(results)

        case "bear_get_notes":
            let noteIDs = MCPArgumentDecoder.stringArray(params.arguments, "note_ids")
            let notes = try service.getNotes(ids: noteIDs)
            return try jsonResult(notes)

        case "bear_list_tags":
            return try jsonResult(try service.listTags())

        case "bear_get_notes_by_tag":
            let tags = MCPArgumentDecoder.stringArray(params.arguments, "tags")
            return try jsonResult(try service.getNotesByTag(tags: tags))

        case "bear_get_scope_notes":
            let scope = try MCPArgumentDecoder.scope(params.arguments)
            return try jsonResult(try service.getScopeNotes(scope: scope))

        case "bear_create_notes":
            let defaults = BearPresentationOptions(
                openNote: configuration.createOpensNoteByDefault,
                newWindow: configuration.openUsesNewWindowByDefault,
                floatingWindow: false,
                showWindow: true,
                edit: configuration.openNoteInEditModeByDefault
            )
            let requests = try MCPArgumentDecoder.objectArray(params.arguments, "operations").map { object in
                CreateNoteRequest(
                    title: try requiredString(object, "title"),
                    content: try requiredString(object, "content"),
                    tags: object["tags"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                    presentation: MCPArgumentDecoder.presentation(object, defaults: defaults)
                )
            }
            return try jsonResult(try await service.createNotes(requests))

        case "bear_insert_text":
            let defaults = BearPresentationOptions(openNote: false, newWindow: false, floatingWindow: false, showWindow: true, edit: configuration.openNoteInEditModeByDefault)
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
            let defaults = BearPresentationOptions(openNote: false, newWindow: false, floatingWindow: false, showWindow: true, edit: configuration.openNoteInEditModeByDefault)
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
            let defaults = BearPresentationOptions(openNote: false, newWindow: false, floatingWindow: false, showWindow: true, edit: configuration.openNoteInEditModeByDefault)
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
                floatingWindow: false,
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
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
            description: "Search Bear notes by query. Supports all notes or the configured active scope.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Search text to match against note titles and note text."),
                    ]),
                    "scope": .object([
                        "type": .string("string"),
                        "enum": .array([.string("all"), .string("active")]),
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                    ]),
                ]),
                "required": .array([.string("query")]),
            ])
        ),
        Tool(
            name: "bear_get_notes",
            description: "Fetch full Bear note records for one or more note identifiers.",
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
            description: "Fetch notes that belong to one or more Bear tags.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "tags": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                    ]),
                ]),
                "required": .array([.string("tags")]),
            ])
        ),
        Tool(
            name: "bear_get_scope_notes",
            description: "Fetch notes in a named scope. In v1 this is mainly the configured active scope.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "scope": .object([
                        "type": .string("string"),
                        "enum": .array([.string("all"), .string("active")]),
                    ]),
                ]),
            ])
        ),
        batchedMutationTool(
            name: "bear_create_notes",
            description: "Create one or more Bear notes. Active tags from config are applied automatically; use tags only for extra explicit tags. Omit optional presentation flags unless you are intentionally overriding config defaults for this request.",
            operationProperties: [
                "title": .object(["type": .string("string")]),
                "content": .object(["type": .string("string")]),
                "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "open_note": optionalPresentationBoolean(description: "Optional override. Omit this field to use the configured create-note open behavior. Only send true or false when intentionally overriding config for this request."),
                "new_window": optionalPresentationBoolean(description: "Optional override. Omit this field to use the configured open-window behavior. This only matters when the created note is opened."),
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
                "new_window": optionalPresentationBoolean(description: "Optional override. Omit this field to use the configured open-window behavior when the note is opened."),
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
                "new_window": optionalPresentationBoolean(description: "Optional override. Omit this field to use the configured open-window behavior when the note is opened."),
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
                "new_window": optionalPresentationBoolean(description: "Optional override. Omit this field to use the configured open-window behavior when the note is opened."),
            ],
            required: ["note_id", "file_path"],
            presentationProperties: [:]
        ),
        batchedMutationTool(
            name: "bear_open_notes",
            description: "Open Bear notes in the Bear UI. Omit optional presentation flags unless you are intentionally overriding config defaults for this request.",
            operationProperties: [
                "note_id": .object(["type": .string("string")]),
                "new_window": optionalPresentationBoolean(description: "Optional override. Omit this field to use the configured open-window behavior."),
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
