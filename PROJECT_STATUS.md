# PROJECT_STATUS.md

This file is the concise handoff for future threads. It should describe the current product truth, not preserve every historical phase in detail.

## Project Identity

- Swift package / CLI name: `bear-mcp`
- MCP server name exposed to clients: `bear`
- Product shell: `Bear MCP.app`
- App bundle identifier: `com.aft.bearmcp`
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
- Selected-note resolution uses the embedded helper bundled inside the installed app.
- Host guidance is generic-first, with Codex and Claude Desktop treated as convenience integrations rather than the product definition.

## Current Working Surface

### App

- Overview, Hosts, Configuration, and Token tabs exist.
- Configuration edits auto-save with validation.
- Configuration now also includes inline template editing for `~/.config/bear-mcp/template.md`, with open/reveal actions and pre-save slot validation.
- The app can install or repair the public launcher.
- The app still exposes a lot of implementation detail and is ready for simplification.

### CLI

Current direct utility commands:

- `bear-mcp --new-note`
- `bear-mcp --apply-template [note-id-or-title ...]`
- `bear-mcp --archive-note [note-id-or-title ...]`
- `bear-mcp --delete-note [note-id-or-title ...]`

Behavior already in place:

- `--new-note` creates a templated editing note.
- Default title format is `yyMMdd - hh:mm a`.
- Default create behavior uses `open_note=yes`, `new_window=no`, and `edit=yes`.
- If a selected note is available, `--new-note` copies that note's tags.
- If selected-note tags are unavailable, it falls back to configured inbox tags.
- `--apply-template`, `--archive-note`, and `--delete-note` target the selected Bear note when called without arguments.
- Passed note arguments resolve as exact note id first, then exact case-insensitive title.

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
- app support root: `~/Library/Application Support/Bear MCP`
- backups: `~/Library/Application Support/Bear MCP/Backups`
- runtime lock: `~/Library/Application Support/Bear MCP/Runtime/.server.lock`
- temp fallback locks: `TMPDIR/bear-mcp/Runtime/...`
- debug log: `~/Library/Application Support/Bear MCP/Logs/debug.log`

Startup now migrates legacy runtime state from `~/Library/Application Support/bear-mcp` and legacy debug logs from `~/Library/Logs/bear-mcp` into the current Bear MCP support root when possible.

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
- `docs/SELECTED_NOTE_HELPER.md`: short note about the embedded helper used for selected-note resolution

Helper-only release/testing duplication should not come back unless the embedded helper packaging itself needs dedicated work again.

## Next Implementation Queue

This is the intended order of work after the doc cleanup:

1. Expand `bear-mcp --new-note` so callers can override title, tags, tag-merge behavior, content, and open/window behavior from flags while preserving current no-argument behavior.
2. Simplify the app UI now that template management has moved into the app.

## Details For The Next Slice

### 1. `--new-note` expansion

Desired behavior:

- `bear-mcp --new-note` with no extra flags should behave exactly as it does now
- when explicit creation flags are passed, the user can override title, tags, tag merge mode, content, open-note behavior, and new-window behavior
- in the explicit-flags path, selected-note text should not be consulted
- if the user does not pass tags in that explicit path, the default should be inbox tags
- append remains the default tag merge mode unless explicitly overridden

## Verification Baseline

When the next implementation slice lands, the standard verification should include:

- `swift test`
- `CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh`

Add command-specific verification as appropriate for whichever slice is being worked on.
