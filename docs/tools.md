# Ursus MCP Tools Reference

Ursus is designed to be a powerful extension of Bear for your AI. The following tools are **batch-friendly**, meaning you can pass an `operations` array to perform multiple actions—like tagging, backing up, and archiving—in a single tool call.

Most note-targeting tools allow you to pass a specific `note` (by ID or exact title) or, if you have a Bear API token configured, `selected: true` to instantly act on the note you currently have open in Bear.

---

## 1. Discovery
*Find notes with precision.*

*   **`bear_find_notes`**: The primary search tool. Filter by text (including attachments), tags, date ranges, pinned status, todos, or whether the note is in your archive. You can request AI to set the `text_mode` to `substring`, `any_terms`, or `all_terms` for flexible matching. If you have multiple topics or alternate phrasings that may belong to different notes, AI should prefer separate objects in `operations` instead of one combined text string.
    *   **A small but important detail**: each search needs at least one real filter, and results come back paginated so searches stay compact.
*   **`bear_find_notes_by_tag`**: Find notes containing specific tags. Set `tag_match` to `any` (contains at least one) or `all` (contains every tag provided).
*   **`bear_find_notes_by_inbox_tags`**: Quickly find notes based on the inbox tags configured in your Ursus preferences.
*   **`bear_get_notes`**: Fetch the full note content, current note `version`, and attachment OCR content. Use this when you need the current text body or the fresh Bear revision number for a guarded full-body replacement. If you are just trying to find a note to edit, you don't need to call this—the mutation tools resolve note targets automatically. Set `include_attachment_text` to `true` if you need to access OCR text from attachments.
*   **`bear_list_tags`**: List all tags in your library. Use `query` to filter by a substring or `under_tag` to return all nested tags under a specific parent.

---

## 2. Notes
*Creation and structural editing.*

*   **`bear_create_notes`**: Creates notes using your saved Ursus defaults.
    *   **Tags**: By default, Ursus may append your configured inbox tags. You can request AI to `use_only_request_tags: true` if you want to ignore your defaults and use *only* the tags provided in the request.
    *   **Opening**: Creation follows your saved default for whether a note opens after creation. If you want the created note opened or want a specific window behavior, use `bear_open_notes` after creation.
    *   **Receipt details on confirmed create**: When Ursus can immediately verify the created Bear note, the creation receipt may include its Bear `version`, whether it was opened, and whether it opened in the `main_window` or a `new_window`. The `version` comes from Bear's database revision, not from Ursus backups.
*   **`bear_insert_text`**: Insert text relative to your existing content. Use `position: top` or `bottom` for simple insertion, or use the `target` option to insert `before` or `after` a specific heading or exact string.
*   **`bear_replace_content`**: Perform structural replacements.
    *   **Kinds**: Choose `title`, `body` (replaces the entire editable area), or `string` (replaces specific text).
    *   **Version guard for full-body replace**: When replacing `body`, you normally pass `expected_version` from the latest `bear_get_notes` read of that same note. This prevents a stale full-note overwrite if Bear content changed after the read.
    *   **Fast retry after a small conflict**: If Bear content changed but Ursus still has the exact older text the AI saw, Ursus returns a compact conflict receipt with bounded diff hunks and a short-lived single-use `conflictToken`. AI may retry the *same* full-body replacement with `conflict_token` instead of re-reading the whole note.
    *   **Large conflicts still force a reread**: If the differences are too large or too truncated to summarize safely, Ursus returns a conflict receipt that explicitly tells AI to call `bear_get_notes` again.
    *   **Forgiving extra field behavior**: If `expected_version` is accidentally sent with `title` or `string`, Ursus ignores it instead of failing the operation.
    *   **Forgiving retry field behavior**: If `conflict_token` is accidentally sent with `title` or `string`, Ursus ignores it instead of failing the operation.
    *   **Occurrence**: When replacing `string`, set `occurrence` to `one` (first match) or `all` (every match).
*   **`bear_add_files`**: Attach local files (requires a valid local file path) with the same `position` or `target` insertion logic used by `bear_insert_text`.
*   **`bear_apply_template`**: Applies your template to an existing note. This is the smart way to normalize tag-only clusters into your defined `{{tags}}` slot.
*   **`bear_open_notes`**: Open notes in Bear. `new_window: true` opens in a separate Bear window; `new_window: false` opens in Bear's main window.
*   **`bear_archive_notes`**: Archives the specified notes.

*Note: `bear_insert_text`, `bear_replace_content`, `bear_add_files`, `bear_add_tags`, `bear_remove_tags`, `bear_apply_template`, and restore flows create backups automatically before rewriting note content. You can disable backups by setting `0` retention days in your preferences.*

---

## 3. Tags
*Global tag management.*

*   **`bear_open_tag`**: Navigates the Bear UI to the specified tag.
*   **`bear_rename_tags`**: Performs a global rename across your entire library.
*   **`bear_delete_tags`**: Removes a tag globally from every note in your library.
*   **`bear_add_tags`**: Appends specific tags to one or more notes.
*   **`bear_remove_tags`**: Strips specific tags from notes. The server is smart enough to remove them from your template's `{{tags}}` slot as well as inline prose.

---

## 4. Backups
*Safety snapshots.*

*   **`bear_create_backups`**: Manually snapshot a note.
*   **`bear_list_backups`**: Returns a paginated history of snapshots of a specific note. You can filter by date using `from` and `to` timestamps (ISO 8601 or natural language like "yesterday").
*   **`bear_compare_backup`**: Compares a specific `snapshot_id` to the current note content. By default it returns compact diff hunks plus a `truncated` flag when excerpts or hunk counts were limited. Set `detail: full` when you need the full changed regions for each hunk.
*   **`bear_delete_backups`**: Delete a single snapshot (`snapshot_id`) or use `delete_all: true` to clear the entire backup history for a note.
*   **`bear_restore_notes`**: Restores the note to a saved snapshot. If `snapshot_id` is omitted, it rolls back to the most recent backup.

---

## 5. A small mental model that helps

If you're new to MCP, the simplest way to think about Ursus is:

*   **Discovery tools** help the AI find the right note.
*   **Note and tag tools** do the actual editing or organizing.
*   **Backup tools** make those edits safer.

With AI, you can simply request operations via natural language. You can also ask AI to suggest things you can do with the Bear tools available to it.
