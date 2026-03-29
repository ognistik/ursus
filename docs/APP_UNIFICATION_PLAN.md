# Bear MCP App Unification Plan

This document is now a short live roadmap. Historical phase-by-phase detail was intentionally removed so future threads can load one current plan instead of re-reading superseded implementation history.

## Purpose

Keep the product app-centered without turning the GUI into the MCP runtime.

That means:

- `Bear MCP.app` stays the control center.
- The bundled `bear-mcp` CLI stays the local stdio MCP server.
- Host setup remains generic-first.
- The standalone helper remains fallback-only.

## Decisions Locked In

- Keep the current package layers.
- Keep reads in SQLite and writes through Bear x-callback URLs.
- Keep config and the single-file template under `~/.config/bear-mcp`.
- Keep the public launcher path at `~/.local/bin/bear-mcp`.
- Keep trash CLI-only for now.
- Do not bring back the old AppleScript / Shortcuts bridge.
- Do not redesign template storage into header/footer files.

## Completed Foundation

These slices are already in place:

- `Bear MCP.app` exists and links the shared package code.
- The app can manage configuration, token state, and launcher repair.
- The app embeds the CLI and can install / repair the public launcher.
- Selected-note resolution prefers the installed app path and preserves the response-file contract.
- The CLI already has a first direct utility surface with `--new-note`, `--apply-template`, and `--delete-note`.

## Current Cleanup Checkpoint

The repo is at a good place to stop and simplify before adding more features.

The main problems to address now are:

- docs are too long and too historical
- template management is still filesystem-first instead of app-first
- `--update-config` is still hanging around as dead-looking compatibility code
- runtime naming is inconsistent across bundle id, Application Support, and logs
- the direct CLI utility surface is useful, but not yet complete enough for automation-friendly note creation

## Recommended Order From Here

### 1. Finish the documentation cleanup

Goal:

- keep one concise status file and one concise roadmap
- remove stale Keychain-era planning language
- avoid helper-only release/testing duplication

This cleanup should land before more feature work so future threads start from cleaner context.

### 2. Move template editing into the app

Goal:

- make `Bear MCP.app` the place where users actually manage `template.md`

Scope:

- show the current template path
- reveal/open the file from the app
- add inline template editing
- validate `{{content}}` and `{{tags}}` slots before save
- surface clear warnings and errors

Non-goal:

- do not redesign storage
- do not move the template out of `~/.config/bear-mcp/template.md`

### 3. Remove `--update-config`

Goal:

- drop the legacy compatibility flag once the app fully owns the remaining config/template editing flow

Requirement before removal:

- the app must already provide an easy path for template/config management and launcher refresh

### 4. Clean up naming and runtime paths together

Goal:

- make app-facing metadata and runtime storage feel like one coherent product

Planned changes:

- app bundle identifier: `com.aft.bearmcp`
- Application Support root: `~/Library/Application Support/Bear MCP`
- debug log location: inside that Bear MCP support root, not `~/Library/Logs`

Migration note:

- do this as one coordinated slice rather than piecemeal
- keep `~/.config/bear-mcp` for config and `template.md`

### 5. Expand the direct CLI utility surface

Goal:

- make direct CLI usage strong enough for manual workflows and automations, not only for MCP hosts

Next additions:

- add `bear-mcp --archive-note [note-id-or-title ...]`
- expand `bear-mcp --new-note` with override flags for title, tags, tag merge mode, content, and open/window behavior

Required behavior for `--archive-note`:

- no arguments targets the selected Bear note
- passed arguments resolve exact note id first, then exact case-insensitive title
- support one or many note arguments

Required behavior for the expanded `--new-note` flow:

- no extra flags preserves today's behavior exactly
- explicit overrides allow automation-friendly note creation
- explicit-override mode should not consult selected-note text
- if explicit mode is used without tags, default to inbox tags
- append remains the default tag merge mode unless explicitly changed

### 6. Simplify the app UI

Goal:

- make the app feel like a control center instead of a diagnostics dump

Likely follow-up after template editing lands:

- reduce overview clutter
- move lower-value details out of the primary path
- keep setup guidance focused on the reusable launcher path
- continue trimming explicit maintenance ceremony

## Likely Files For The Next Slices

- `App/BearMCPApp/BearMCPDashboardView.swift`
- `App/BearMCPApp/BearMCPAppModel.swift`
- `Sources/BearApplication/BearAppSupport.swift`
- `Sources/BearApplication/BearService.swift`
- `Sources/BearCore/BearPaths.swift`
- `Sources/BearMCPCLI/BearCLICommand.swift`
- `Sources/BearMCPCLI/BearMCPMain.swift`
- `Support/app/Info.plist`
- `BearMCPApp.xcodeproj/project.pbxproj`

## What Not To Do

- do not move MCP stdio serving into the GUI app
- do not redesign the service layer
- do not change template storage away from one `template.md`
- do not expose CLI-only trashing through MCP unless explicitly requested
- do not spread runtime files across more macOS locations than necessary

## Verification Baseline

For the next implementation slices, keep the baseline checks:

- `swift test`
- `CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh`
