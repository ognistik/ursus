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

- `bear_replace_note_body` should build the new full note content programmatically outside Bear.
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
- restore
- unarchive

### 6. Scope / active notes

The old `get-active` behavior is important.

Current direction:

- represent this as a scope concept
- `active` scope is driven by configured active tags
- this is read from config, not hardcoded into the MCP protocol

## Current Code Status

As of 2026-03-24, the repo contains a working initial scaffold.

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
- CLI commands: `mcp`, `doctor`, `paths`
- a few core tests

Verified locally:

- `swift build`
- `swift test`
- `swift run bear-mcp doctor`

## Current Tool Surface

Implemented MCP tool names:

- `bear_search_notes`
- `bear_get_notes`
- `bear_list_tags`
- `bear_get_notes_by_tag`
- `bear_get_scope_notes`
- `bear_create_notes`
- `bear_insert_text`
- `bear_replace_note_body`
- `bear_add_files`
- `bear_open_notes`
- `bear_archive_notes`

## Current File Map

Primary files:

- `Package.swift`
- `Sources/BearDB/BearDatabaseReader.swift`
- `Sources/BearApplication/BearService.swift`
- `Sources/BearXCallback/BearXCallbackURLBuilder.swift`
- `Sources/BearXCallback/BearXCallbackTransport.swift`
- `Sources/BearMCP/BearMCPServer.swift`
- `Sources/BearMCPCLI/main.swift`
- `docs/ARCHITECTURE.md`

## Current Runtime Paths

Current local runtime paths are:

- config: `~/.config/bear-mcp/config.json`
- note template: `~/.config/bear-mcp/template.md`
- process lock (preferred shared path): `~/Library/Application Support/bear-mcp/Runtime/.server.lock`
- process lock (contention/temp fallback): `TMPDIR/bear-mcp/Runtime/.server.lock` and `TMPDIR/bear-mcp/Runtime/locks/<pid>.server.lock`
- temporary debug log: `~/Library/Logs/bear-mcp/debug.log`
- default Bear DB path:
  `/Users/ognistik/Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/Application Data/database.sqlite`

Important: repo/GitHub naming can change to `bear-inbox` without immediately changing these runtime paths.

## Important Implementation Details

### Search/read side

- The current DB reader queries `ZSFNOTE`, `ZSFNOTETAG`, and `Z_5TAGS`.
- Search currently uses straightforward SQL `LIKE` matching over title and text.
- Notes are normalized into typed models.
- Returned notes include `title`, `body`, `rawText`, tags, and note revision metadata.

### Mutation side

- Create builds final text locally, then uses Bear x-callback create.
- Create uses a config-driven default for whether the new note opens at all, plus config-driven open style defaults when it does open.
- Insert uses Bear add-text with prepend/append mapping.
- Replace computes full new note text locally, then writes through add-text with `replace_all`.
- Add file uses Bear add-file.
- Open uses Bear open-note.
- Archive uses Bear archive.

### Receipt behavior

- Mutations return compact receipts by design.
- Create currently uses best-effort note discovery by title and recent modification time.
- Other mutations try to verify completion by polling Bear's DB for version/state changes.

## Known Gaps / Risks

- Live write behavior has not yet been validated end-to-end for every Bear x-callback action.
- Create receipt matching is heuristic and may be ambiguous when titles collide.
- Token/keychain-backed x-callback actions are not wired yet.
- Tag mutation tools are not implemented yet.
- Search is functional but still basic; exact phrase semantics and better ranking can be improved later.
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
- The create template matters for creation behavior and tag placement.
- The MCP surface should stay simple: mutation tools only expose `open_note` and `new_window`, and `bear_open_notes` only exposes `new_window`.
- Create defaults are config-driven for whether creation opens the note; explicit `open_note` and `new_window` values override config for that request.
- User phrasing like "floating window" should map to `new_window`; the server should not emit Bear's `float` URL parameter.
- Bear x-callback URLs should launch without activating Bear unless Bear itself decides to foreground for its own reasons.
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
