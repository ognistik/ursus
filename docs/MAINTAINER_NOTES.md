# Maintainer Notes

This file is the concise handoff for contributors and future agent threads. It should describe the current product truth, not preserve old implementation phases.

## Project Identity

- Swift package name: `ursus`
- CLI / stdio MCP executable: `ursus`
- Selected-note helper executable: `ursus-helper`
- MCP server name exposed to clients: `ursus`
- Product shell: `Ursus.app`
- App bundle identifier: `com.aft.ursus`
- Helper bundle identifier: `com.aft.ursus-helper`
- Platform: local macOS 14 or later
- Release architecture: universal macOS app bundles with `arm64` and `x86_64` slices

## Product Invariants

- Ursus is a Bear-specific local MCP server and macOS app.
- Reads come from Bear's local SQLite database through the read adapter.
- Writes go through Bear's x-callback-url scheme. Do not write directly to Bear's SQLite database.
- Do not rebuild the old AppleScript / Shortcuts bridge into this runtime.
- Keep the MCP surface explicit and batch-friendly. Do not collapse it into one giant `bear_action` tool.
- Preserve the layered structure: `BearCore`, `BearDB`, `BearXCallback`, `BearApplication`, `BearMCP`, `BearCLIRuntime`, `BearMCPCLI`.
- Keep template storage as one real file at `~/Library/Application Support/Ursus/template.md`.
- Mutation tools should return compact receipts unless the user explicitly asks for content.
- `bear_replace_content` computes the final full note markdown locally, then commits through Bear's full replacement path.
- Discovery tools should return compact note summaries; `bear_get_notes` remains the full-note fetch.
- Batch operations are first-class. Batched MCP tools require a non-empty `operations` array and distinguish missing batches from empty batches.
- Bear's own trash/restore flows are not part of the MCP surface. Backup restore is exposed separately through `bear_restore_notes`.

## Current Product Surface

### App

- `Ursus.app` is the control center and product shell.
- The app uses one main dashboard window with `Setup`, `Preferences`, and `Tools` tabs.
- `Setup` handles the main path: defaults, Bear selected-note token, detected local host setup, and optional localhost bridge setup.
- Connect Apps lists only detected local hosts and keeps each row compact: app name, passive `Installed` indicator when healthy, one primary `Install` or `Repair` action when needed, and one trailing overflow menu for advanced actions.
- Supported local host rows are currently `Codex`, `Claude Desktop`, and `Claude CLI`. Remove actions are app-specific and delete only Ursus's host config entry, not the shared launcher or the app itself.
- `Preferences` owns durable note/template defaults, inline `template.md` editing with validation, inbox-tag editing, and Sparkle update controls.
- `Tools` owns launcher repair, reveal-file/log actions, and tool availability controls.
- Ursus does not expose a separate macOS Settings window or multi-window dashboard flow; `Cmd+,` and `File > New Window` stay disabled because those surfaces already live inside the main window tabs.
- Donation prompting is app-only. MCP runtime code only records local eligibility in `Runtime/runtime-state.sqlite`.
- Sparkle update UI remains in the app executable, and embedded CLI runs can participate in scheduled Sparkle checks for stdio MCP / bridge usage without opening the dashboard.
- Embedded bridge / stdio Sparkle scheduling must avoid `SPUStandardUpdaterController`; hidden CLI runs use a background `SPUUpdater` user driver so the bridge does not claim the visible app's LaunchServices identity. If that background check finds an update, it hands off to the same app executable in Sparkle-only foreground mode.
- Background bridge / stdio Sparkle checks are silent when no update is found or when a check fails. Only a real update-found event should foreground Sparkle UI.
- User-initiated checks (`ursus --check-updates` and the app's own "Check for Updates…") may show Sparkle's standard "up to date" UI. Do not carry that no-update UI behavior into background bridge / MCP checks.
- Sparkle-only mode exists specifically to avoid the old failure mode where the wrong process owned the modal update window and left Ursus stuck, unclickable, or impossible to reopen. Do not move update UI ownership back into the hidden bridge / CLI process, and do not add another helper app for update presentation.
- Clearing `SULastCheckTime` and restarting bridge / stdio is the intended local test reset for scheduled checks. Long-running bridge / stdio processes should keep Sparkle's 3-hour scheduling alive without requiring the dashboard app to stay open.

### CLI

Current direct utility commands:

- `ursus --new-note [--title TEXT] [--content TEXT] [--tags TAGS] [--replace-tags] [--open-note] [--new-window]`
- `ursus --backup-note [note-id-or-title ...]`
- `ursus --restore-note [NOTE_ID SNAPSHOT_ID ...]`
- `ursus --apply-template [note-id-or-title ...]`
- `ursus --check-updates`
- `ursus --auto-install-updates true|false`
- `ursus bridge serve`
- `ursus bridge status`
- `ursus bridge print-url`
- `ursus doctor`
- `ursus paths`

Important behavior:

- Running `ursus` with no command starts the stdio MCP server.
- The public launcher at `~/.local/bin/ursus` forwards into `Ursus.app/Contents/MacOS/Ursus` with a hidden `--ursus-cli` flag.
- Opening `Ursus.app` reconciles that public launcher automatically before the user works through Setup, so host install/repair flows can target the shared launcher path consistently.
- Embedded CLI runs launched through the app bundle supply a Sparkle update checker. `ursus mcp` and `ursus bridge serve` start Sparkle's scheduled check cycle so Sparkle can check on its configured 3-hour cadence. Ordinary short-lived CLI commands do not trigger scheduled Sparkle checks. `ursus --check-updates` and MCP / bridge update-found events hand off to the foreground app executable in Sparkle-only mode so the user-facing Sparkle UI owns a normal AppKit run loop without opening the dashboard. `ursus --auto-install-updates true|false` updates Sparkle's persisted automatic-download/install preference from the command line; enabling it also turns on automatic update checks so it matches the user-facing Sparkle opt-in flow.
- Ordinary one-shot CLI commands such as note creation should not advance Sparkle's scheduler or touch `SULastCheckTime`; only the long-running MCP / bridge surfaces and explicit update-check commands should participate.
- CLI bridge recovery is available through `ursus bridge pause`, `ursus bridge resume`, and `ursus bridge remove`.
- Bare `--new-note` preserves the interactive editing-note flow and can seed tags from the selected Bear note when a selected-note token is configured.
- Explicit `--new-note` mode skips selected-note lookup, follows the create-adds-inbox-tags default when `--tags` is omitted, appends tags unless `--replace-tags` is passed, and leaves the note closed unless `--open-note` is passed.
- `--new-window` is only valid with `--open-note`.
- `--backup-note`, bare `--restore-note`, and `--apply-template` target the selected Bear note when no explicit targets are passed.
- Passed note arguments resolve as exact note id first, then exact case-insensitive title, except `--restore-note`, which requires exact `NOTE_ID SNAPSHOT_ID` pairs.

### MCP

Implemented MCP tools:

- discovery: `bear_find_notes`, `bear_find_notes_by_tag`, `bear_find_notes_by_inbox_tags`, `bear_get_notes`, `bear_list_tags`
- backups: `bear_create_backups`, `bear_list_backups`, `bear_compare_backup`, `bear_delete_backups`, `bear_restore_notes`
- tag/navigation: `bear_open_tag`, `bear_open_notes`, `bear_rename_tags`, `bear_delete_tags`, `bear_add_tags`, `bear_remove_tags`
- note mutation: `bear_apply_template`, `bear_create_notes`, `bear_insert_text`, `bear_replace_content`, `bear_add_files`, `bear_archive_notes`

MCP presentation controls are intentionally narrow: `bear_create_notes` keeps config-driven `open_note` and `new_window`, `bear_open_notes` keeps `new_window`, and other note/tag mutation tools run as background mutations without presentation overrides.

The server does not expose Bear resources, but it answers empty `resources/list` and `resources/templates/list` requests so clients that probe resources do not treat the server as broken.

### Optional HTTP Bridge

- The canonical runtime remains stdio MCP.
- The optional HTTP bridge runs through `ursus bridge serve`, binds to loopback, and exposes MCP at the configured endpoint path, defaulting to `/mcp`.
- Remote connector clients should use the full MCP endpoint URL, not the bare bridge origin.
- The bridge uses stateless HTTP transport and returns one-shot SSE-formatted POST responses when clients advertise `text/event-stream`.
- Bridge install/resume waits for MCP `initialize` and `tools/list` probes before reporting success.
- App-level Restart is intentionally lighter than Repair: it stop/starts the existing LaunchAgent when the plist still matches expectations, while Repair rewrites the LaunchAgent and reconciles bridge install artifacts.
- The app manages the bridge as a per-user LaunchAgent at `~/Library/LaunchAgents/com.aft.ursus.plist`.
- The bridge can be open or OAuth-protected. Protected mode is scoped to the optional HTTP bridge and does not affect stdio.
- Bridge OAuth state lives in `~/Library/Application Support/Ursus/Auth/bridge-auth.sqlite`.
- Protected bridges serve bridge-local OAuth discovery, dynamic client registration, authorization, decision, and token routes from the same loopback-bound process.
- The app surfaces bridge access review and remembered-grant revocation from `Setup`.
- Runtime drift detection compares persisted config generation, selected-note token availability, and the served MCP bridge-surface marker.

### Selected-Note Helper

- Selected-note targeting uses the helper app embedded inside `Ursus.app`, not a foreground app-host callback path.
- The helper bundle is `Ursus Helper.app`; the executable product is `ursus-helper`; the callback scheme is `ursushelper://`.
- The helper is background-only and on-demand. It launches for the selected-note callback round trip, writes the response-file JSON payload expected by the CLI runtime, then exits.
- Helper lookup prefers the most recently opened `Ursus.app` bundle path recorded in runtime state, then falls back to `/Applications/Ursus.app` and `~/Applications/Ursus.app`.
- The helper is signed without restricted entitlements because it does not read the selected-note token directly.
- Build the helper bundle directly only when working on helper packaging or callback behavior:

```sh
Support/scripts/build-ursus-helper-app.sh
CONFIGURATION=Release Support/scripts/build-ursus-helper-app.sh
```

The helper bundle version follows the app target's Xcode `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, so normal releases only need one version bump in the app project settings.

## Runtime Paths

- app support root: `~/Library/Application Support/Ursus`
- config file: `~/Library/Application Support/Ursus/config.json`
- template: `~/Library/Application Support/Ursus/template.md`
- backups: `~/Library/Application Support/Ursus/Backups`
- backup metadata DB: `~/Library/Application Support/Ursus/backups.sqlite`
- backup quarantine: `~/Library/Application Support/Ursus/Backups/_quarantine`
- bridge auth DB: `~/Library/Application Support/Ursus/Auth/bridge-auth.sqlite`
- runtime lock: `~/Library/Application Support/Ursus/Runtime/.server.lock`
- runtime state DB: `~/Library/Application Support/Ursus/Runtime/runtime-state.sqlite`
- current app bundle state: `~/Library/Application Support/Ursus/Runtime/current-app-bundle.json`
- bridge runtime state: `~/Library/Application Support/Ursus/Runtime/bridge-runtime-state.json`
- debug log: `~/Library/Application Support/Ursus/Logs/debug.log`
- bridge stdout log: `~/Library/Application Support/Ursus/Logs/bridge.stdout.log`
- bridge stderr log: `~/Library/Application Support/Ursus/Logs/bridge.stderr.log`
- public launcher: `~/.local/bin/ursus`
- bridge LaunchAgent plist: `~/Library/LaunchAgents/com.aft.ursus.plist`
- temp fallback locks: `TMPDIR/ursus/Runtime/...`

## Current Technical Truths

- Config and template editing are JSON / file based under `~/Library/Application Support/Ursus`.
- The Bear database path is resolved directly from Bear's canonical group-container path and is not stored in `config.json`.
- The selected-note token is managed in macOS Keychain through Ursus-owned code rather than `config.json`.
- Discovery page size and snippet length come from config defaults; MCP discovery inputs do not accept per-call `limit` or `snippet_length` overrides.
- Backup snapshot payloads live in canonical per-note folders under `Backups/<note-id>/<snapshot-id>.json`; rebuildable metadata lives in root-level `backups.sqlite`.
- Successful user-meaningful MCP operations are counted in `Runtime/runtime-state.sqlite`; probes and failed tool calls are excluded, and successful operations inside batches are counted per operation.
- Debug builds include hidden donation-testing CLI flags; release builds keep threshold-only behavior.
- App bundle versioning has one release-facing source of truth in the Xcode project build settings.
- Bridge HTTP request tracing writes compact ingress/egress lines to `Logs/debug.log`, including a `base-url-miss` hint when clients hit the bridge origin instead of the MCP endpoint.
- If MCP behavior changes in a way that `tools/list` will not reflect on its own, bump `UrsusMCPServer.bridgeSurfaceEpoch`.
- Host integrations are explicit per app rather than generic. Codex merges `~/.codex/config.toml`, Claude Desktop merges `claude_desktop_config.json`, and Claude CLI merges `~/.claude.json`. Rewrites preserve unrelated settings, and destructive recovery plus Codex TOML rewrites create sibling backup files before overwriting the file.

## Working Documentation Set

- `docs/MAINTAINER_NOTES.md`: current maintainer handoff and next queue
- `docs/ARCHITECTURE.md`: current runtime and behavior shape
- `docs/BUILD_INSTALL.md`: practical local build, release, reset, and bridge testing guide
- `docs/appcast.xml`: Sparkle appcast feed

Historical implementation plans and the standalone selected-note helper note are intentionally gone. Helper behavior is now covered by the architecture and maintainer notes.

## Next Implementation Queue

Current near-term priorities:

1. Validate the protected bridge against more real remote-host interoperability cases now that bearer-token MCP access is in place.
2. Decide whether bridge diagnostics need a lightweight authenticated probe, or whether the current transport-up plus OAuth-challenge model is sufficient.

## Verification Baseline

Use this baseline before release-impacting changes:

```sh
swift test
swift build
CONFIGURATION=Debug Support/scripts/build-ursus-app.sh
swift run ursus doctor
swift run ursus --help
swift run ursus bridge status
```

For release builds, follow `docs/BUILD_INSTALL.md`; it includes version bumping, Developer ID signing/notarization, DMG creation, release notes, and Sparkle appcast generation.
Release artifacts should be universal. Check the app executable and helper before uploading:

```sh
lipo -archs ".build/UrsusApp/Build/Products/Release/Ursus.app/Contents/MacOS/Ursus"
lipo -archs ".build/UrsusApp/Build/Products/Release/Ursus.app/Contents/Library/Helpers/Ursus Helper.app/Contents/MacOS/ursus-helper"
```
