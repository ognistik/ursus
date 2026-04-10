# AGENTS.md

Read [docs/MAINTAINER_NOTES.md](./docs/MAINTAINER_NOTES.md) before making substantial changes.

## Project Identity

- Current MCP server name exposed to clients is `ursus`.
- Do not rename package targets, binary names, config paths, or MCP tool names unless the user explicitly asks for that migration.

## Product Rules

- This is a Bear-specific local MCP server for macOS.
- Reads come from Bear's local SQLite database.
- Writes go through Bear's x-callback-url scheme.
- Do not write directly to Bear's SQLite database.
- Do not rebuild the old AppleScript/Shortcuts bridge into the new runtime.
- Do not turn the MCP surface into one giant `bear_action` tool.

## Important User Preferences

- Batch operations are important. Prefer non-empty `operations: [...]` inputs for mutation tools that support batching.
- The old Alter schema and AppleScript bridge are reference material only and must not be modified.
- `bear_replace_content` should compute the full note text locally, then commit through Bear's full replacement path.
- That replacement flow may be used for title changes when the leading title markdown is changed.
- Discovery tools should return compact note summaries, while `bear_get_notes` remains the full-note fetch. Inbox-note discovery is driven by configured inbox tags.
- Mutation tools should return compact receipts, not full note bodies, unless the user explicitly asks for content.
- Bear's own trash/restore flows are intentionally excluded from the MCP surface for now. Backup restore remains available through `bear_restore_notes`.

## Current Technical Direction

- Config and templates currently live under `~/Library/Application Support/Ursus`.
- Create-note templates are currently single-file `template.md`, not separate header/footer files.
- The current read adapter is real and queries the installed Bear database schema.
- The current write adapter launches Bear URLs and uses best-effort DB polling for mutation receipts.
- The MCP server should run as a single instance; startup now takes a process lock to prevent stale concurrent servers.
- Runtime artifacts live under `~/Library/Application Support/Ursus`.
- Debug tracing is written under `~/Library/Application Support/Ursus/Logs/debug.log` with size-based retention.
- Sparkle update UI must remain owned by the app executable. Long-running `ursus mcp` / `ursus bridge serve` use a background `SPUUpdater` scheduler and only hand off to foreground Sparkle UI when an update is actually available.
- Background Sparkle checks must stay silent on "no update" and on updater errors. User-initiated checks may show Sparkle's normal "up to date" UI.
- Do not make ordinary one-shot CLI commands participate in scheduled Sparkle checks or advance `SULastCheckTime`.
- Do not add another helper app for update presentation. Preserve the current Sparkle-only foreground mode in the main app executable and the separation between bridge process ownership and update UI ownership.
- If you touch Sparkle, bridge lifecycle, launcher behavior, or multi-process app/CLI handoff, update `docs/ARCHITECTURE.md` and `docs/MAINTAINER_NOTES.md` in the same change and preserve the documented invariants.

## Working Style

- Preserve the current layered structure: `BearCore`, `BearDB`, `BearXCallback`, `BearApplication`, `BearMCP`, `BearCLIRuntime`, `BearMCPCLI`.
- Prefer real implementation over stubs when local context is available.
- Keep docs and status files updated when architecture or scope changes.
