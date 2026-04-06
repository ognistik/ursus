# PROJECT_STATUS.md

This file is the concise handoff for future threads. It should describe the current product truth, not preserve every historical phase in detail.

## Project Identity

- Swift package executable / CLI name: `ursus`
- Swift package name: `ursus`
- Selected-note helper executable: `ursus-helper`
- MCP server name exposed to clients: `ursus`
- Product shell: `Ursus.app`
- App bundle identifier: `com.aft.ursus`
- Helper bundle identifier: `com.aft.ursus-helper`
- Platform: local macOS only

## Locked Product Rules

- Reads come from Bear's local SQLite database.
- Writes go through Bear's x-callback-url actions.
- Do not write directly to Bear's SQLite database.
- Do not rebuild the old AppleScript / Shortcuts bridge into this runtime.
- Keep the MCP surface explicit and batch-friendly rather than collapsing into one giant action tool.
- Keep the current layered structure: `BearCore`, `BearDB`, `BearXCallback`, `BearApplication`, `BearMCP`, `BearCLIRuntime`, `BearMCPCLI`.
- Keep template storage as one real file at `~/Library/Application Support/Ursus/template.md`.
- Trash stays CLI-only for now unless the user explicitly asks to expose it through MCP.

## Current Product Shape

Phases 1 through 6 of the Ursus identity reset are complete:

- `Ursus.app` is now the product shell and control center.
- The standalone local stdio/runtime executable remains `ursus`.
- The app-owned in-bundle launch path is now `Ursus.app/Contents/MacOS/Ursus`, and the public launcher forwards into that executable with a hidden `--ursus-cli` flag so app-bundle replacement updates Terminal and bridge launches together without shipping a second embedded CLI copy.
- The embedded selected-note helper is now `Ursus Helper.app` / `ursus-helper`.
- MCP `initialize` now reports server name `ursus`.
- The bridge LaunchAgent label is now `com.aft.ursus`.
- Config, template, logs, backups, and runtime locks now live under `~/Library/Application Support/Ursus`.
- Temp fallback runtime locks now live under `TMPDIR/ursus/Runtime/...`.
- The public launcher path is now `~/.local/bin/ursus`.
- Launcher repair/install, bridge diagnostics, and CLI help/doctor/status output now point at the `ursus` launcher and `Ursus.app`.
- Selected-note helper lookup now prefers the embedded helper in the app bundle the user most recently opened, while still falling back to `/Applications/Ursus.app` and `~/Applications/Ursus.app` when needed.
- Host setup snippets and diagnostics now recommend `ursus` as the host-side server identity for Codex and Claude Desktop.
- Broader app copy now presents the product as Ursus while keeping Bear wording only for Bear-specific domains like the Bear database, Bear notes, and Bear tokens.
- Current docs, local build/reset guidance, and helper docs are aligned to the shipped Ursus identity.
- Repo-internal app/container paths and product-facing internal type names now use Ursus branding where they represent the product shell rather than the Bear integration domain.
- Repo identity search gates now catch accidental reintroduction of old product wording outside the dedicated gate test.
- Prerelease support-root and debug-log migration logic has been removed instead of carried forward.

## Current Working Surface

### App

- The primary app surface now uses `Setup`, `Preferences`, and `Tools` tabs instead of the old dashboard-style `Overview` / `Hosts` / `Configuration` / `Token` split.
- `Setup` is the default landing screen and keeps the main path compact: a clean Ursus header plus divider-led sections for defaults, Bear token, detected local host app setup, and the optional localhost bridge.
- `Setup` status treatment is now calmer and action-led, using compact state badges plus a single inline bridge repair path instead of diagnostic-heavy status walls.
- `Preferences` keeps durable note/template defaults compact, including inline template editing with validation and a refined chip-style inbox-tags editor.
- `Preferences` and `Tools` now each open with one quiet auto-save/restart note instead of repeating restart warnings inside individual controls.
- `Tools` now owns launcher repair, reveal-file/log actions, and tool availability controls in a quieter presentation so those details stay out of the beginner path.
- The optional `Remote MCP Bridge` remains visible and actionable from `Setup`, with install, remove, pause, resume/restart, copy-URL actions, and a saved port control that is only editable before bridge install.
- The `Remote MCP Bridge` now also carries one bridge-scoped auth toggle: open by default, or `Require OAuth for all bridge requests` for the entire `/mcp` surface. This applies only to the optional HTTP bridge; stdio remains untouched.
- The Setup bridge card now derives a `Restart Required` state from persisted runtime config drift, selected-note token availability drift, and MCP bridge-surface drift versus the markers last loaded by the serving bridge process, without adding transient restart toasts or extra inline warnings elsewhere.
- The macOS Settings window now mirrors the `Preferences` surface instead of exposing a separate configuration-only hierarchy.

### CLI

Current direct utility commands:

- `ursus --new-note [--title TEXT] [--content TEXT] [--tags TAGS] [--replace-tags] [--open-note] [--new-window]`
- `ursus --backup-note [note-id-or-title ...]`
- `ursus --restore-note [NOTE_ID SNAPSHOT_ID ...]`
- `ursus --apply-template [note-id-or-title ...]`
- `ursus bridge serve`
- `ursus bridge status`
- `ursus bridge print-url`

Behavior already in place:

- `--new-note` creates a templated editing note.
- Default title format is `yyMMdd - hh:mm a`.
- Bare `--new-note` still opens an editing note in the foreground and seeds tags from the selected note when a Bear token is configured.
- Bare `--new-note` now skips selected-note lookup entirely when no Bear token is configured and falls back to configured inbox tags only when `Create adds inbox tags by default` is enabled.
- Explicit `--new-note` mode always skips selected-note lookup, makes omitted `--tags` follow the `Create adds inbox tags by default` setting, defaults to append semantics unless `--replace-tags` is passed, and leaves the note closed/background unless `--open-note` is passed.
- In explicit `--new-note` mode, `--new-window` is a presence flag and is only valid together with `--open-note`.
- CLI-created empty notes now preserve one empty editable body line inside the templated `{{content}}` slot so the caret lands in the body without breaking template structure.
- Short aliases now exist for explicit `--new-note` subflags: `-t`, `-c`, `-g`, `-rt`, `-on`, and `-nw`.
- `--backup-note` captures one durable backup snapshot per selected or explicitly targeted note and prints machine-friendly receipt lines that include both `note_id` and `snapshot_id`.
- Bare `--restore-note` restores the selected Bear note from its most recent backup snapshot and reports a compact receipt.
- Passed `--restore-note` arguments restore one or more explicit `NOTE_ID SNAPSHOT_ID` pairs, require exact note ids rather than title selectors, and report per-pair receipts.
- `--apply-template`, `--backup-note`, and bare `--restore-note` target the selected Bear note when called without arguments.
- Passed note arguments resolve as exact note id first, then exact case-insensitive title.
- `bridge serve` now provides the first optional loopback HTTP MCP runtime path, reusing the same internal Bear service stack as `ursus mcp`.
- Bridge config now lives inside `~/Library/Application Support/Ursus/config.json` with default localhost settings and a stable saved port.
- Bridge LaunchAgent management is now implemented natively in `BearApplication` and targets the stable public launcher path.
- The bridge runtime now uses the SDK's stateless HTTP transport, so `initialize` and `tools/list` succeed as plain request/response calls without per-client session headers.
- The stateless bridge now uses an Ursus-owned validation pipeline instead of the SDK's localhost-only default host/origin guard, which keeps the bridge loopback-bound while allowing personal tunnel forwarding to reach the same `/mcp` endpoint.
- The bridge now also wraps successful POST request responses as one-shot SSE events when a client advertises `Accept: ... text/event-stream`, which keeps simple JSON clients working while improving compatibility with remote MCP clients that expect streamable HTTP response formatting.
- Repeated `initialize` requests against the running stateless bridge are now treated as compatibility handshakes, so hosts can remove and re-add the same MCP URL without reinstalling the bridge.
- Bridge install/resume now wait for the localhost endpoint to pass an MCP `initialize` probe before reporting success, and dashboard status distinguishes `loaded` from healthy endpoint state.
- Bridge diagnostics now go beyond TCP reachability: the app and CLI surface LaunchAgent state, protocol-health results, and recent stdout/stderr log hints for unhealthy bridges.
- `bridge status` now prints saved config, LaunchAgent state, health-check detail, and relevant runtime paths.
- App-side bridge configuration keeps the host non-editable and localhost-oriented, while the port control auto-skips busy ports and install/resume reject ports already in use.
- Runtime log retention is now capped per log family: `debug.log`, `bridge.stdout.log`, and `bridge.stderr.log` each keep at most the active file plus one `.1` archive, and bridge removal clears both live and archived bridge log files.

### MCP

The main MCP surface is already broad and usable. Implemented tools include:

- discovery: `bear_find_notes`, `bear_find_notes_by_tag`, `bear_find_notes_by_inbox_tags`, `bear_get_notes`, `bear_list_tags`
- backups: `bear_create_backups`, `bear_list_backups`, `bear_compare_backup`, `bear_delete_backups`, `bear_restore_notes`
- tag/navigation: `bear_open_tag`, `bear_open_notes`, `bear_rename_tags`, `bear_delete_tags`, `bear_add_tags`, `bear_remove_tags`
- note mutation: `bear_apply_template`, `bear_create_notes`, `bear_insert_text`, `bear_replace_content`, `bear_add_files`, `bear_archive_notes`

## Current Runtime Paths

These paths describe the codebase as it exists after Phase 6:

- config file: `~/Library/Application Support/Ursus/config.json`
- template: `~/Library/Application Support/Ursus/template.md`
- public launcher: `~/.local/bin/ursus`
- app support root: `~/Library/Application Support/Ursus`
- bridge LaunchAgent plist path: `~/Library/LaunchAgents/com.aft.ursus.plist`
- backups: `~/Library/Application Support/Ursus/Backups`
- backup metadata DB: `~/Library/Application Support/Ursus/backups.sqlite`
- backup quarantine: `~/Library/Application Support/Ursus/Backups/_quarantine`
- runtime lock: `~/Library/Application Support/Ursus/Runtime/.server.lock`
- current app bundle state: `~/Library/Application Support/Ursus/Runtime/current-app-bundle.json`
- bridge runtime state: `~/Library/Application Support/Ursus/Runtime/bridge-runtime-state.json`
- temp fallback locks: `TMPDIR/ursus/Runtime/...`
- debug log: `~/Library/Application Support/Ursus/Logs/debug.log`
- bridge stdout log: `~/Library/Application Support/Ursus/Logs/bridge.stdout.log`
- bridge stderr log: `~/Library/Application Support/Ursus/Logs/bridge.stderr.log`

## Current Technical Truths

- Phases 1 through 6 are complete: shipped identities are cut over, runtime storage is unified under `~/Library/Application Support/Ursus`, launcher/locator wiring points at `ursus` and `Ursus.app`, repo-internal app containers and product-facing internal types now use Ursus-branded names, and the status/build/helper docs now match that product truth.
- Config and template editing are JSON / file based under `~/Library/Application Support/Ursus`.
- The selected-note token is now managed in macOS Keychain through shared Ursus-owned code rather than `config.json`.
- CLI and bridge behavior now live in a shared `BearCLIRuntime` target used by both the standalone `ursus` executable and `Ursus.app`'s hidden CLI mode, so launchd only has to execute the already-provisioned app binary inside the bundle.
- The selected-note helper is signed without restricted entitlements because it does not read the shared token directly.
- Opened notes now always request Bear edit mode; that default is no longer user-configurable in config.
- Discovery tools return compact note summaries with attachment presence metadata, attachment-match evidence, and optional backup-presence hints when backup tooling is active; `bear_get_notes` remains the full-note fetch, and attachment OCR/search text is opt-in there.
- Discovery page size and snippet length now come only from config defaults. MCP discovery inputs do not accept per-call `limit` or `snippet_length` overrides anymore, and cursor continuation keeps using the configured defaults.
- Backup MCP discovery is now note-scoped and paginated with opaque cursors. `bear_create_backups` reuses the manual capture path, `bear_list_backups` supports optional inclusive `from` / `to` filters on the backup creation timestamp, `bear_compare_backup` returns compact metadata plus bounded diff hunks, and backup list results no longer include stored snippets or Bear revision numbers.
- Backup snapshot payloads now live in canonical per-note folders under `Backups/<note-id>/<snapshot-id>.json`, while backup metadata now lives in the root-level `backups.sqlite` index instead of a flat `index.json`. The store keeps a lightweight backup-tree fingerprint in SQLite so normal access can skip the expensive recursive reconciliation pass, then rebuilds the metadata index from disk only when the tree changes. Malformed or ambiguous files are quarantined under `Backups/_quarantine`, expired snapshots are removed during reconciliation, and empty backup folders are cleaned up after moves and deletions. Backup identity and recency are driven by `snapshot_id` plus `captured_at`, not Bear's mutable note revision counter, and backup-list cursors are keyed to the normalized note-scoped date-filter query so filtered pages cannot be mixed.
- Mutation receipts should stay compact unless the user explicitly asks for content.
- `bear_replace_content` computes the final full note body locally, then commits through Bear's full replacement path.
- MCP presentation controls are now intentionally narrow: `bear_create_notes` keeps config-driven `open_note` and `new_window`, `bear_open_notes` keeps `new_window`, and the other note/tag mutation tools run as background mutations without exposed presentation overrides.
- Batch operations matter and should stay first-class.
- Batched MCP tools now require `operations` to be a non-empty array of operation objects, and missing versus empty `operations` batches are surfaced as distinct validation errors.
- No prerelease support-root or legacy-log migration path is preserved in startup anymore.
- Bridge LaunchAgent unload now checks actual loaded state first so a stale plist does not abort install/remove with `launchctl bootout` I/O errors.
- Bridge port edits now save through the app config flow and take effect on the next bridge install or resume. Host overrides remain config-only for advanced users.
- The bridge HTTP handler now preserves request paths and routes `/mcp` separately from future OAuth bridge paths, so OAuth well-known and authorization endpoints can be added without another transport-layer refactor.
- Runtime-affecting config now carries a persisted monotonic `runtimeConfigurationGeneration`, and the serving bridge records the config generation/fingerprint, selected-note token availability, and a canonical MCP bridge-surface marker in a small runtime state file so the app can flag stale-yet-serving bridge processes after config edits, token availability changes, or MCP-surface updates without guessing about client restarts.
- The app now records the most recently opened `Ursus.app` bundle path in runtime state, so launcher validation, CLI diagnostics, and selected-note helper lookup can continue to find a nonstandard install location after the app has been opened once.
- Bridge log maintenance now runs on install/resume and while the bridge is serving, snapshots oversized stdout/stderr logs into a single `.1` archive before truncating the live file in place, and bridge removal deletes the whole bridge-log family.
- Host setup snapshots now include a lightweight presentation flag so the app can hide irrelevant local integrations from the main setup flow while still keeping generic/remote guidance available in underlying support logic and diagnostics.
- Queue labels, logger labels, DB labels, and selected-note callback paths no longer use the old launcher identity.
- A repo identity gate test now keeps old product strings isolated to the dedicated guard test.

## Documentation Cleanup Decisions

This repo had started to accumulate too much historical planning text. The working documentation set should now be:

- `PROJECT_STATUS.md`: current truth and next queue
- `docs/ARCHITECTURE.md`: current runtime and behavior shape
- `docs/APP_UNIFICATION_PLAN.md`: short live roadmap
- `docs/LOCAL_BUILD_AND_CLEAN_INSTALL.md`: practical local build / reset guide
- `docs/SELECTED_NOTE_HELPER.md`: short note about the embedded helper used for selected-note resolution

Helper-only release/testing duplication should not come back unless the embedded helper packaging itself needs dedicated work again.

The repo now also keeps one small automated identity gate in tests so current-truth docs and user-facing copy do not drift back toward prerelease names.

The old implementation handoff document `docs/URSUS_IMPLEMENTATION_PLAN.md` has been removed now that the Phase 6 cleanup pass is complete.

## Next Implementation Queue

Current near-term priorities:

1. Build Phase 2 of the HTTP bridge OAuth work: durable auth state/storage plus compact app snapshots for pending requests and grants.
2. Implement the built-in bridge-local authorization server endpoints on top of the new multi-route bridge boundary.

## Verification Baseline

Phase 1 verification that already passed:

- `swift test`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- built outputs verified at `.build/UrsusApp/Build/Products/Debug/Ursus.app`
- bundled artifacts verified: `Contents/MacOS/Ursus` and `Contents/Library/Helpers/Ursus Helper.app`
- HTTP MCP `initialize` probe returned `serverInfo.name = "ursus"`

Phase 2 verification that passed on 2026-03-30:

- `swift test`
- `swift run ursus paths`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- `swift run ursus paths` printed only Ursus-era storage roots plus the intentionally deferred pre-Phase-3 launcher-path survivor
- built outputs verified at `.build/UrsusApp/Build/Products/Debug/Ursus.app`
- bundled artifacts re-verified: `Contents/MacOS/Ursus` and `Contents/Library/Helpers/Ursus Helper.app`

Phase 3 verification that passed on 2026-03-30:

- `swift test`
- `swift run ursus paths`
- `swift run ursus --help`
- `swift run ursus doctor`
- `swift run ursus bridge status`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- `swift run ursus paths` printed only Ursus-era storage roots, including the renamed public launcher path `~/.local/bin/ursus`
- `swift run ursus --help` printed `ursus` command examples throughout
- `swift run ursus doctor` and `swift run ursus bridge status` reported `~/.local/bin/ursus` plus Ursus-era launcher/bridge diagnostics
- built outputs re-verified at `.build/UrsusApp/Build/Products/Debug/Ursus.app`
- bundled artifacts re-verified: `Contents/MacOS/Ursus` and `Contents/Library/Helpers/Ursus Helper.app`

Phase 4 verification that passed on 2026-03-30:

- `swift test`
- `swift run ursus doctor`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- host setup guidance tests now verify `ursus` snippets for Codex and Claude Desktop
- `swift run ursus doctor` now reports `host-codex` / `host-claude-desktop` guidance in terms of `ursus` host entries
- built app re-verified at `.build/UrsusApp/Build/Products/Debug/Ursus.app`

Phase 5 verification that passed on 2026-03-30:

- `swift test`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- current-truth docs were updated to remove stale prerelease wording from current workflows
- repo identity gate coverage now keeps old product strings isolated to the dedicated guard test

Phase 6 verification that passed on 2026-03-31:

- `swift test`

Phase 7 verification that passed on 2026-04-03:

- `swift build`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- the app built successfully with the new `Setup` / `Preferences` / `Tools` surface
- detected-host filtering kept ChatGPT and the generic stdio example out of the primary app path while preserving bridge and advanced repair controls
- `swift run ursus doctor`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- repo-internal app containers and product-facing internal type/file names were renamed to Ursus-branded names where they represented the product rather than the Bear integration domain
- built app re-verified at `.build/UrsusApp/Build/Products/Debug/Ursus.app`
- bundled artifacts re-verified: `Contents/MacOS/Ursus` and `Contents/Library/Helpers/Ursus Helper.app`

Bridge-launch packaging verification that passed on 2026-04-02:

- `swift test`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- `./.build/debug/ursus --help`
- `./.build/UrsusApp/Build/Products/Debug/Ursus.app/Contents/MacOS/Ursus --ursus-cli --help`
- verified the app executable now owns the in-bundle launch path used by the public launcher and bridge runtime
- verified the build no longer produces `Contents/Resources/bin/ursus`
- verified the selected-note helper still bundles at `Contents/Library/Helpers/Ursus Helper.app`

Add command-specific verification as appropriate for whichever slice is being worked on.
