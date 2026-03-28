# AGENTS.md

Read [PROJECT_STATUS.md](/Users/ognistik/Documents/GitHubRepos/bear-mcp/PROJECT_STATUS.md) before making substantial changes.

## Project Identity

- Current MCP server name exposed to clients is `bear`.
- Do not rename package targets, binary names, config paths, or MCP tool names unless the user explicitly asks for that migration.

## Product Rules

- This is a Bear-specific local MCP server for macOS.
- Reads come from Bear's local SQLite database.
- Writes go through Bear's x-callback-url scheme.
- Do not write directly to Bear's SQLite database.
- Do not rebuild the old AppleScript/Shortcuts bridge into the new runtime.
- Do not turn the MCP surface into one giant `bear_action` tool.

## Important User Preferences

- The old Alter schema and AppleScript bridge are reference material only and must not be modified.
- Batch operations are important. Prefer `operations: []` inputs for mutation tools.
- `bear_replace_note_body` should compute the full note text locally, then commit through Bear's full replacement path.
- That replacement flow may be used for title changes when the leading title markdown is changed.
- Discovery tools should return compact note summaries, while `bear_get_notes` remains the full-note fetch. Inbox-note discovery is driven by configured inbox tags.
- Mutation tools should return compact receipts, not full note bodies, unless the user explicitly asks for content.
- Trash/restore are intentionally excluded for now.

## Current Technical Direction

- Config and templates currently live under `~/.config/bear-mcp`.
- Create-note templates are currently single-file `template.md`, not separate header/footer files.
- The current read adapter is real and queries the installed Bear database schema.
- The current write adapter launches Bear URLs and uses best-effort DB polling for mutation receipts.
- The MCP server should run as a single instance; startup now takes a process lock to prevent stale concurrent servers.
- Temporary debug tracing may be written under `~/.config/bear-mcp/debug.log` while write behavior is being validated.

## Working Style

- Preserve the current layered structure: `BearCore`, `BearDB`, `BearXCallback`, `BearApplication`, `BearMCP`, `BearMCPCLI`.
- Prefer real implementation over stubs when local context is available.
- Keep docs and status files updated when architecture or scope changes.
