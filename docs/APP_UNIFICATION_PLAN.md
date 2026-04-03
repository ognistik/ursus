# Ursus App Unification Plan

This document is now a short live roadmap. Historical phase-by-phase detail was intentionally removed so future threads can load one current plan instead of re-reading superseded implementation history.

## Purpose

Keep the product app-centered without turning the GUI into the MCP runtime.

That means:

- `Ursus.app` stays the control center.
- The bundled `ursus` CLI stays the local stdio MCP server.
- Host setup remains generic-first.
- The embedded helper remains the selected-note callback path.

## Decisions Locked In

- Keep the current package layers.
- Keep reads in SQLite and writes through Bear x-callback URLs.
- Keep config and the single-file template under `~/Library/Application Support/Ursus`.
- Keep the public launcher path at `~/.local/bin/ursus`.
- Keep trash CLI-only for now.
- Do not bring back the old AppleScript / Shortcuts bridge.
- Do not redesign template storage into header/footer files.

## Completed Foundation

These slices are already in place:

- `Ursus.app` exists and links the shared package code.
- The app can manage configuration, token state, launcher repair, and the live `template.md` file.
- The app can also manage the optional localhost HTTP bridge, including a saved port setting, LaunchAgent lifecycle, status, and copyable MCP URL output.
- The app owns the bundled launch path at `Contents/MacOS/Ursus`, and the public launcher can install / repair itself to forward into that executable with a hidden `--ursus-cli` entry flag.
- The public launcher now lives at `~/.local/bin/ursus`.
- Host setup snippets now recommend `ursus` consistently for Codex and Claude Desktop.
- Selected-note resolution prefers the installed app path and preserves the response-file contract.
- The CLI direct utility surface now includes `--new-note` override flags for title, tags, replace/open/window behavior, plus `--backup-note`, `--restore-note`, and `--apply-template`.
- Current status/build/helper docs are aligned to the shipped Ursus identity, and automated identity-gate tests now protect those current-truth surfaces from drifting back toward prerelease product wording.

## Current Cleanup Checkpoint

The repo is at a good place to simplify before adding more features.

The main remaining cleanup themes are:

- the app still shows too much implementation detail in its primary UI
- keep post-Phase-6 naming consistency intact while future work stays focused on UX and bridge behavior

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

Current scope is complete:

- native localhost HTTP bridge is shipped
- bridge diagnostics now include MCP-health checks and log hints
- `ursus bridge status` now reports LaunchAgent and health detail
- app users can edit the port before install and reuse the saved endpoint later, while host overrides stay config-only

## Likely Files For The Next Slices

- `App/UrsusApp/UrsusDashboardView.swift`
- `App/UrsusApp/UrsusAppModel.swift`
- `App/UrsusApp/main.swift`
- `Sources/BearApplication/BearAppSupport.swift`
- `Sources/BearMCPCLI/BearCLICommand.swift`
- `Sources/BearMCPCLI/UrsusMain.swift`
- `Sources/BearMCPCLIExecutable/UrsusMain.swift`

## What Not To Do

- do not move MCP stdio serving into the GUI app
- do not redesign the service layer
- do not change template storage away from one `template.md`
- do not expose CLI-only trashing through MCP unless explicitly requested
- do not spread runtime files across more macOS locations than necessary

## Verification Baseline

For the next implementation slices, keep the baseline checks:

- `swift test`
- `CONFIGURATION=Debug Support/scripts/build-ursus-app.sh`
