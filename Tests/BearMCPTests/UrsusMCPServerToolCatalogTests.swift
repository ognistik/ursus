@testable import BearMCP
import BearCore
import MCP
import Testing

@Test
func toolCatalogInjectsCurrentSessionDefaultsIntoOverrideableFields() throws {
    let configuration = BearConfiguration(
        inboxTags: ["0-inbox", "client work"],
        defaultInsertPosition: .top,
        templateManagementEnabled: true,
        createOpensNoteByDefault: false,
        openUsesNewWindowByDefault: false,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .replace,
        defaultDiscoveryLimit: 7,
        defaultSnippetLength: 90,
        backupRetentionDays: 30
    )

    let tools = UrsusMCPServer.toolCatalog(
        configuration: configuration,
        selectedNoteTokenConfigured: true
    )

    let create = try #require(tool(named: "bear_create_notes", in: tools))
    let createDescription = try #require(create.description)
    #expect(createDescription.hasPrefix("Create one or more Bear notes."))
    #expect(createDescription.contains("Defaults: `open_note` = `false`"))
    #expect(createDescription.contains("`new_window` = `false` when opened"))
    #expect(createDescription.contains("configured inbox tags = `0-inbox`, `client work`"))
    #expect(createDescription.contains("omitted tag-merge behavior uses request tags when any are supplied"))
    #expect(createDescription.contains("Omit `open_note` and `new_window` unless the user explicitly wants to override those defaults.") == true)
    #expect(propertyDescription(named: "open_note", in: create) == "Optional. Omit to use the default `false`. Send `true` only when the user explicitly wants the created note to open.")
    #expect(propertyDescription(named: "new_window", in: create) == "Optional. Only applies when `open_note` is `true`. Omit to use the default when opening: `false`. Send `true` only when the user explicitly wants a separate Bear window.")

    let insert = try #require(tool(named: "bear_insert_text", in: tools))
    let insertDescription = try #require(insert.description)
    #expect(insertDescription.hasPrefix("Insert text into one or more Bear notes."))
    #expect(insertDescription.contains("`position` = `top`"))
    #expect(insertDescription.contains("`new_window` = `false` when opened") == false)
    #expect(insertDescription.contains("`note` accepts a selector matched as exact note id first"))
    #expect(propertyDescription(named: "note", in: insert)?.contains("Use exactly one of `note` or `selected: true`") == true)
    #expect(propertyDescription(named: "selected", in: insert)?.contains("currently selected Bear note") == true)
    #expect(propertyDescription(named: "note", in: insert)?.contains("exact case-insensitive title across notes and archive") == true)
    #expect(propertyDescription(named: "note", in: insert)?.contains("Do not call `bear_get_notes` only to resolve this selector") == true)
    #expect(propertyDescription(named: "position", in: insert)?.contains("Omit to use the current session default `top` when no `target` is provided") == true)
    #expect(propertyDescription(named: "target", in: insert)?.contains("before or after a matching heading") == true)
    #expect(propertyDescription(named: "open_note", in: insert) == nil)
    #expect(propertyDescription(named: "new_window", in: insert) == nil)
    #expect(propertyDescription(named: "expected_version", in: insert) == nil)

    let addFiles = try #require(tool(named: "bear_add_files", in: tools))
    let addFilesDescription = try #require(addFiles.description)
    #expect(addFilesDescription.hasPrefix("Attach one or more local files to Bear notes."))
    #expect(addFilesDescription.contains("`position` = `top`"))
    #expect(propertyDescription(named: "note", in: addFiles)?.contains("exact case-insensitive title across notes and archive") == true)
    #expect(propertyDescription(named: "position", in: addFiles)?.contains("Omit to use the current session default `top` when no `target` is provided") == true)
    #expect(propertyDescription(named: "target", in: addFiles)?.contains("before or after a matching heading") == true)

    let openNotes = try #require(tool(named: "bear_open_notes", in: tools))
    #expect(try #require(openNotes.description).contains("Default: `new_window` = `false`"))
    #expect(propertyDescription(named: "note", in: openNotes)?.contains("exact case-insensitive title across notes and archive") == true)
    #expect(propertyDescription(named: "new_window", in: openNotes) == "Optional. Omit to use the default when opening: `false`. Send `true` only when the user explicitly wants a separate Bear window.")

    let replace = try #require(tool(named: "bear_replace_content", in: tools))
    #expect(try #require(replace.description).contains("Do not call `bear_get_notes` only to resolve the note selector"))
    #expect(try #require(replace.description).contains("exact current text is not already known"))
    #expect(propertyDescription(named: "note", in: replace)?.contains("exact case-insensitive title across notes and archive") == true)
    #expect(propertyDescription(named: "kind", in: replace)?.contains("Required replacement kind") == true)
    #expect(propertyDescription(named: "expected_version", in: replace) == nil)

    let addTags = try #require(tool(named: "bear_add_tags", in: tools))
    let addTagsDescription = try #require(addTags.description)
    #expect(addTagsDescription.hasPrefix("Add one or more tags to specific Bear notes"))
    #expect(addTagsDescription.contains("specific Bear notes"))
    #expect(addTagsDescription.contains("Do not call `bear_get_notes` only to resolve the note selector"))
    #expect(addTagsDescription.contains("exact current tags are actually needed"))
    #expect(propertyDescription(named: "note", in: addTags)?.contains("exact case-insensitive title across notes and archive") == true)
    #expect(propertyDescription(named: "open_note", in: addTags) == nil)
    #expect(propertyDescription(named: "new_window", in: addTags) == nil)
    #expect(propertyDescription(named: "expected_version", in: addTags) == nil)

    let removeTags = try #require(tool(named: "bear_remove_tags", in: tools))
    let removeTagsDescription = try #require(removeTags.description)
    #expect(removeTagsDescription.contains("without deleting the tag globally"))
    #expect(removeTagsDescription.contains("Do not call `bear_get_notes` only to resolve the note selector"))
    #expect(propertyDescription(named: "tags", in: removeTags)?.contains("remove from this one note only") == true)

    let applyTemplate = try #require(tool(named: "bear_apply_template", in: tools))
    let applyTemplateDescription = try #require(applyTemplate.description)
    #expect(applyTemplateDescription.contains("normalize tag-only clusters into the template `{{tags}}` slot"))
    #expect(applyTemplateDescription.contains("preserves inline prose hashtags"))
    #expect(propertyDescription(named: "note", in: applyTemplate)?.contains("exact case-insensitive title across notes and archive") == true)
    #expect(propertyDescription(named: "open_note", in: applyTemplate) == nil)
    #expect(propertyDescription(named: "new_window", in: applyTemplate) == nil)

    let deleteTags = try #require(tool(named: "bear_delete_tags", in: tools))
    #expect(try #require(deleteTags.description).contains("entire Bear app"))
    #expect(propertyDescription(named: "name", in: deleteTags)?.contains("delete across Bear") == true)
    #expect(propertyDescription(named: "show_window", in: deleteTags) == nil)

    let createBackups = try #require(tool(named: "bear_create_backups", in: tools))
    #expect(try #require(createBackups.description).contains("manual capture flow as the CLI"))
    #expect(propertyDescription(named: "note", in: createBackups)?.contains("Use exactly one of `note` or `selected: true`") == true)

    let listBackups = try #require(tool(named: "bear_list_backups", in: tools))
    #expect(try #require(listBackups.description).contains("one Bear note"))
    #expect(try #require(listBackups.description).contains("backup creation timestamp"))
    #expect(propertyDescription(named: "limit", in: listBackups) == nil)
    #expect(propertyDescription(named: "from", in: listBackups)?.contains("backup creation timestamp") == true)
    #expect(propertyDescription(named: "to", in: listBackups)?.contains("backup creation timestamp") == true)
    #expect(propertyDescription(named: "cursor", in: listBackups)?.contains("same note-scoped date-filtered query") == true)
    #expect(propertyDescription(named: "selected", in: listBackups)?.contains("currently selected Bear note") == true)

    let compareBackup = try #require(tool(named: "bear_compare_backup", in: tools))
    #expect(try #require(compareBackup.description).contains("detail: full"))
    #expect(propertyDescription(named: "snapshot_id", in: compareBackup)?.contains("Required backup snapshot identifier") == true)
    #expect(propertyDescription(named: "detail", in: compareBackup)?.contains("full changed regions") == true)

    let deleteBackups = try #require(tool(named: "bear_delete_backups", in: tools))
    #expect(try #require(deleteBackups.description).contains("Provide `snapshot_id` to delete one exact backup"))
    #expect(propertyDescription(named: "delete_all", in: deleteBackups)?.contains("remove all saved backups for that note") == true)
    #expect(propertyDescription(named: "selected", in: deleteBackups)?.contains("currently selected Bear note") == true)

    let restore = try #require(tool(named: "bear_restore_notes", in: tools))
    #expect(try #require(restore.description).contains("If `snapshot_id` is omitted, the most recent backup"))
    #expect(propertyDescription(named: "snapshot_id", in: restore)?.contains("most recent snapshot") == true)
    #expect(propertyDescription(named: "open_note", in: restore) == nil)
    #expect(propertyDescription(named: "new_window", in: restore) == nil)

    let getNotes = try #require(tool(named: "bear_get_notes", in: tools))
    #expect(try #require(getNotes.description).contains("selected: true"))
    #expect(try #require(getNotes.description).contains("Attachment OCR/search text is omitted unless `include_attachment_text` is `true`"))
    #expect(propertyDescription(named: "include_attachment_text", inTopLevelTool: getNotes)?.contains("default `false`") == true)
    #expect(propertyDescription(named: "selected", inTopLevelTool: getNotes)?.contains("currently selected Bear note") == true)

    let archiveNotes = try #require(tool(named: "bear_archive_notes", in: tools))
    #expect(try #require(archiveNotes.description).contains("selected: true"))
    #expect(propertyDescription(named: "selected", inTopLevelTool: archiveNotes)?.contains("currently selected Bear note") == true)
}

@Test
func batchedToolSchemasAdvertiseNonEmptyOperations() throws {
    let tools = UrsusMCPServer.toolCatalog(configuration: .default)
    let batchedToolNames = [
        "bear_find_notes",
        "bear_find_notes_by_tag",
        "bear_find_notes_by_inbox_tags",
        "bear_create_backups",
        "bear_list_backups",
        "bear_compare_backup",
        "bear_delete_backups",
        "bear_rename_tags",
        "bear_delete_tags",
        "bear_add_tags",
        "bear_remove_tags",
        "bear_apply_template",
        "bear_create_notes",
        "bear_insert_text",
        "bear_replace_content",
        "bear_add_files",
        "bear_open_notes",
        "bear_restore_notes",
    ]

    for name in batchedToolNames {
        let matchedTool = try #require(tool(named: name, in: tools))
        let operations = try #require(operationsSchema(in: matchedTool))
        let requiredValues = try #require(matchedTool.inputSchema.objectValue?["required"]?.arrayValue)
        let required = requiredValues.compactMap(\.stringValue)

        #expect(required.contains("operations"))
        #expect(operations["minItems"]?.intValue == 1)
        #expect(operations["description"]?.stringValue == "Required non-empty array of operation objects.")
        #expect(try #require(matchedTool.description).contains("`operations` must be a non-empty array of operation objects."))
    }

    let inbox = try #require(tool(named: "bear_find_notes_by_inbox_tags", in: tools))
    #expect(try #require(inbox.description).contains("Each operation object may be empty"))
}

@Test
func toolCatalogInjectsDiscoveryDefaultsAndInboxTags() throws {
    let configuration = BearConfiguration(
        inboxTags: ["0-inbox", "deep work"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 11,
        defaultSnippetLength: 120,
        backupRetentionDays: 30
    )

    let tools = UrsusMCPServer.toolCatalog(
        configuration: configuration,
        selectedNoteTokenConfigured: false
    )

    let find = try #require(tool(named: "bear_find_notes", in: tools))
    #expect(try #require(find.description).hasPrefix("Find Bear notes with text, tag, inbox-tag, and date filters"))
    #expect(try #require(find.description).contains("prefer separate objects in `operations` instead of one combined text string"))
    #expect(try #require(find.description).contains("returned notes may include `hasBackups`"))
    #expect(propertyDescription(named: "limit", in: find) == nil)
    #expect(propertyDescription(named: "snippet_length", in: find) == nil)
    #expect(propertyDescription(named: "id", in: find)?.contains("search hypotheses") == true)
    #expect(propertyDescription(named: "text", in: find)?.contains("separate operation objects") == true)
    #expect(propertyDescription(named: "text_mode", in: find)?.contains("Default `substring`") == true)
    #expect(propertyDescription(named: "has_pinned", in: find)?.contains("pinned notes") == true)
    #expect(propertyDescription(named: "has_todos", in: find)?.contains("open todos only") == true)
    #expect(propertyDescription(named: "has_attachment_search_text", in: find) == nil)
    #expect(propertyDescription(named: "inbox_tags_mode", in: find)?.contains("`0-inbox`, `deep work`") == true)

    let inbox = try #require(tool(named: "bear_find_notes_by_inbox_tags", in: tools))
    #expect(try #require(inbox.description).contains("Current inbox tags: `0-inbox`, `deep work`"))
    #expect(propertyDescription(named: "match", in: inbox)?.contains("`0-inbox`, `deep work`") == true)

    let insert = try #require(tool(named: "bear_insert_text", in: tools))
    #expect(propertyDescription(named: "selected", in: insert) == nil)

    let getNotes = try #require(tool(named: "bear_get_notes", in: tools))
    #expect(try #require(getNotes.description).contains("returned notes may include `hasBackups`"))
    #expect(propertyDescription(named: "selected", inTopLevelTool: getNotes) == nil)
}

@Test
func toolCatalogCanAdvertiseSelectedNoteSupportWhenTokenComesFromKeychain() throws {
    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30
    )

    let tools = UrsusMCPServer.toolCatalog(
        configuration: configuration,
        selectedNoteTokenConfigured: true
    )

    let getNotes = try #require(tool(named: "bear_get_notes", in: tools))
    #expect(try #require(getNotes.description).contains("selected: true"))
    #expect(propertyDescription(named: "selected", inTopLevelTool: getNotes)?.contains("currently selected Bear note") == true)
}

@Test
func toolCatalogOmitsDisabledToolsFromConfiguration() {
    let configuration = BearConfiguration.default.updatingDisabledTools([.addTags, .deleteTags, .findNotes])

    let tools = UrsusMCPServer.toolCatalog(configuration: configuration)

    #expect(tool(named: "bear_add_tags", in: tools) == nil)
    #expect(tool(named: "bear_delete_tags", in: tools) == nil)
    #expect(tool(named: "bear_find_notes", in: tools) == nil)
    #expect(tool(named: "bear_get_notes", in: tools) != nil)
}

@Test
func bridgeSurfaceMarkerTracksServedCatalogChanges() {
    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30
    )

    let selectedEnabledMarker = UrsusMCPServer.bridgeSurfaceMarker(
        configuration: configuration,
        selectedNoteTokenConfigured: true
    )
    let selectedDisabledMarker = UrsusMCPServer.bridgeSurfaceMarker(
        configuration: configuration,
        selectedNoteTokenConfigured: false
    )
    let disabledToolsMarker = UrsusMCPServer.bridgeSurfaceMarker(
        configuration: configuration.updatingDisabledTools([.getNotes]),
        selectedNoteTokenConfigured: true
    )

    #expect(selectedEnabledMarker != selectedDisabledMarker)
    #expect(selectedEnabledMarker != disabledToolsMarker)
}

@Test
func toolCatalogOmitsBackupHintWhenBackupListingIsUnavailable() throws {
    let noRetention = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 0
    )
    let disabledListBackups = BearConfiguration.default.updatingDisabledTools([.listBackups])

    let noRetentionTools = UrsusMCPServer.toolCatalog(configuration: noRetention)
    let disabledListBackupsTools = UrsusMCPServer.toolCatalog(configuration: disabledListBackups)

    let noRetentionFind = try #require(tool(named: "bear_find_notes", in: noRetentionTools))
    let disabledFind = try #require(tool(named: "bear_find_notes", in: disabledListBackupsTools))

    #expect(try #require(noRetentionFind.description).contains("returned notes may include `hasBackups`") == false)
    #expect(try #require(disabledFind.description).contains("returned notes may include `hasBackups`") == false)
}

@Test
func toolCatalogFlipsPresentationOverrideGuidanceWhenDefaultsAreTrue() throws {
    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .top,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 7,
        defaultSnippetLength: 90,
        backupRetentionDays: 30
    )

    let tools = UrsusMCPServer.toolCatalog(
        configuration: configuration,
        selectedNoteTokenConfigured: true
    )

    let create = try #require(tool(named: "bear_create_notes", in: tools))
    #expect(propertyDescription(named: "open_note", in: create) == "Optional. Omit to use the default `true`. Send `false` only when the user explicitly wants the created note to stay closed.")
    #expect(propertyDescription(named: "new_window", in: create) == "Optional. Only applies when `open_note` is `true`. Omit to use the default when opening: `true`. Send `false` only when the user explicitly wants Bear's main window.")

    let openNotes = try #require(tool(named: "bear_open_notes", in: tools))
    #expect(propertyDescription(named: "new_window", in: openNotes) == "Optional. Omit to use the default when opening: `true`. Send `false` only when the user explicitly wants Bear's main window.")
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

private func propertyDescription(named name: String, inTopLevelTool tool: Tool) -> String? {
    guard
        let schema = tool.inputSchema.objectValue,
        let properties = schema["properties"]?.objectValue,
        let property = properties[name]?.objectValue
    else {
        return nil
    }

    return property["description"]?.stringValue
}

private func operationsSchema(in tool: Tool) -> [String: Value]? {
    tool.inputSchema.objectValue?["properties"]?.objectValue?["operations"]?.objectValue
}
