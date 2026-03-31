# PROJECT_STATUS.md

This file is the concise handoff for future threads. It should describe the current product truth, not preserve every historical phase in detail.

## Project Identity

- Swift package executable / CLI name: `ursus`
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

Phases 1 and 2 of the Ursus identity reset are complete:

- `Ursus.app` is now the product shell and control center.
- The bundled local stdio/runtime executable is now `ursus`.
- The embedded selected-note helper is now `Ursus Helper.app` / `ursus-helper`.
- MCP `initialize` now reports server name `ursus`.
- The bridge LaunchAgent label is now `com.aft.ursus`.
- Config, template, logs, backups, and runtime locks now live under `~/Library/Application Support/Ursus`.
- Temp fallback runtime locks now live under `TMPDIR/ursus/Runtime/...`.
- Prerelease support-root and debug-log migration logic has been removed instead of carried forward.

Intentional carry-over until later phases:

- the public launcher path is still `~/.local/bin/bear-mcp` until Phase 3
- broader app/UI wording, host snippets, and old Bear MCP documentation cleanup are still pending

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

- `ursus --new-note [--title TEXT] [--content TEXT] [--tags TAGS] [--tag-merge-mode append|replace] [--open-note yes|no] [--new-window yes|no]`
- `ursus --apply-template [note-id-or-title ...]`
- `ursus --archive-note [note-id-or-title ...]`
- `ursus --delete-note [note-id-or-title ...]`
- `ursus bridge serve`
- `ursus bridge status`
- `ursus bridge print-url`

Behavior already in place:

- `--new-note` creates a templated editing note.
- Default title format is `yyMMdd - hh:mm a`.
- Default create behavior uses `open_note=yes`, `new_window=no`, and `edit=yes`.
- If a selected note is available, `--new-note` copies that note's tags.
- If selected-note tags are unavailable, it falls back to configured inbox tags.
- `--new-note` with any explicit override flags skips selected-note lookup entirely.
- In explicit `--new-note` mode, omitted `--tags` defaults to configured inbox tags.
- In explicit `--new-note` mode, `--tag-merge-mode` defaults to `append` regardless of the general create-note config, and `replace` is available as an explicit override.
- In explicit `--new-note` mode, `--title` defaults to the same timestamp format, `--content` defaults to empty content, `--open-note` defaults to `createOpensNoteByDefault`, `--new-window` defaults to `openUsesNewWindowByDefault`, and edit mode follows `openNoteInEditModeByDefault` when the created note opens.
- `--apply-template`, `--archive-note`, and `--delete-note` target the selected Bear note when called without arguments.
- Passed note arguments resolve as exact note id first, then exact case-insensitive title.
- `bridge serve` now provides the first optional localhost HTTP MCP runtime path, reusing the same internal Bear service stack as `ursus mcp`.
- Bridge config now lives inside `~/Library/Application Support/Ursus/config.json` with default localhost settings and a stable saved port.
- Bridge LaunchAgent management is now implemented natively in `BearApplication` and still targets the stable public launcher path.
- The bridge runtime now uses the SDK's stateless HTTP transport, so `initialize` and `tools/list` succeed as plain request/response calls without per-client session headers.
- Repeated `initialize` requests against the running stateless bridge are now treated as compatibility handshakes, so hosts can remove and re-add the same MCP URL without reinstalling the bridge.
- Bridge install/resume now wait for the localhost endpoint to pass an MCP `initialize` probe before reporting success, and dashboard status distinguishes `loaded` from healthy endpoint state.
- Bridge diagnostics now go beyond TCP reachability: the app and CLI surface LaunchAgent state, protocol-health results, and recent stdout/stderr log hints for unhealthy bridges.
- `bridge status` now prints saved config, LaunchAgent state, health-check detail, and relevant runtime paths.
- App-side bridge configuration keeps the host non-editable and localhost-oriented, while the port control auto-skips busy ports and install/resume reject ports already in use.

### MCP

The main MCP surface is already broad and usable. Implemented tools include:

- discovery: `bear_find_notes`, `bear_find_notes_by_tag`, `bear_find_notes_by_inbox_tags`, `bear_get_notes`, `bear_list_tags`
- backups: `bear_list_backups`, `bear_delete_backups`, `bear_restore_notes`
- tag/navigation: `bear_open_tag`, `bear_open_notes`, `bear_rename_tags`, `bear_delete_tags`, `bear_add_tags`, `bear_remove_tags`
- note mutation: `bear_apply_template`, `bear_create_notes`, `bear_insert_text`, `bear_replace_content`, `bear_add_files`, `bear_archive_notes`

## Current Runtime Paths

These paths describe the codebase as it exists after Phase 2:

- config file: `~/Library/Application Support/Ursus/config.json`
- template: `~/Library/Application Support/Ursus/template.md`
- public launcher: `~/.local/bin/bear-mcp`
- app support root: `~/Library/Application Support/Ursus`
- bridge LaunchAgent plist path: `~/Library/LaunchAgents/com.aft.ursus.plist`
- backups: `~/Library/Application Support/Ursus/Backups`
- runtime lock: `~/Library/Application Support/Ursus/Runtime/.server.lock`
- temp fallback locks: `TMPDIR/ursus/Runtime/...`
- debug log: `~/Library/Application Support/Ursus/Logs/debug.log`
- bridge stdout log: `~/Library/Application Support/Ursus/Logs/bridge.stdout.log`
- bridge stderr log: `~/Library/Application Support/Ursus/Logs/bridge.stderr.log`

## Current Technical Truths

- Phases 1 and 2 are complete: shipped identities are cut over and runtime storage is unified under `~/Library/Application Support/Ursus`.
- Config and template editing are JSON / file based under `~/Library/Application Support/Ursus`.
- The selected-note token is currently managed in Bear MCP's config flow, not in Keychain.
- Discovery tools return compact note summaries; `bear_get_notes` remains the full-note fetch.
- Mutation receipts should stay compact unless the user explicitly asks for content.
- `bear_replace_content` computes the final full note body locally, then commits through Bear's full replacement path.
- Batch operations matter and should stay first-class.
- No prerelease support-root or legacy-log migration path is preserved in startup anymore.
- Bridge LaunchAgent unload now checks actual loaded state first so a stale plist does not abort install/remove with `launchctl bootout` I/O errors.
- Bridge port edits now save through the app config flow and take effect on the next bridge install or resume. Host overrides remain config-only for advanced users.

## Documentation Cleanup Decisions

This repo had started to accumulate too much historical planning text. The working documentation set should now be:

- `PROJECT_STATUS.md`: current truth and next queue
- `docs/ARCHITECTURE.md`: current runtime and behavior shape
- `docs/APP_UNIFICATION_PLAN.md`: short live roadmap
- `docs/LOCAL_BUILD_AND_CLEAN_INSTALL.md`: practical local build / reset guide
- `docs/SELECTED_NOTE_HELPER.md`: short note about the embedded helper used for selected-note resolution

Helper-only release/testing duplication should not come back unless the embedded helper packaging itself needs dedicated work again.

## Next Implementation Queue

This is the intended order after Phase 2:

1. Phase 3: rename the public launcher path to `~/.local/bin/ursus` and finish the app/helper/bridge locator wiring around the new product identity.
2. Phase 4: update host snippets, app copy, CLI wording, and diagnostics to present Ursus consistently.
3. Phase 5: finish docs/status cleanup and run the identity search gates.

## Verification Baseline

Phase 1 verification that already passed:

- `swift test`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- built outputs verified at `.build/BearMCPApp/Build/Products/Debug/Ursus.app`
- bundled artifacts verified: `Contents/Resources/bin/ursus` and `Contents/Library/Helpers/Ursus Helper.app`
- HTTP MCP `initialize` probe returned `serverInfo.name = "ursus"`

Phase 2 verification that passed on 2026-03-30:

- `swift test`
- `swift run ursus paths`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
- `swift run ursus paths` printed only Ursus-era storage roots plus the intentional Phase 3 survivor `~/.local/bin/bear-mcp`
- built outputs verified at `.build/BearMCPApp/Build/Products/Debug/Ursus.app`
- bundled artifacts re-verified: `Contents/Resources/bin/ursus` and `Contents/Library/Helpers/Ursus Helper.app`

Add command-specific verification as appropriate for whichever slice is being worked on.
