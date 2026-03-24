# bear-mcp Architecture

`bear-mcp` is a local stdio MCP server for Bear on macOS.

## Layers

- `BearCore`: domain types, config paths, template rendering, and shared errors.
- `BearDB`: read-only access to Bear's SQLite database through GRDB.
- `BearXCallback`: Bear mutation URL construction and Bear app launching.
- `BearApplication`: orchestration, mutation planning, version guards, and bootstrap files.
- `BearMCP`: MCP tool registration and argument decoding.
- `BearMCPCLI`: executable entrypoint for `mcp`, `doctor`, and `paths`.

## Current v1 shape

- Reads come directly from Bear's local SQLite database.
- Mutations are submitted through Bear's official x-callback actions.
- `bear_replace_note_body` computes the full note markdown locally, then writes with Bear's `replace_all` mode.
- `bear_create_notes` builds the final note text locally from a single `template.md`, merges configured active tags with any explicit request tags, and sends tags inside the note text instead of Bear's `tags=` create parameter.
- `bear-mcp mcp` is intended to run as a single local server instance; startup takes a process lock so stale concurrent instances do not diverge on config or behavior.
- Batch inputs are supported at the MCP layer with `operations: []`.
- Config and the create-note template live under `~/.config/bear-mcp`.
- Runtime artifacts are kept out of the config folder: the lock file lives under `~/Library/Application Support/bear-mcp/Runtime/.server.lock` and debug traces live under `~/Library/Logs/bear-mcp/debug.log`.

## Current limits

- Token-backed x-callback actions are not wired yet.
- Create receipts use best-effort note discovery by title and recent modification time.
- Tag mutations are not implemented yet.
- Debug tracing uses a simple file under `~/Library/Logs/bear-mcp` with size-based rotation.
