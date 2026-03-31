# Bear MCP App Unification Plan

This document is now a short live roadmap. Historical phase-by-phase detail was intentionally removed so future threads can load one current plan instead of re-reading superseded implementation history.

## Purpose

Keep the product app-centered without turning the GUI into the MCP runtime.

That means:

- `Bear MCP.app` stays the control center.
- The bundled `bear-mcp` CLI stays the local stdio MCP server.
- Host setup remains generic-first.
- The embedded helper remains the selected-note callback path.

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
- The app can manage configuration, token state, launcher repair, and the live `template.md` file.
- The app can also manage the optional localhost HTTP bridge, including a saved port setting, LaunchAgent lifecycle, status, and copyable MCP URL output.
- The app embeds the CLI and can install / repair the public launcher.
- Selected-note resolution prefers the installed app path and preserves the response-file contract.
- The CLI direct utility surface now includes `--new-note` override flags for title, tags, tag merge mode, content, and open/window behavior, plus `--apply-template`, `--archive-note`, and `--delete-note`.

## Current Cleanup Checkpoint

The repo is at a good place to stop and simplify before adding more features.

The main problems to address now are:

- docs are too long and too historical
- the app still shows too much implementation detail in its primary UI

## Recommended Order From Here

### 1. Simplify the app UI

Goal:

- make the app feel like a control center instead of a diagnostics dump

Likely next adjustments:

- reduce overview clutter
- move lower-value details out of the primary path
- keep setup guidance focused on the reusable launcher path
- continue trimming explicit maintenance ceremony

### 2. Remote MCP Bridge

Goal:

- keep the shipped localhost HTTP bridge stable while the rest of the app is simplified

High-level constraints:

- keep the feature optional
- keep it native to this project
- keep it centered on the stable public launcher path
- keep it localhost-only by default
- keep the chosen port stable once selected
- do not mix this slice with the later product rename

Current scope is complete:

- native localhost HTTP bridge is shipped
- bridge diagnostics now include MCP-health checks and log hints
- `bear-mcp bridge status` now reports LaunchAgent and health detail
- app users can edit the port before install and reuse the saved endpoint later, while host overrides stay config-only

## Likely Files For The Next Slices

- `App/BearMCPApp/BearMCPDashboardView.swift`
- `App/BearMCPApp/BearMCPAppModel.swift`
- `Sources/BearApplication/BearAppSupport.swift`
- `Sources/BearMCPCLI/BearCLICommand.swift`
- `Sources/BearMCPCLI/BearMCPMain.swift`

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
