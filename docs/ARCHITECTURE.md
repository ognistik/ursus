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
- The MCP surface keeps mutation-time presentation intentionally small: create/insert/replace/add-file only expose `open_note` and `new_window`, while `bear_open_notes` only exposes `new_window`. Those presentation fields are optional overrides and should normally be omitted so config defaults apply. Explicit `open_note` and `new_window` values override config for that request. When a note is not being opened, open-only URL flags are suppressed. User requests for a separate or floating Bear window map to `new_window`; the server does not emit Bear's `float` URL parameter.
- Bear x-callback URLs are launched with app activation suppressed so background mutations do not steal focus from the current app.
- `bear-mcp mcp` is intended to run as a single local server instance; startup takes a process lock so stale concurrent instances do not diverge on config or behavior.
- Batch inputs are supported at the MCP layer with `operations: []`.
- Config and the create-note template live under `~/.config/bear-mcp`.
- Runtime artifacts are kept out of the config folder: the lock file lives under `~/Library/Application Support/bear-mcp/Runtime/.server.lock` and debug traces live under `~/Library/Logs/bear-mcp/debug.log`.
- The server does not currently expose Bear resources, but it answers empty `resources/list` and `resources/templates/list` requests so MCP clients that probe those endpoints during discovery do not treat the server as broken.

## Current limits

- Token-backed x-callback actions are not wired yet.
- Create receipts use best-effort note discovery by title and recent modification time.
- Tag mutations are not implemented yet.
- Debug tracing uses a simple file under `~/Library/Logs/bear-mcp` with size-based rotation.
