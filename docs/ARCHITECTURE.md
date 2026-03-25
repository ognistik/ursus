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
- Discovery tools (`bear_search_notes`, `bear_get_notes_by_tag`, and `bear_get_notes_by_active_tags`) return paged compact note summaries and reserve `bear_get_notes` for full structured note fetches.
- Discovery reads always exclude trashed notes and target either normal notes or archived notes explicitly through `location: notes|archive`.
- `bear_list_tags` defaults `location` to `notes`, excludes trashed and permanently deleted notes, returns location-scoped `noteCount`, and supports optional `query` and hierarchical `under_tag` filtering before tags are returned to clients.
- Tag tools are split by intent: `bear_list_tags` is discovery, `bear_get_notes_by_tag` is read, `bear_open_tag` is UI navigation for one known tag name, and `bear_rename_tags` is a batched mutation surface.
- `bear_get_notes` defaults `location` to `notes`, never returns trashed notes, resolves each selector as exact note id first and then exact case-insensitive title within the chosen location, and never mixes normal notes with archived notes in one call.
- MCP tool descriptions steer clients to omit `location` unless the user explicitly asks for archived notes, and tag-specific descriptions point clients back to `bear_list_tags` when a canonical tag name must be discovered first.
- Discovery snippet length and result-count defaults come from config, allow per-call overrides, are capped server-side, and page forward with opaque cursor-based continuation.
- Discovery snippets are template-aware when the current `template.md` can be matched back to the stored note body; otherwise they fall back to the parsed note body.
- Full note fetches expose a single canonical `content` field derived from normalized raw markdown, strip template wrapper noise when the current template matches, and return attachment metadata plus Bear's extracted attachment search text separately instead of duplicating `body` and `rawText`.
- `bear_replace_note_body` computes the full note markdown locally, then writes with Bear's `replace_all` mode.
- `bear_create_notes` builds the final note text locally from a single `template.md`, merges configured active tags with any explicit request tags, and sends tags inside the note text instead of Bear's `tags=` create parameter.
- Tag handling uses bare tag names internally. Rendering into note markdown applies Bear syntax: `#tag` for single-word tags and `#tag with spaces#` for tags that contain whitespace.
- Create-note tag merging follows config `tagsMergeMode` by default. `bear_create_notes` may override that per operation with `use_only_request_tags`, where `true` means use only the supplied request tags instead of configured active tags, `false` explicitly appends configured active tags, and omission uses the configured default. Omission is distinct from `false`: omission means use config, while an explicit boolean forces behavior for that request. If the user only asks to add tag X, clients should pass `tags` and omit `use_only_request_tags`. Clients should omit the override unless the user explicitly asks to change tag-merging behavior for that request.
- The MCP surface keeps mutation-time presentation intentionally small: create/insert/replace/add-file only expose `open_note` and `new_window`, `bear_open_notes` only exposes `new_window`, `bear_open_tag` exposes no presentation overrides, and `bear_rename_tags` only exposes optional `show_window`. Those optional fields should be omitted unless the user explicitly asks to change Bear's default window behavior for that request. Omission is distinct from `false`: omission means use config or Bear defaults, while an explicit boolean forces behavior for that request. If the user does not mention opening, clients should not send `open_note`. Explicit `open_note` and `new_window` values override config for that request. When a note is not being opened, open-only URL flags are suppressed. User requests for a separate or floating Bear window map to `new_window`; the server does not emit Bear's `float` URL parameter.
- Bear x-callback URLs are launched with app activation suppressed so background mutations do not steal focus from the current app.
- `bear-mcp mcp` still prefers a shared runtime lock for stale-process detection and predictable diagnostics, but it falls back to temp per-launch locks when Codex opens additional stdio MCP children.
- The stdio runtime exits when the MCP connection finishes or the original parent PID disappears, which prevents orphaned Codex-spawned servers from lingering after restarts.
- Batch inputs are supported at the MCP layer with `operations: []`.
- Config and the create-note template live under `~/.config/bear-mcp`.
- `bear-mcp --update-config` rewrites the config file in the latest canonical shape, preserving existing values and filling in any missing keys.
- Runtime artifacts are kept out of the config folder: the preferred lock file lives under `~/Library/Application Support/bear-mcp/Runtime/.server.lock`, with temp-directory fallback locks used when sandbox policy blocks that path or when another live stdio launch already holds the shared lock, and debug traces live under `~/Library/Logs/bear-mcp/debug.log`.
- The server does not currently expose Bear resources, but it answers empty `resources/list` and `resources/templates/list` requests so MCP clients that probe those endpoints during discovery do not treat the server as broken.

## Current limits

- Token-backed x-callback actions are not wired yet.
- Create receipts use best-effort note discovery by title and recent modification time.
- Tag rename uses best-effort verification by polling tag lists across both normal and archived note locations after Bear accepts the x-callback.
- Debug tracing uses a simple file under `~/Library/Logs/bear-mcp` with size-based rotation.
