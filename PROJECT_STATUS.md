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
- Keep the current layered structure: `BearCore`, `BearDB`, `BearXCallback`, `BearApplication`, `BearMCP`, `BearMCPCLI`.
- Keep template storage as one real file at `~/Library/Application Support/Ursus/template.md`.
- Trash stays CLI-only for now unless the user explicitly asks to expose it through MCP.

## Current Product Shape

Phases 1 through 6 of the Ursus identity reset are complete:

- `Ursus.app` is now the product shell and control center.
- The bundled local stdio/runtime executable is now `ursus`.
- The embedded selected-note helper is now `Ursus Helper.app` / `ursus-helper`.
- MCP `initialize` now reports server name `ursus`.
- The bridge LaunchAgent label is now `com.aft.ursus`.
- Config, template, logs, backups, and runtime locks now live under `~/Library/Application Support/Ursus`.
- Temp fallback runtime locks now live under `TMPDIR/ursus/Runtime/...`.
- The public launcher path is now `~/.local/bin/ursus`.
- Launcher repair/install, bridge diagnostics, and CLI help/doctor/status output now point at the `ursus` launcher and `Ursus.app`.
- Selected-note helper lookup now prefers the embedded helper in `/Applications/Ursus.app` but still falls back to `~/Applications/Ursus.app` when needed.
- Host setup snippets and diagnostics now recommend `ursus` as the host-side server identity for Codex and Claude Desktop.
- Broader app copy now presents the product as Ursus while keeping Bear wording only for Bear-specific domains like the Bear database, Bear notes, and Bear tokens.
- Current docs, local build/reset guidance, and helper docs are aligned to the shipped Ursus identity.
- Repo-internal app/container paths and product-facing internal type names now use Ursus branding where they represent the product shell rather than the Bear integration domain.
- Repo identity search gates now catch accidental reintroduction of old product wording outside the dedicated gate test.
- Prerelease support-root and debug-log migration logic has been removed instead of carried forward.

## Current Working Surface

### App

- Overview, Hosts, Configuration, and Token tabs exist.
- Configuration edits auto-save with validation.
- Configuration now also includes inline template editing for `~/Library/Application Support/Ursus/template.md`, with open/reveal actions and pre-save slot validation.
- The app can install or repair the public launcher.
- The app now also exposes the optional `Remote MCP Bridge` with install, remove, pause, resume, status, copy-URL actions, and an editable saved port control before install.
- The app still exposes a lot of implementation detail and is ready for simplification.

### CLI

Current direct utility commands:

- `ursus --new-note [--title TEXT] [--content TEXT] [--tags TAGS] [--replace-tags] [--open-note] [--new-window]`
- `ursus --backup-note [note-id-or-title ...]`
- `ursus --restore-note NOTE_ID SNAPSHOT_ID [NOTE_ID SNAPSHOT_ID ...]`
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
- `--restore-note` restores one or more explicit `NOTE_ID SNAPSHOT_ID` pairs, requires exact note ids rather than title selectors, and reports per-pair receipts.
- `--apply-template` and `--backup-note` target the selected Bear note when called without arguments.
- Passed note arguments resolve as exact note id first, then exact case-insensitive title.
- `bridge serve` now provides the first optional localhost HTTP MCP runtime path, reusing the same internal Bear service stack as `ursus mcp`.
- Bridge config now lives inside `~/Library/Application Support/Ursus/config.json` with default localhost settings and a stable saved port.
- Bridge LaunchAgent management is now implemented natively in `BearApplication` and targets the stable public launcher path.
- The bridge runtime now uses the SDK's stateless HTTP transport, so `initialize` and `tools/list` succeed as plain request/response calls without per-client session headers.
- Repeated `initialize` requests against the running stateless bridge are now treated as compatibility handshakes, so hosts can remove and re-add the same MCP URL without reinstalling the bridge.
- Bridge install/resume now wait for the localhost endpoint to pass an MCP `initialize` probe before reporting success, and dashboard status distinguishes `loaded` from healthy endpoint state.
- Bridge diagnostics now go beyond TCP reachability: the app and CLI surface LaunchAgent state, protocol-health results, and recent stdout/stderr log hints for unhealthy bridges.
- `bridge status` now prints saved config, LaunchAgent state, health-check detail, and relevant runtime paths.
- App-side bridge configuration keeps the host non-editable and localhost-oriented, while the port control auto-skips busy ports and install/resume reject ports already in use.

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
- backup metadata DB: `~/Library/Application Support/Ursus/Backups/backups.sqlite`
- runtime lock: `~/Library/Application Support/Ursus/Runtime/.server.lock`
- temp fallback locks: `TMPDIR/ursus/Runtime/...`
- debug log: `~/Library/Application Support/Ursus/Logs/debug.log`
- bridge stdout log: `~/Library/Application Support/Ursus/Logs/bridge.stdout.log`
- bridge stderr log: `~/Library/Application Support/Ursus/Logs/bridge.stderr.log`

## Current Technical Truths

- Phases 1 through 6 are complete: shipped identities are cut over, runtime storage is unified under `~/Library/Application Support/Ursus`, launcher/locator wiring points at `ursus` and `Ursus.app`, repo-internal app containers and product-facing internal types now use Ursus-branded names, and the status/build/helper docs now match that product truth.
- Config and template editing are JSON / file based under `~/Library/Application Support/Ursus`.
- The selected-note token is currently managed in Ursus's config flow, not in Keychain.
- Opened notes now always request Bear edit mode; that default is no longer user-configurable in config.
- Discovery tools return compact note summaries with attachment presence metadata and attachment-match evidence only; `bear_get_notes` remains the full-note fetch, and attachment OCR/search text is opt-in there.
- Discovery page size and snippet length now come only from config defaults. MCP discovery inputs do not accept per-call `limit` or `snippet_length` overrides anymore, and cursor continuation keeps using the configured defaults.
- Backup MCP discovery is now note-scoped and paginated with opaque cursors. `bear_create_backups` reuses the manual capture path, `bear_compare_backup` returns compact metadata plus bounded diff hunks, and backup list results no longer include stored snippets.
- Backup snapshot payloads remain one JSON file per snapshot, while backup metadata now lives in `Backups/backups.sqlite` instead of a flat `index.json`, so list/lookup/delete/prune operations no longer load whole-history metadata into memory.
- Mutation receipts should stay compact unless the user explicitly asks for content.
- `bear_replace_content` computes the final full note body locally, then commits through Bear's full replacement path.
- Batch operations matter and should stay first-class.
- No prerelease support-root or legacy-log migration path is preserved in startup anymore.
- Bridge LaunchAgent unload now checks actual loaded state first so a stale plist does not abort install/remove with `launchctl bootout` I/O errors.
- Bridge port edits now save through the app config flow and take effect on the next bridge install or resume. Host overrides remain config-only for advanced users.
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

1. Simplify the app UI so the control-center path shows less implementation detail.
2. Keep the optional localhost HTTP bridge stable while the app surface is simplified.

## Verification Baseline

Phase 1 verification that already passed:

- `swift test`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- built outputs verified at `.build/UrsusApp/Build/Products/Debug/Ursus.app`
- bundled artifacts verified: `Contents/Resources/bin/ursus` and `Contents/Library/Helpers/Ursus Helper.app`
- HTTP MCP `initialize` probe returned `serverInfo.name = "ursus"`

Phase 2 verification that passed on 2026-03-30:

- `swift test`
- `swift run ursus paths`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- `swift run ursus paths` printed only Ursus-era storage roots plus the intentionally deferred pre-Phase-3 launcher-path survivor
- built outputs verified at `.build/UrsusApp/Build/Products/Debug/Ursus.app`
- bundled artifacts re-verified: `Contents/Resources/bin/ursus` and `Contents/Library/Helpers/Ursus Helper.app`

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
- bundled artifacts re-verified: `Contents/Resources/bin/ursus` and `Contents/Library/Helpers/Ursus Helper.app`

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
- `swift run ursus doctor`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- repo-internal app containers and product-facing internal type/file names were renamed to Ursus-branded names where they represented the product rather than the Bear integration domain
- built app re-verified at `.build/UrsusApp/Build/Products/Debug/Ursus.app`
- bundled artifacts re-verified: `Contents/Resources/bin/ursus` and `Contents/Library/Helpers/Ursus Helper.app`

Add command-specific verification as appropriate for whichever slice is being worked on.
