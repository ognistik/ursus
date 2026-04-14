# Ursus Architecture

`Ursus` is a local macOS MCP runtime for Bear. The canonical server is stdio MCP; `Ursus.app` can optionally install a loopback HTTP bridge for hosts that only speak MCP over HTTP.

## Layers

- `BearCore`: domain types, config paths, template rendering, bridge settings, selected-note token storage, process/runtime paths, and shared errors.
- `BearDB`: read-only access to Bear's SQLite database through GRDB.
- `BearXCallback`: Bear mutation URL construction, Bear app launching, x-callback transport, and selected-note callback-host logic.
- `BearApplication`: orchestration, mutation planning, bootstrap files, backups, runtime state, app support snapshots, and bridge LaunchAgent/status management.
- `BearMCP`: MCP tool registration, argument decoding, tool catalog generation, and successful-operation counting.
- `BearCLIRuntime`: shared CLI and bridge runtime, mapped to `Sources/BearMCPCLI`, used by both the standalone `ursus` executable and the app binary's hidden CLI mode.
- `BearMCPCLI`: tiny executable wrapper at `Sources/BearMCPCLIExecutable` that imports `BearCLIRuntime`.
- `BearSelectedNoteHelper`: background helper executable bundled as `Ursus Helper.app`.
- `Ursus.app`: native macOS control center in `UrsusApp.xcodeproj`, with one main dashboard window containing setup/preferences/tools UI, inline template editing, optional bridge controls, bridge access review, donation prompting, Sparkle update UI, and hidden CLI-mode entry through the main app executable.

## Read And Write Model

- Reads come directly from Bear's local SQLite database.
- Normal reads use a bounded backoff retry window on transient SQLite busy/locked errors so brief Bear write contention does not surface as tool failures, while still failing promptly on longer lockouts.
- Mutations are submitted through Bear's official x-callback actions. Ursus never writes directly to Bear's SQLite database.
- Bear x-callback URLs use an action-aware activation policy: UI navigation and requested note opens foreground Bear, while background mutations send `open_note=no` plus `show_window=no`.
- Debug traces log x-callback action/query summaries while redacting token-bearing callback URLs and large `text` / `file` payload values.

## MCP Surface

- Discovery tools return compact summaries: `bear_find_notes`, `bear_find_notes_by_tag`, and `bear_find_notes_by_inbox_tags`.
- Full note content comes from `bear_get_notes`, which is not intended as a selector-resolution preflight for note-targeting mutations.
- Reads exclude trashed notes and target normal notes by default; archive reads require explicit `location: archive`.
- `bear_list_tags` is location-scoped, excludes trashed/permanently deleted notes, and supports `query` plus hierarchical `under_tag` filtering.
- Discovery inputs use required non-empty `operations` arrays. Each operation can return either a summary page or an inline error without failing sibling operations.
- Discovery page size and snippet length come from config; MCP discovery inputs do not accept per-call `limit` or `snippet_length`.
- Pagination uses opaque cursors keyed by the normalized filter set and internal sort key.
- Text discovery ranking is deterministic: exact phrase matches first, then ordered terms, unordered all-term matches, modified date, and note id.
- Discovery summaries include template-aware snippets, `hasAttachments`, matched fields for text searches, and optional `hasBackups`. Attachment OCR/search text never appears in discovery output.
- `bear_get_notes` returns a canonical `content` field, strips template wrapper noise when the current template matches, and returns attachment metadata by default. Attachment OCR/search text is opt-in through `include_attachment_text: true`.
- The MCP server does not expose Bear resources, but answers empty `resources/list` and `resources/templates/list` requests for client compatibility.
- Tool descriptions are built from loaded config at startup so user-overridable defaults are visible in the tool catalog.
- MCP initialization advertises the human-readable server title `Ursus`, and the HTTP bridge includes themed SVG `serverInfo.icons` metadata for clients that support server branding.

## Mutation Planning

- Note-targeting mutations accept exact note ids or exact case-insensitive titles; ambiguous titles require a note id.
- When selected-note token availability is present, note-targeting tools can also accept `selected: true`.
- `bear_replace_content` computes final full note markdown locally and commits through Bear's `replace_all` mode. Title edits rebuild the note with the new title; body/string edits are limited to editable content.
- Before note-destructive mutations, the service captures one durable pre-mutation backup snapshot per logical note operation.
- `bear_create_notes` renders one `template.md`, merges configured inbox tags with explicit request tags according to config/request overrides, and writes tags into note text rather than Bear's `tags=` create parameter.
- `bear_insert_text` and `bear_add_files` preserve templated note structure when possible. Relative placements are planned locally against editable content and committed through full replacement after any backend attachment anchoring is cleaned up.
- Tag handling uses bare tag names internally and renders Bear markdown syntax only at the boundary.
- Template-aware reads and note-tag mutations parse literal tag tokens from stored note text instead of using Bear's DB-expanded effective tag list as write-back source of truth.
- `bear_add_tags` prefers a matched template `{{tags}}` slot, then raw tag-only clusters, then template/default-position fallback.
- `bear_remove_tags` strips literal tag tokens from raw body text with whitespace cleanup.
- `bear_apply_template` always loads the current `template.md`, migrates tag-only clusters into the `{{tags}}` slot, preserves inline prose hashtags, and fails clearly if the template is missing required `{{content}}` / `{{tags}}` slots.
- Mutation-time presentation stays narrow: `bear_create_notes` exposes config-driven `open_note` / `new_window`, `bear_open_notes` exposes `new_window`, and other note/tag mutation tools do not expose presentation overrides.

## Backups

- Durable snapshots live under `~/Library/Application Support/Ursus/Backups/<note-id>/<snapshot-id>.json`.
- Rebuildable metadata lives in `~/Library/Application Support/Ursus/backups.sqlite`.
- Malformed or ambiguous files are quarantined under `Backups/_quarantine`.
- The backup store keeps a lightweight tree fingerprint so normal access can skip expensive recursive reconciliation unless the filesystem changes.
- `bear_create_backups` reuses the manual capture path.
- `bear_list_backups` is note-scoped, paginated by `captured_at` plus `snapshot_id`, and supports inclusive `from` / `to` filters.
- `bear_compare_backup` returns compact metadata plus bounded diff hunks.
- `bear_delete_backups` removes one snapshot or clears one note's backup history.
- `bear_restore_notes` restores a snapshot primarily for note-text rollback. Attachment-related rollback remains best-effort because Bear may perform attachment-side rewrites.

## Selected-Note Helper

- Selected-note resolution uses Bear's token-backed `open-note?selected=yes` flow plus an embedded helper app, not a foreground app-host callback path.
- The helper bundle is `Ursus Helper.app`; the executable product is `ursus-helper`; the callback scheme is `ursushelper://`.
- The helper is background-only and on-demand. It launches for the callback round trip, receives Bear's callback without foregrounding the visible app, writes the response-file JSON payload expected by the CLI runtime, then exits.
- Managed-token injection is shared so the helper can prepare Bear request URLs without exposing token-bearing callback URLs in user-facing layers.
- Helper lookup prefers the most recently opened `Ursus.app` path recorded in runtime state, then falls back to `/Applications/Ursus.app` and `~/Applications/Ursus.app`.
- The helper is signed without restricted entitlements because it does not read the selected-note token directly.
- Direct helper bundle builds are only needed for helper packaging or callback work:

```sh
Support/scripts/build-ursus-helper-app.sh
CONFIGURATION=Release Support/scripts/build-ursus-helper-app.sh
```

The helper bundle version follows the app target's Xcode `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.

## CLI And App Runtime

- Running `ursus` with no command starts the stdio MCP server.
- The terminal-facing CLI also supports `note` subcommands, `update` subcommands, `doctor`, `paths`, and bridge utility commands.
- The app owns the in-bundle launch path at `Ursus.app/Contents/MacOS/Ursus`.
- The public launcher at `~/.local/bin/ursus` resolves to the app executable with a hidden `--ursus-cli` flag, so replacing `Ursus.app` updates Terminal and bridge launches together.
- Opening `Ursus.app` reconciles that public launcher automatically, so Setup-driven host installs and repairs can target one shared launcher path before they rewrite host configs.
- Embedded CLI runs launched through the app bundle receive a Sparkle update-checking hook from the app target. `ursus mcp` and `ursus bridge serve` start Sparkle's scheduled check cycle for the long-running MCP surfaces using a background `SPUUpdater` user driver that does not register the bridge as the visible app. Sparkle's scheduled interval is fixed at 3 hours through the app bundle configuration so app, stdio MCP, and bridge surfaces share one cadence. When that background check finds an update, or when the user runs `ursus update check`, Ursus hands off to a normal foreground app process in Sparkle-only mode so the standard Sparkle UI owns a real AppKit lifecycle without opening the dashboard. Ordinary short-lived CLI commands do not participate in Sparkle's scheduled checks.
- Sparkle behavior is intentionally split by initiation mode. User-initiated checks (`ursus update check` and the app UI's "Check for Updates…") may show Sparkle's normal "no updates available" result. Background bridge / stdio scheduled checks stay silent when no update is found or when the check errors; they only foreground Sparkle when an update is actually available.
- The Sparkle-only foreground handoff must continue using the same `Ursus.app` executable, not a separate helper app and not the hidden embedded CLI path. This avoids the stuck-process / unfocusable-dialog failures caused by trying to present Sparkle UI from the wrong process role.
- Sparkle-only mode is a focused update surface, not the dashboard. It should not open the main Ursus window just to present update UI unless a normal regular app instance is already the one consuming the request.
- `defaults delete com.aft.ursus SULastCheckTime` is the supported local reset for verifying scheduled update behavior. After clearing that key, restarting `ursus bridge serve` or `ursus mcp` should make Sparkle treat the next scheduled check as overdue and perform it promptly.
- Long-running bridge / stdio processes are expected to keep Sparkle scheduling alive for days at a time. Sparkle maintains its own next-check timer inside that running process, so leaving bridge / MCP running should continue 3-hour checks without requiring the dashboard app to stay open.
- `ursus mcp` prefers a shared Application Support runtime lock and falls back to temp per-launch locks when hosts open additional stdio MCP children.
- The stdio runtime exits when the MCP connection finishes or the original parent PID disappears.
- Config, template, backups, logs, bridge auth, process locks, and runtime state live under `~/Library/Application Support/Ursus`, with temp fallback locks under `TMPDIR/ursus/Runtime/...`.
- Runtime bootstrap does not migrate prerelease support roots or legacy debug logs forward; clean reset is the intended fallback for old prerelease state.

## HTTP Bridge

- The optional HTTP bridge runs through `ursus bridge serve`, reuses the same `BearService` stack as stdio MCP, binds to loopback, and exposes one MCP endpoint at the configured path, defaulting to `/mcp`.
- Plain JSON request/response clients work; clients that advertise `text/event-stream` receive one-shot SSE-formatted POST responses for MCP request calls.
- Remote connector clients should use the full MCP endpoint URL, for example `http://127.0.0.1:6190/mcp` locally or `https://your-domain.example/mcp` through a personal tunnel.
- In OAuth mode, the configured MCP endpoint is the only protected MCP route. Public OAuth routes live on the same origin: `/.well-known/oauth-protected-resource/...`, `/.well-known/oauth-authorization-server`, `/oauth/register`, `/oauth/authorize`, `/oauth/decision`, and `/oauth/token`.
- First-time bridge authorization is browser-first through `/oauth/authorize` and `/oauth/decision`; the old app-handoff polling route is gone.
- Public bridge OAuth origin metadata is derived from the incoming public host so tunneled HTTPS hosts do not leak the loopback port.
- OAuth routes and protected `/mcp` challenges answer CORS preflight and expose Bearer challenge headers for browser-based connector setup.
- `Ursus.app` remains the control center for bridge auth state and remembered-grant revocation.
- The app manages the bridge as a per-user LaunchAgent at `~/Library/LaunchAgents/com.aft.ursus.plist`, targeting `~/.local/bin/ursus bridge serve`.
- Bridge install/resume/restart waits for MCP `initialize` and `tools/list` probes. Repeated HTTP `initialize` requests return compatibility handshakes so hosts can reconnect cleanly.
- App-level Restart reuses the existing LaunchAgent plist when it still matches the expected launcher and log paths; Repair remains the heavier reinstall path for missing or drifted LaunchAgent artifacts.
- Bridge diagnostics combine LaunchAgent state, TCP reachability, MCP `initialize` health, and recent stdout/stderr log hints.
- Bridge runtime state records config drift inputs, selected-note token availability, and a hash of the served MCP surface. If MCP behavior changes in a way that `tools/list` will not reflect, bump `UrsusMCPServer.bridgeSurfaceEpoch`.

## Local Host Integrations

- The `Setup` tab's Connect Apps section lists only detected local hosts and keeps each row compact: app name, passive `Installed` indicator when healthy, one primary `Install` or `Repair` action when needed, and one trailing overflow menu for advanced actions.
- Host-app detection is launcher-centric rather than alias-centric: supported local hosts count as installed when an existing local stdio MCP entry already points at the shared `~/.local/bin/ursus` launcher, even if the user chose a custom server alias or omitted explicit `mcp` args. The destructive Remove action remains limited to Ursus-managed canonical entries so custom aliases are preserved.
- Supported local host integrations are currently `Codex`, `Claude Desktop`, and `Claude CLI`; remote-only clients stay outside this section.
- Host integration health is explicit per row: `Install` means no Ursus config is present, `Repair` means Ursus config exists but is stale or broken, and `Installed` means the host config is correct and the shared launcher exists and is executable.
- Install and repair are implemented per host rather than through a generic plugin layer: Codex rewrites `~/.codex/config.toml`, Claude Desktop merges `claude_desktop_config.json`, and Claude CLI merges `~/.claude.json`.
- Remove actions delete only Ursus's own host config entry. They do not uninstall `Ursus.app` and do not remove the shared launcher at `~/.local/bin/ursus`.
- Host config rewrites preserve unrelated settings, and destructive recovery plus Codex TOML rewrites create sibling backup files before the file is changed.

## App-Only Features

- Donation prompting is decoupled from runtime work. MCP code updates local eligibility state; `Ursus.app` presents the support prompt on open/activation.
- The app shell is intentionally single-window. The dashboard tabs are the only supported app surface, so Ursus does not expose a separate macOS Settings scene and disables the standard `New Window` / `Preferences…` menu commands.
- Successful user-meaningful MCP operations are counted centrally inside `UrsusMCPServer`; probes, OAuth setup routes, failed tool calls, and list/resource probes are excluded.
- Debug builds include hidden donation test commands; release builds keep threshold-only behavior.
- Sparkle is owned by the app target. Runtime layers expose only a small update-checking hook so stdio MCP / bridge launches can participate in Sparkle's scheduler without importing Sparkle directly.
- Runtime log retention keeps each log family to the active file plus one `.1` archive, and bridge removal deletes live plus archived bridge logs.

## Current Limits

- Token-backed x-callback actions are used for selected-note resolution through the embedded helper only; broader token-backed Bear actions remain unexposed.
- Create receipts use best-effort note discovery by title and recent modification time.
- Tag rename and delete use best-effort verification by polling tag lists across normal and archived note locations after Bear accepts the x-callback.
