@testable import BearMCP
import BearCore
import MCP
import Testing

@Test
func toolCatalogInjectsCurrentSessionDefaultsIntoOverrideableFields() throws {
    let configuration = BearConfiguration(
        databasePath: "/tmp/bear.sqlite",
        activeTags: ["0-inbox", "client work"],
        defaultInsertPosition: .top,
        templateManagementEnabled: true,
        openNoteInEditModeByDefault: true,
        createOpensNoteByDefault: false,
        openUsesNewWindowByDefault: false,
        createAddsActiveTagsByDefault: true,
        tagsMergeMode: .replace,
        defaultDiscoveryLimit: 7,
        maxDiscoveryLimit: 25,
        defaultSnippetLength: 90,
        maxSnippetLength: 180,
        backupRetentionDays: 30
    )

    let tools = BearMCPServer.toolCatalog(configuration: configuration)

    let create = try #require(tool(named: "bear_create_notes", in: tools))
    #expect(create.description?.contains("omitted `open_note` uses `false`") == true)
    #expect(create.description?.contains("omitted `new_window` uses `false`") == true)
    #expect(create.description?.contains("configured active tags are `0-inbox`, `client work`") == true)
    #expect(create.description?.contains("tag merging on omission currently uses request tags when any are supplied") == true)
    #expect(propertyDescription(named: "open_note", in: create)?.contains("Current omission default: `false`") == true)
    #expect(propertyDescription(named: "new_window", in: create)?.contains("Current omission default when the created note is opened: `false`") == true)

    let insert = try #require(tool(named: "bear_insert_text", in: tools))
    #expect(insert.description?.contains("`position` uses `top`") == true)
    #expect(insert.description?.contains("`new_window` uses `false` when the note is opened") == true)
    #expect(insert.description?.contains("`note` accepts a selector matched as exact note id first") == true)
    #expect(propertyDescription(named: "note", in: insert)?.contains("exact case-insensitive title across notes and archive") == true)
    #expect(propertyDescription(named: "position", in: insert)?.contains("Omitted uses the current session default `top`") == true)

    let addFiles = try #require(tool(named: "bear_add_files", in: tools))
    #expect(addFiles.description?.contains("`position` uses `top`") == true)
    #expect(propertyDescription(named: "note", in: addFiles)?.contains("exact case-insensitive title across notes and archive") == true)
    #expect(propertyDescription(named: "position", in: addFiles)?.contains("Omitted uses the current session default `top`") == true)

    let openNotes = try #require(tool(named: "bear_open_notes", in: tools))
    #expect(openNotes.description?.contains("Current omission default: `new_window` uses `false`") == true)
    #expect(propertyDescription(named: "note", in: openNotes)?.contains("exact case-insensitive title across notes and archive") == true)

    let replace = try #require(tool(named: "bear_replace_content", in: tools))
    #expect(propertyDescription(named: "note", in: replace)?.contains("exact case-insensitive title across notes and archive") == true)
    #expect(propertyDescription(named: "kind", in: replace)?.contains("Required replacement kind") == true)

    let listBackups = try #require(tool(named: "bear_list_backups", in: tools))
    #expect(listBackups.description?.contains("Use this before `bear_restore_notes`") == true)
    #expect(propertyDescription(named: "limit", in: listBackups)?.contains("Omitted uses `7`") == true)

    let deleteBackups = try #require(tool(named: "bear_delete_backups", in: tools))
    #expect(deleteBackups.description?.contains("Provide `snapshot_id` to delete one exact backup") == true)
    #expect(propertyDescription(named: "delete_all", in: deleteBackups)?.contains("remove all saved backups for that note") == true)

    let restore = try #require(tool(named: "bear_restore_notes", in: tools))
    #expect(restore.description?.contains("If `snapshot_id` is omitted, the most recent backup") == true)
    #expect(propertyDescription(named: "snapshot_id", in: restore)?.contains("most recent snapshot") == true)
}

@Test
func toolCatalogInjectsDiscoveryDefaultsAndActiveTags() throws {
    let configuration = BearConfiguration(
        databasePath: "/tmp/bear.sqlite",
        activeTags: ["0-inbox", "deep work"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        openNoteInEditModeByDefault: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsActiveTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 11,
        maxDiscoveryLimit: 44,
        defaultSnippetLength: 120,
        maxSnippetLength: 360,
        backupRetentionDays: 30
    )

    let tools = BearMCPServer.toolCatalog(configuration: configuration)

    let find = try #require(tool(named: "bear_find_notes", in: tools))
    #expect(propertyDescription(named: "limit", in: find)?.contains("Omitted uses `11`") == true)
    #expect(propertyDescription(named: "limit", in: find)?.contains("Values above `44` are capped") == true)
    #expect(propertyDescription(named: "snippet_length", in: find)?.contains("Omitted uses `120`") == true)
    #expect(propertyDescription(named: "snippet_length", in: find)?.contains("Values above `360` are capped") == true)
    #expect(propertyDescription(named: "active_tags_mode", in: find)?.contains("`0-inbox`, `deep work`") == true)

    let active = try #require(tool(named: "bear_find_notes_by_active_tags", in: tools))
    #expect(active.description?.contains("Current active tags: `0-inbox`, `deep work`") == true)
    #expect(propertyDescription(named: "match", in: active)?.contains("`0-inbox`, `deep work`") == true)
}

private func tool(named name: String, in tools: [Tool]) -> Tool? {
    tools.first(where: { $0.name == name })
}

private func propertyDescription(named name: String, in tool: Tool) -> String? {
    guard
        let schema = tool.inputSchema.objectValue,
        let properties = schema["properties"]?.objectValue,
        let operations = properties["operations"]?.objectValue,
        let items = operations["items"]?.objectValue,
        let itemProperties = items["properties"]?.objectValue,
        let property = itemProperties[name]?.objectValue
    else {
        return nil
    }

    return property["description"]?.stringValue
}
