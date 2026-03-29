# PROJECT_STATUS.md

This file is the concise handoff for future threads. It should describe the current product truth, not preserve every historical phase in detail.

## Project Identity

- Swift package / CLI name: `bear-mcp`
- MCP server name exposed to clients: `bear`
- Product shell: `Bear MCP.app`
- Platform: local macOS only

## Locked Product Rules

- Reads come from Bear's local SQLite database.
- Writes go through Bear's x-callback-url actions.
- Do not write directly to Bear's SQLite database.
- Do not rebuild the old AppleScript / Shortcuts bridge into this runtime.
- Keep the MCP surface explicit and batch-friendly rather than collapsing into one giant action tool.
- Keep the current layered structure: `BearCore`, `BearDB`, `BearXCallback`, `BearApplication`, `BearMCP`, `BearMCPCLI`.
- Keep template storage as one real file at `~/.config/bear-mcp/template.md`.
- Trash stays CLI-only for now unless the user explicitly asks to expose it through MCP.

## Current Product Shape

The repo already has the app-centered architecture we wanted:

- `Bear MCP.app` is the control center for diagnostics, host guidance, token/config management, and launcher repair.
- The bundled `bear-mcp` CLI remains the canonical local stdio MCP runtime.
- The app installs or repairs one public launcher at `~/.local/bin/bear-mcp`.
- Selected-note resolution prefers the installed app path and keeps the standalone helper only as a narrow fallback.
- Host guidance is generic-first, with Codex and Claude Desktop treated as convenience integrations rather than the product definition.

## Current Working Surface

### App

- Overview, Hosts, Configuration, and Token tabs exist.
- Configuration edits auto-save with validation.
- The app can install or repair the public launcher.
- The app still exposes a lot of implementation detail and is ready for simplification.

### CLI

Current direct utility commands:

- `bear-mcp --new-note`
- `bear-mcp --apply-template [note-id-or-title ...]`
- `bear-mcp --delete-note [note-id-or-title ...]`

Behavior already in place:

- `--new-note` creates a templated editing note.
- Default title format is `yyMMdd - hh:mm a`.
- Default create behavior uses `open_note=yes`, `new_window=no`, and `edit=yes`.
- If a selected note is available, `--new-note` copies that note's tags.
- If selected-note tags are unavailable, it falls back to configured inbox tags.
- `--apply-template` and `--delete-note` target the selected Bear note when called without arguments.
- Passed note arguments resolve as exact note id first, then exact case-insensitive title.

Legacy maintenance command still present in code:

- `bear-mcp --update-config`

Treat that flag as temporary compatibility code. It should be removed once the app fully owns the remaining config/template management flows.

### MCP

The main MCP surface is already broad and usable. Implemented tools include:

- discovery: `bear_find_notes`, `bear_find_notes_by_tag`, `bear_find_notes_by_inbox_tags`, `bear_get_notes`, `bear_list_tags`
- backups: `bear_list_backups`, `bear_delete_backups`, `bear_restore_notes`
- tag/navigation: `bear_open_tag`, `bear_open_notes`, `bear_rename_tags`, `bear_delete_tags`, `bear_add_tags`, `bear_remove_tags`
- note mutation: `bear_apply_template`, `bear_create_notes`, `bear_insert_text`, `bear_replace_content`, `bear_add_files`, `bear_archive_notes`

## Current Runtime Paths

These paths describe the codebase as it exists today:

- config file: `~/.config/bear-mcp/config.json`
- template: `~/.config/bear-mcp/template.md`
- public launcher: `~/.local/bin/bear-mcp`
- app support root: `~/Library/Application Support/bear-mcp`
- backups: `~/Library/Application Support/bear-mcp/Backups`
- runtime lock: `~/Library/Application Support/bear-mcp/Runtime/.server.lock`
- temp fallback locks: `TMPDIR/bear-mcp/Runtime/...`
- debug log: `~/Library/Logs/bear-mcp/debug.log`

Important: the current runtime path layout is expected to change in the next cleanup pass. The planned target is to keep config/template where they are, but move runtime artifacts under `~/Library/Application Support/Bear MCP` and keep logs there instead of under `~/Library/Logs`.

## Current Technical Truths

- Config and template editing are JSON / file based under `~/.config/bear-mcp`.
- The selected-note token is currently managed in Bear MCP's config flow, not in Keychain.
- Discovery tools return compact note summaries; `bear_get_notes` remains the full-note fetch.
- Mutation receipts should stay compact unless the user explicitly asks for content.
- `bear_replace_content` computes the final full note body locally, then commits through Bear's full replacement path.
- Batch operations matter and should stay first-class.

## Documentation Cleanup Decisions

This repo had started to accumulate too much historical planning text. The working documentation set should now be:

- `PROJECT_STATUS.md`: current truth and next queue
- `docs/ARCHITECTURE.md`: current runtime and behavior shape
- `docs/APP_UNIFICATION_PLAN.md`: short live roadmap
- `docs/LOCAL_BUILD_AND_CLEAN_INSTALL.md`: practical local build / reset guide
- `docs/SELECTED_NOTE_HELPER.md`: small fallback note for the standalone helper path

Helper-only release/testing duplication should not come back unless the fallback helper becomes a primary product again.

## Next Implementation Queue

This is the intended order of work after the doc cleanup:

1. Add app-managed template editing and validation inside `Bear MCP.app`.
2. Remove stale `--update-config` compatibility code once the app owns the remaining config/template flow.
3. Migrate the app bundle identifier to `com.aft.bearmcp`.
4. Rename the Application Support root from `~/Library/Application Support/bear-mcp` to `~/Library/Application Support/Bear MCP`, with logs kept inside that root.
5. Add `bear-mcp --archive-note [note-id-or-title ...]`, matching the same selector behavior used by `--delete-note` and `--apply-template`.
6. Expand `bear-mcp --new-note` so callers can override title, tags, tag-merge behavior, content, and open/window behavior from flags while preserving current no-argument behavior.
7. Simplify the app UI once template management has moved into the app.

## Details For The Next Slice

### 1. App-managed template editing

Desired behavior:

- show the real `template.md` path in the app
- open / reveal that file from the app
- support inline editing in the app, similar to config editing
- validate that the template contains valid `{{content}}` and `{{tags}}` slots before save
- show clear warnings and errors in the app
- keep `~/.config/bear-mcp/template.md` as the source of truth

### 2. `--new-note` expansion

Desired behavior:

- `bear-mcp --new-note` with no extra flags should behave exactly as it does now
- when explicit creation flags are passed, the user can override title, tags, tag merge mode, content, open-note behavior, and new-window behavior
- in the explicit-flags path, selected-note text should not be consulted
- if the user does not pass tags in that explicit path, the default should be inbox tags
- append remains the default tag merge mode unless explicitly overridden

### 3. Naming / path cleanup

Desired behavior:

- app bundle identifier becomes `com.aft.bearmcp`
- repo/user-specific identifiers should stop leaking into app-facing metadata
- runtime artifacts should live under `~/Library/Application Support/Bear MCP`
- debug logs should no longer write to `~/Library/Logs/bear-mcp`

This migration should be done carefully and deliberately so existing local installs do not silently lose runtime state.

## Verification Baseline

When the next implementation slice lands, the standard verification should include:

- `swift test`
- `CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh`

Add command-specific verification as appropriate for whichever slice is being worked on.
