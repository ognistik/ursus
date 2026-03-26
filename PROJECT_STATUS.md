# PROJECT_STATUS.md

This file exists to preserve project context across Codex threads, workspace renames, and future contributors.

## What This Project Is

The current codebase implements a local macOS MCP server for Bear Notes with:

- Swift package/binary name: `bear-mcp`
- MCP server name presented to clients: `bear`
- local stdio transport
- direct SQLite reads from Bear's local database
- Bear x-callback-url writes for note mutations and UI actions

## What This Project Is Not

- not a generic MCP bridge
- not a remote MCP proxy
- not a Shortcuts-first runtime
- not an AppleScript-first runtime
- not a direct Bear database writer
- not a single giant branching tool

## Old System Reference Only

These old assets are important references but must not be modified as part of this project:

- Schema: `/Users/ognistik/Dropbox/2-Areas/SystemAndApps/Alter/Tools/Schemas/bear-notes`
- AppleScript bridge: `/Users/ognistik/Dropbox/2-Areas/SystemAndApps/Alter/Tools/Scripts/bear-notes.scpt`

The old tool proved the feature surface. It should not define the new architecture.

## Key Product Decisions Already Made

### 1. Swift is the chosen implementation language

Reasons:

- native macOS integration
- easier signing/notarization later
- good fit for SQLite, URL launching, and local CLI distribution
- aligned with a long-term shareable binary

### 2. Layering

Current package layout:

- `BearCore`: domain types, errors, config paths, template rendering
- `BearDB`: read-only Bear SQLite access through GRDB
- `BearXCallback`: URL building and Bear app launching for writes
- `BearApplication`: orchestration, guards, template application, mutation planning
- `BearMCP`: MCP tool registration and argument decoding
- `BearMCPCLI`: executable entrypoint

### 3. Read/write split

- Read note data locally from the Bear database.
- Do not write directly to the database.
- Perform writes through Bear's x-callback-url endpoints.
- For v1, verify many writes by polling the database after launching the Bear URL.

### 4. Replace strategy

The user explicitly clarified an important behavior:

- `bear_replace_content` should build the new full note content programmatically outside Bear.
- The write path should then use Bear's full replacement mode.
- Even when the user conceptually wants to change a title, a word, a phrase, or the entire content, the system can still compute the final full text locally and perform one full replacement write.

Current implementation follows that direction.

### 5. Tool philosophy

- explicit tools
- batch-capable mutation inputs
- compact mutation receipts
- keep destructive actions separated

Tools intentionally excluded for now:

- trash
- unarchive

### 6. Active notes / discovery

The old `get-active` behavior is important.

Current direction:

- represent active-note listing as an explicit discovery tool
- `bear_find_notes_by_active_tags` is driven by configured active tags from config
- discovery tools return compact note summaries, not full note bodies
- archive reads are explicit via tool input (`location: notes|archive`), not mixed into default note discovery

## Current Code Status

As of 2026-03-25, the repo contains a working initial scaffold.

Implemented:

- Swift package manifest and dependency graph
- real Bear DB reader against the installed Bear schema
- config/bootstrap path helpers
- single-file create-note template support
- runtime lock handling that prefers a shared process lock and falls back to temp locks when Codex launches additional stdio children
- stdio runtime shutdown that exits when the MCP connection closes or the original parent process disappears
- process-lock acquisition that prefers `~/Library/Application Support/bear-mcp/Runtime/.server.lock` and falls back to temp runtime locks when sandbox policy denies that location or another live stdio launch already holds the shared lock
- application service layer
- x-callback URL builder
- x-callback launcher transport with best-effort polling
- MCP server/tool registration
- empty MCP resource/resource-template list handlers for client compatibility during discovery
- CLI commands: `mcp`, `--update-config`, `doctor`, `paths`
- a few core tests

Verified locally:

- `swift build`
- `swift test`
- `swift run bear-mcp doctor`

## Current Tool Surface

Implemented MCP tool names:

- `bear_find_notes`
- `bear_get_notes`
- `bear_list_tags`
- `bear_find_notes_by_tag`
- `bear_find_notes_by_active_tags`
- `bear_list_backups`
- `bear_delete_backups`
- `bear_open_tag`
- `bear_rename_tags`
- `bear_create_notes`
- `bear_insert_text`
- `bear_replace_content`
- `bear_add_files`
- `bear_open_notes`
- `bear_archive_notes`
- `bear_restore_notes`

## Current File Map

Primary files:

- `Package.swift`
- `Sources/BearDB/BearDatabaseReader.swift`
- `Sources/BearApplication/BearService.swift`
- `Sources/BearApplication/BearBackupFileStore.swift`
- `Sources/BearXCallback/BearXCallbackURLBuilder.swift`
- `Sources/BearXCallback/BearXCallbackTransport.swift`
- `Sources/BearMCP/BearMCPServer.swift`
- `Sources/BearMCPCLI/main.swift`
- `docs/ARCHITECTURE.md`

## Current Runtime Paths

Current local runtime paths are:

- config: `~/.config/bear-mcp/config.json`
- note template: `~/.config/bear-mcp/template.md`
- backups: `~/Library/Application Support/bear-mcp/Backups/`
- backup index: `~/Library/Application Support/bear-mcp/Backups/index.json`
- process lock (preferred shared path): `~/Library/Application Support/bear-mcp/Runtime/.server.lock`
- process lock (contention/temp fallback): `TMPDIR/bear-mcp/Runtime/.server.lock` and `TMPDIR/bear-mcp/Runtime/locks/<pid>.server.lock`
- temporary debug log: `~/Library/Logs/bear-mcp/debug.log`
- default Bear DB path:
  `/Users/ognistik/Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/Application Data/database.sqlite`

Important: repo/GitHub naming can change to `bear-inbox` without immediately changing these runtime paths.

## Important Implementation Details

### Search/read side

- The current DB reader queries `ZSFNOTE`, `ZSFNOTETAG`, and `Z_5TAGS`.
- Find currently uses structured SQL filtering over title, body, tags, tag presence, dates, attachment presence, and attachment OCR/index text.
- Discovery tools always exclude trashed notes.
- Discovery tools search either normal notes or archived notes, never both in one call.
- MCP tool descriptions now explicitly steer clients to omit `location` unless the user asks for archived notes, and user-overridable defaults are injected from the loaded config at startup.
- `bear_list_tags` now defaults `location` to `notes`, excludes trashed and permanently deleted notes, returns location-scoped tag counts, and supports optional `query` and hierarchical `under_tag` filters.
- MCP tag-tool descriptions now cross-reference `bear_list_tags`, `bear_find_notes_by_tag`, and `bear_open_tag` so clients have clearer discovery hints when an exact tag name is required versus when the goal is UI navigation.
- `bear_get_notes` now defaults `location` to `notes`, never returns trashed notes, and only searches archived notes when `location: archive` is explicitly requested.
- `bear_get_notes` now accepts a single `notes` selector array, resolves each selector as exact note id first and then exact case-insensitive title within the requested location, preserves selector order, and deduplicates results by note id.
- `bear_find_notes`, `bear_find_notes_by_tag`, and `bear_find_notes_by_active_tags` now share a batched summary result shape. Each operation returns compact note summaries with note id, title, body snippet, optional attachment snippet, optional matched fields, tags, created/modified timestamps, archive status, and pagination metadata, or an inline error.
- Discovery pagination is cursor-based per operation. Discovery tools accept an optional opaque `cursor`, return `hasMore` plus `nextCursor`, and paginate over the full internal sort key.
- Internal tag values are normalized as bare tag names. When rendering note text, single-word tags use `#tag` and tags containing whitespace use Bear's wrapped form `#tag with spaces#`.
- Discovery limits and snippet lengths are config-driven defaults with per-operation overrides and server-side hard caps, and the live default/cap values are injected into MCP property descriptions at startup.
- Snippets are template-aware when the current template can be matched back to the stored note body; otherwise they fall back to the parsed note body.
- Attachment snippets are built from `ZSFNOTEFILE.ZSEARCHTEXT` in attachment insertion order and truncated with the same configured snippet limit.
- `bear_find_notes` supports query-less filtering by tags, presence flags, or dates and accepts supported past/present natural-language date phrases that are resolved server-side in the local timezone.
- Text discovery now applies deterministic ranking when `text` is present: exact full-query phrase matches sort ahead of ordered-term matches, which sort ahead of unordered all-term matches, with ties broken by modified date plus note id. Filter-only discovery still uses pure recency ordering.
- `from` and `to` are inclusive bounds rather than named-period presets; using the same phrase on both sides narrows the query to that one resolved interval.
- Notes are normalized into typed models.
- Full note fetches now return a lean structured record with `noteID`, `title`, canonical template-aware `content`, tags, timestamps, version, and per-file attachment records including Bear's attachment search text when available. The exposed note `version` now tracks Bear's changing SQLite row revision field (`Z_OPT`) rather than the mostly static `ZVERSION` column.
- Attached file OCR/index text currently comes from `ZSFNOTEFILE.ZSEARCHTEXT` and is returned separately from note content.

### Config behavior

- Missing config keys fall back to defaults in memory during load.
- `bear-mcp --update-config` rewrites `config.json` in canonical current format, preserving existing values while filling in any newer keys.
- `backupRetentionDays` controls durable backup retention under Application Support. `0` disables capture and prunes stored backups.

### Mutation side

- Create builds final text locally, then uses Bear x-callback create.
- Create uses a config-driven default for whether the new note opens at all, plus config-driven open style defaults when it does open.
- Create uses config `tagsMergeMode` as the default for how requested tags combine with configured active tags, and `bear_create_notes` can override that per operation with `use_only_request_tags` when the user explicitly asks.
- Before note-destructive mutations (`bear_insert_text`, `bear_replace_content`, `bear_add_files`, and `bear_restore_notes`), the service now captures one pre-mutation backup snapshot per logical note operation in a durable file-backed store under Application Support. Template-aware multi-step add-file flows snapshot only once before internal anchor writes so backup history does not include temporary transport states.
- Note-targeting mutation tools now accept title-or-ID selectors at the MCP surface. Selectors resolve as exact note id first, then exact case-insensitive title across notes and archive, and ambiguous title matches require the note id.
- Insert now tries to preserve the active note template: when template management is enabled and the current note matches the active `template.md`, the service inserts inside the `{{content}}` region locally and writes the full note back through `replace_all`; otherwise it falls back to Bear's direct add-text prepend/append path. Omitted `position` still defaults to config `defaultInsertPosition`.
- Replace content computes full new note text locally from title/body/content-scoped edit intents, then writes through add-text with `replace_all`.
- For note-opening mutation flows, omitted `new_window` now consistently falls back to config `openUsesNewWindowByDefault`.
- Add file now defaults omitted `position` to config `defaultInsertPosition`, base64-encodes the local file payload for Bear's documented `add-file` URL parameters, and preserves active template boundaries when possible by inserting through a temporary backend-only header anchor inside the `{{content}}` region before cleaning that anchor back out with `replace_all`. Cleanup now tolerates Bear rewriting the anchor line by appending the attachment inline instead of leaving the header on its own line. In the template-aware path, Bear's header-targeted add-file call always uses `prepend`; top/bottom placement is determined by whether the temporary anchor is inserted at the top or bottom of the content region.
- `bear_list_backups` returns compact snapshot summaries for one note or across notes, `bear_delete_backups` deletes one explicit `snapshot_id` or clears one note's saved backup history when `delete_all: true` is paired with a note selector, and `bear_restore_notes` restores either the latest saved snapshot for a note or an explicit `snapshot_id`.
- Open tag uses Bear open-tag for a single canonical tag name and returns a compact UI-action receipt rather than note data.
- Rename tags use Bear rename-tag with batched `operations: []` input and only send `show_window` when the caller explicitly requests it.
- Open uses Bear open-note.
- Archive uses Bear archive.

### Receipt behavior

- Mutations return compact receipts by design.
- Create currently uses best-effort note discovery by title and recent modification time.
- Other mutations try to verify completion by polling Bear's DB for concrete note-state changes such as version, modified timestamp, raw text, and attachment-count deltas rather than relying on version bumps alone.
- Tag rename uses best-effort verification by polling tag lists across both notes and archive locations.

## Known Gaps / Risks

- Live write behavior has not yet been validated end-to-end for every Bear x-callback action.
- Create receipt matching is heuristic and may be ambiguous when titles collide.
- Token/keychain-backed x-callback actions are not wired yet.
- Backup restore is strongest for note-text mistakes. Attachment-related rollback is still best-effort because restoring saved raw markdown cannot perfectly model every Bear attachment side effect.
- Find now has deterministic text-aware ranking, but it still does not use fuzzy matching, typo tolerance, stemming, BM25, or SQLite FTS scoring.
- Runtime config directory is still named `bear-mcp`; migrating it to `bear-inbox` would be a separate compatibility decision.
- Debug tracing now writes under `~/Library/Logs/bear-mcp/debug.log` with simple size-based rotation.
- The preferred shared runtime lock lives under `~/Library/Application Support/bear-mcp/Runtime/.server.lock` so the user-facing config folder only contains editable files.
- When Codex launches additional stdio MCP children while another Bear server is already active, the runtime now falls back to temp per-launch lock files instead of refusing to start.
- The stdio server now shuts down on either transport EOF or loss of the original parent PID so Codex restarts do not leave orphaned MCP instances holding the lock.
- When the preferred Application Support lock path is not writable under the client sandbox, the server falls back to a temp-directory lock path so Codex can still launch the MCP process.

## User Preferences That Should Survive Future Threads

- Favor easy local installation and eventual GitHub sharing.
- Keep the local MCP architecture first-class; remote/proxy work is a separate project.
- Keep the old Alter/Shortcuts bridge untouched.
- The create template matters for creation behavior, tag placement, and template-aware insert positioning.
- The MCP surface should stay simple: note mutation tools only expose `open_note` and `new_window`, `bear_open_notes` only exposes `new_window`, `bear_open_tag` accepts a single canonical `tag`, and `bear_rename_tags` only exposes optional `show_window`.
- Create defaults are config-driven for whether creation opens the note; explicit `open_note` and `new_window` values override config for that request.
- User-overridable defaults should be reflected in MCP tool descriptions using the live loaded config, but internal-only config should stay out of the schema text.
- User phrasing like "floating window" should map to `new_window`; the server should not emit Bear's `float` URL parameter.
- Bear x-callback URLs should use an action-aware activation policy: UI-navigation actions and note-opening mutations foreground Bear, while background mutations stay unfocused.
- Presentation flags in MCP mutation inputs are optional overrides and should normally be omitted so config defaults apply.
- Batch operations matter.
- Returning giant note bodies after mutations wastes tokens and should usually be avoided.
- The project name `aft-bear` was rejected.
- The likely public repo name is now `bear-inbox`.
- The MCP itself being named `bear` is acceptable.

## Recommended Next Steps

1. Add keychain token support and any token-dependent Bear actions that are worth exposing.
2. Improve create-result identification so note IDs are returned more reliably.
3. Decide whether runtime paths should stay `bear-mcp` or migrate to `bear-inbox`.
4. Add README/install docs now that the create/write path has been validated live.
