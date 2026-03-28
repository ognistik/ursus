import Foundation

public enum BearToolCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case discovery
    case noteContent
    case tags
    case backups
    case navigation

    public var title: String {
        switch self {
        case .discovery:
            return "Discovery"
        case .noteContent:
            return "Notes"
        case .tags:
            return "Tags"
        case .backups:
            return "Backups"
        case .navigation:
            return "Navigation"
        }
    }
}

public enum BearToolName: String, CaseIterable, Codable, Hashable, Sendable {
    case findNotes = "bear_find_notes"
    case getNotes = "bear_get_notes"
    case listTags = "bear_list_tags"
    case findNotesByTag = "bear_find_notes_by_tag"
    case findNotesByInboxTags = "bear_find_notes_by_inbox_tags"
    case listBackups = "bear_list_backups"
    case deleteBackups = "bear_delete_backups"
    case openTag = "bear_open_tag"
    case renameTags = "bear_rename_tags"
    case deleteTags = "bear_delete_tags"
    case addTags = "bear_add_tags"
    case removeTags = "bear_remove_tags"
    case applyTemplate = "bear_apply_template"
    case createNotes = "bear_create_notes"
    case insertText = "bear_insert_text"
    case replaceContent = "bear_replace_content"
    case addFiles = "bear_add_files"
    case openNotes = "bear_open_notes"
    case archiveNotes = "bear_archive_notes"
    case restoreNotes = "bear_restore_notes"

    public var title: String {
        switch self {
        case .findNotes:
            return "Find Notes"
        case .getNotes:
            return "Get Notes"
        case .listTags:
            return "List Tags"
        case .findNotesByTag:
            return "Find Notes by Tag"
        case .findNotesByInboxTags:
            return "Find Notes by Inbox Tags"
        case .listBackups:
            return "List Backups"
        case .deleteBackups:
            return "Delete Backups"
        case .openTag:
            return "Open Tag"
        case .renameTags:
            return "Rename Tags"
        case .deleteTags:
            return "Delete Tags"
        case .addTags:
            return "Add Tags"
        case .removeTags:
            return "Remove Tags"
        case .applyTemplate:
            return "Apply Template"
        case .createNotes:
            return "Create Notes"
        case .insertText:
            return "Insert Text"
        case .replaceContent:
            return "Replace Content"
        case .addFiles:
            return "Add Files"
        case .openNotes:
            return "Open Notes"
        case .archiveNotes:
            return "Archive Notes"
        case .restoreNotes:
            return "Restore Notes"
        }
    }

    public var summary: String {
        switch self {
        case .findNotes:
            return "Search note summaries with text, tags, filters, and pagination."
        case .getNotes:
            return "Fetch full note bodies, versions, and attachment metadata."
        case .listTags:
            return "Discover canonical Bear tags before tagging or navigation."
        case .findNotesByTag:
            return "Search note summaries by one or more Bear tags."
        case .findNotesByInboxTags:
            return "Search note summaries using the configured inbox tags."
        case .listBackups:
            return "Inspect saved note backup snapshots."
        case .deleteBackups:
            return "Remove saved backup snapshots."
        case .openTag:
            return "Open a Bear tag in the Bear app UI."
        case .renameTags:
            return "Rename Bear tags globally."
        case .deleteTags:
            return "Delete Bear tags globally."
        case .addTags:
            return "Add tags to notes."
        case .removeTags:
            return "Remove tags from notes."
        case .applyTemplate:
            return "Apply the current template to notes."
        case .createNotes:
            return "Create new Bear notes."
        case .insertText:
            return "Insert text into note content."
        case .replaceContent:
            return "Replace note titles or body content."
        case .addFiles:
            return "Attach local files to notes."
        case .openNotes:
            return "Open notes in Bear."
        case .archiveNotes:
            return "Archive notes."
        case .restoreNotes:
            return "Restore notes from backups."
        }
    }

    public var category: BearToolCategory {
        switch self {
        case .findNotes, .getNotes, .listTags, .findNotesByTag, .findNotesByInboxTags:
            return .discovery
        case .createNotes, .insertText, .replaceContent, .addFiles, .applyTemplate:
            return .noteContent
        case .renameTags, .deleteTags, .addTags, .removeTags:
            return .tags
        case .listBackups, .deleteBackups, .restoreNotes:
            return .backups
        case .openTag, .openNotes, .archiveNotes:
            return .navigation
        }
    }
}
