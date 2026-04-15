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
    case createBackups = "bear_create_backups"
    case listBackups = "bear_list_backups"
    case compareBackup = "bear_compare_backup"
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
        case .createBackups:
            return "Create Backups"
        case .listBackups:
            return "List Backups"
        case .compareBackup:
            return "Compare Backup"
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
            return "Search across your Bear library using combinations of text, tags, dates, pinned state, todos, and attachment content."
        case .getNotes:
            return "Fetch the full body of notes, metadata, and attachment details."
        case .listTags:
            return "Show the tags that exist in Bear so related actions can use the correct names."
        case .findNotesByTag:
            return "Find notes that match one or more specific Bear tags."
        case .findNotesByInboxTags:
            return "Find notes that use your configured inbox tags."
        case .createBackups:
            return "Save snapshots of notes so you can recover earlier states later. Useful before risky edits, bulk changes, or cleanup passes."
        case .listBackups:
            return "Show the saved backup history for a note, including support for narrowing by date."
        case .compareBackup:
            return "Compare a saved snapshot against the current note so you can inspect what changed before restoring anything."
        case .deleteBackups:
            return "Remove saved backup snapshots when they are no longer needed. This can delete a single backup or clear the backup history for a note."
        case .openTag:
            return "Open a Bear tag directly in the Bear app."
        case .renameTags:
            return "Rename a tag across Bear globally, not just in one note."
        case .deleteTags:
            return "Delete Bear tags globally."
        case .addTags:
            return "Add one or more tags to specific notes."
        case .removeTags:
            return "Remove specific tags from specific notes while leaving those tags available elsewhere in Bear. This is the note-level cleanup tool, not a global tag deletion."
        case .applyTemplate:
            return "Reformat existing notes using your current Ursus template while preserving their actual content and normalizing tag placement."
        case .createNotes:
            return "Create new Bear notes with your configured template and tag behavior. Whether creation opens the note comes from your saved defaults; use the open-notes tool when you want an explicit open action."
        case .insertText:
            return "Add new text into an existing note without replacing everything else. It can insert at the top, bottom, or relative to specific text or headings inside the note."
        case .replaceContent:
            return "Edit a note directly by replacing its title, replacing the entire body, or swapping exact text inside the body."
        case .addFiles:
            return "Attach local files to notes and place them at a chosen position in the note content."
        case .openNotes:
            return "Open one or more notes in Bear so you can view or continue working on them in the app."
        case .archiveNotes:
            return "Move notes into Bear's archive without deleting them."
        case .restoreNotes:
            return "Restore a note from one of its saved backups. Use this to roll back unwanted edits or recover an earlier version of the note."
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
        case .createBackups, .listBackups, .compareBackup, .deleteBackups, .restoreNotes:
            return .backups
        case .openTag, .openNotes, .archiveNotes:
            return .navigation
        }
    }
}
