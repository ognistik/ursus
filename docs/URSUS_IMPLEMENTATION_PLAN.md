# Ursus Implementation Plan

This document is the execution handoff for the first public-release identity reset of this project.

Scope:

- planning to implementation handoff
- product identity reset from `bear-mcp` / `Bear MCP` to `Ursus` / `ursus`
- storage unification under one canonical macOS app root
- prerelease cleanup with no compatibility-by-default

Non-goals:

- do not change `bear_*` MCP tool names
- do not change the Bear integration model
- do not move reads away from Bear SQLite
- do not move writes away from Bear x-callback-url
- do not collapse the current package layering
- do not add compatibility aliases unless there is a hard technical need

## Product Decisions Locked In

- Product / app / brand name: `Ursus`
- CLI executable: `ursus`
- App shell: `Ursus.app`
- MCP server name exposed to hosts: `ursus`
- Bundle id namespace: `com.aft.ursus`
- User-facing identity should be `Ursus` / `ursus` everywhere possible
- Keep `Bear` only where it describes the Bear integration domain itself
- MCP tool names remain `bear_*`
- Clean install is acceptable; do not preserve prerelease migrations by default

## Bear vs Ursus Boundary

Use `Ursus` for:

- app title and bundle name
- CLI name and launcher path
- MCP server name in host configs
- LaunchAgent label and plist name
- runtime/storage root names
- docs, UI copy, diagnostics, onboarding, install guidance
- helper app branding and callback scheme

Keep `Bear` for:

- `bear_*` tool names
- Bear note/tag/database/x-callback semantics
- Bear-specific integration wording inside tool docs and mutation/read behavior
- internal implementation areas where `Bear` describes the integration domain rather than the product

## Canonical Runtime Layout

Adopt one canonical app root:

- config: `~/Library/Application Support/Ursus/config.json`
- template: `~/Library/Application Support/Ursus/template.md`
- logs: `~/Library/Application Support/Ursus/Logs/debug.log`
- backups: `~/Library/Application Support/Ursus/Backups/`
- backup index: `~/Library/Application Support/Ursus/Backups/index.json`
- runtime lock: `~/Library/Application Support/Ursus/Runtime/.server.lock`
- fallback temp locks: `TMPDIR/ursus/Runtime/...`
- bridge stdout log: `~/Library/Application Support/Ursus/Logs/bridge.stdout.log`
- bridge stderr log: `~/Library/Application Support/Ursus/Logs/bridge.stderr.log`
- LaunchAgent plist: `~/Library/LaunchAgents/com.aft.ursus.plist`
- public launcher: `~/.local/bin/ursus`

Why:

- the app is now the control center
- config and `template.md` are app-owned assets
- shipping `~/.config/bear-mcp` alongside `Application Support/Bear MCP` would preserve a split identity on day one
- keeping logs, backups, and runtime files under one `Application Support/Ursus` root makes reset, diagnostics, and support simpler

## Compatibility / Legacy Stance

Default rule:

- do not preserve prerelease identity or migrations unless a concrete runtime conflict would result

Delete entirely:

- support-root migration from `~/Library/Application Support/bear-mcp`
- log migration from `~/Library/Logs/bear-mcp`
- backup merge helpers added only for prerelease support-root changes
- any old launcher fallback guidance that references `Bear MCP.app`
- old host-config detection/guidance for server key `bear`

Explicitly avoid:

- adding new fallback reads from old config locations
- dual-writing config/template to old and new roots
- keeping old launcher names or old LaunchAgent labels as supported identities
- shipping compatibility aliases for old app/helper names

Optional narrow exception:

- if needed during rename execution, a one-time manual clean-reset instruction is acceptable
- do not build an automatic migration framework for it

## Internal Naming Policy

For the first public release:

- rename all shipped surfaces
- keep current package layer boundaries
- it is acceptable to keep internal target/type/file names like `BearCore`, `BearApplication`, `BearMCP`, and similar for now

Reason:

- the product identity reset is already wide
- internal module renames are high-churn and low user value
- shipped identity matters more than internal symbol cleanup for this release

Revisit later only if there is clear value in a second internal cleanup pass.

## Execution Strategy

The work should be done in phases with hard verification gates. Do not blend all of this into one giant rename.

### Phase 1: Freeze Identity Constants

Goal:

- define the final shipped identity in code and metadata before touching docs/UI drift

Work:

- rename the CLI executable product from `bear-mcp` to `ursus`
- rename the app product/target/scheme from `Bear MCP` to `Ursus`
- set app bundle id to `com.aft.ursus`
- rename helper bundle id to `com.aft.ursus-helper`
- rename helper app to `Ursus Helper.app`
- rename helper executable to `ursus-helper`
- rename helper callback scheme from `bearmcphelper` to `ursushelper`
- rename MCP server name from `bear` to `ursus`
- rename LaunchAgent label from `com.aft.bear-mcp` to `com.aft.ursus`

Primary files:

- `Package.swift`
- `BearMCPApp.xcodeproj/project.pbxproj`
- `BearMCPApp.xcodeproj/xcshareddata/xcschemes/...`
- `Support/app/Info.plist`
- `Support/helper/Info.plist`
- `Support/scripts/build-bear-mcp-app.sh`
- `Support/scripts/build-selected-note-helper-app.sh`
- `Sources/BearMCP/BearMCPServer.swift`

Verification:

- `swift test`
- `CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh`
- verify built outputs are `Ursus.app`, bundled `ursus`, and embedded `Ursus Helper.app`
- verify MCP initialize reports server name `ursus`

### Phase 2: Canonical Storage Cutover

Goal:

- move the runtime to one canonical `Application Support/Ursus` root

Work:

- update all config/template paths to `~/Library/Application Support/Ursus`
- update logs/backups/runtime paths to `Ursus`
- update fallback temp runtime root to `ursus`
- update bridge log/plist generation to the new names
- update any user-facing error strings that mention old file paths

Primary files:

- `Sources/BearCore/BearPaths.swift`
- `Sources/BearApplication/BearRuntimeBootstrap.swift`
- `Sources/BearCore/BearDebugLog.swift`
- `Sources/BearApplication/BearService.swift`
- `Sources/BearApplication/BearAppSupport.swift`
- `Sources/BearCore/BearBridgeConfiguration.swift`

Important rule:

- remove prerelease migration logic instead of translating it to a new Ursus migration layer

Verification:

- `swift test`
- confirm `ursus paths` prints only Ursus-era paths
- confirm first launch creates only the new runtime locations
- confirm template/config editing in the app uses the new root only

### Phase 3: Launcher, App Locator, Bridge, and Helper Wiring

Goal:

- make install/repair behavior coherent under the new identity

Work:

- rename public launcher path to `~/.local/bin/ursus`
- regenerate launcher script text and candidate bundle paths for `Ursus.app`
- remove `Bear MCP.app` fallback search paths
- update app locator guidance to `Ursus.app`
- update helper locator to `Ursus Helper.app`
- update selected-note callback host and helper runner to the new helper scheme and names
- update bridge LaunchAgent plist generation and validation to the new label/path
- update any queue/logger/db labels that still leak `bear-mcp`

Primary files:

- `Sources/BearCore/BearMCPCLILocator.swift`
- `Sources/BearCore/BearMCPAppLocator.swift`
- `Sources/BearCore/BearSelectedNoteHelperLocator.swift`
- `Sources/BearXCallback/BearSelectedNoteCallbackHost.swift`
- `Sources/BearXCallback/BearSelectedNoteCallbackSession.swift`
- `Sources/BearXCallback/BearSelectedNoteHelperRunner.swift`
- `Sources/BearSelectedNoteHelper/main.swift`
- `Sources/BearCore/BearBridgeConfiguration.swift`
- `Sources/BearCore/BearProcessLock.swift`
- `Sources/BearDB/BearDatabaseReader.swift`
- `Sources/BearMCPCLI/BearTerminationSignalMonitor.swift`

Verification:

- install/repair launcher from app
- run `ursus --help`
- run `ursus doctor`
- run `ursus bridge status`
- install/remove/resume/pause bridge from app
- verify selected-note helper still resolves a selected note

### Phase 4: Host Integration and User-Facing Surface

Goal:

- make the product feel like one single product to end users and hosts

Work:

- change Codex snippets from `[mcp_servers.bear]` to `[mcp_servers.ursus]`
- change Claude Desktop snippet key from `"bear"` to `"ursus"`
- change all UI/dashboard copy from Bear MCP product language to Ursus product language
- keep Bear wording only where it refers to Bear notes/tags/database/actions
- update CLI usage text and bridge status wording to `ursus`

Primary files:

- `Sources/BearApplication/BearHostAppSupport.swift`
- `Sources/BearApplication/BearAppSupport.swift`
- `Sources/BearMCPCLI/BearCLICommand.swift`
- `Sources/BearMCPCLI/BearMCPMain.swift`
- `App/BearMCPApp/BearMCPApp.swift`
- `App/BearMCPApp/BearMCPAppModel.swift`
- `App/BearMCPApp/BearMCPDashboardView.swift`

Verification:

- manually inspect app UI strings
- verify host setup snippets show `ursus` server identity
- verify doctor output and launcher guidance use Ursus branding consistently
- verify Bear-domain tool names still remain `bear_*`

### Phase 5: Docs, Tests, and Status Alignment

Goal:

- eliminate drift so future threads inherit the correct product truth

Work:

- update `PROJECT_STATUS.md` to the new identity and paths
- update architecture/build/install/helper docs
- add or update clean-reset guidance for removing old prerelease artifacts manually
- update tests for new names, paths, scheme values, helper scheme, LaunchAgent label, server name, and docs-sensitive strings
- search for remaining `Bear MCP`, `bear-mcp`, `bearmcphelper`, `.config/bear-mcp`, and `com.aft.bear-mcp`

Primary files:

- `PROJECT_STATUS.md`
- `docs/ARCHITECTURE.md`
- `docs/APP_UNIFICATION_PLAN.md`
- `docs/LOCAL_BUILD_AND_CLEAN_INSTALL.md`
- `docs/SELECTED_NOTE_HELPER.md`
- affected tests in `Tests/`

Verification:

- `swift test`
- `CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh`
- repo-wide search returns only intentional Bear-domain uses

## Search Gates

Before closing the work, run focused searches to prove the identity reset is clean.

These should be near-zero or intentional-only:

- `rg -n "Bear MCP|bear-mcp|bearmcphelper|com\\.aft\\.bear" .`
- `rg -n "\\.config/bear-mcp|Application Support/Bear MCP|Library/Logs/bear-mcp" .`
- `rg -n "\\[mcp_servers\\.bear\\]|\"bear\"\\s*:" Sources App docs Tests`

Intentional survivors should be Bear-domain only:

- `bear_*` tool names
- Bear integration wording
- Bear database/x-callback semantics

## Acceptance Criteria

The implementation is complete when all of the following are true:

- the shipped app is `Ursus.app`
- the public CLI is `ursus`
- the MCP server name is `ursus`
- Bear tools are still named `bear_*`
- config and template live under `~/Library/Application Support/Ursus/`
- no runtime behavior depends on old `bear-mcp` or `Bear MCP` paths
- launcher repair/install works with the new app name and CLI name
- bridge LaunchAgent works with the new label/path
- selected-note helper works with the new helper bundle and callback scheme
- app UI, docs, and diagnostics consistently present Ursus as the product
- tests and docs are aligned with the new reality

## Recommended Order of Execution Across Threads

If this work is split across multiple threads, keep the order strict:

1. Phase 1 identity constants
2. Phase 2 storage cutover
3. Phase 3 launcher/helper/bridge wiring
4. Phase 4 host integration and UI wording
5. Phase 5 docs/tests/status cleanup

Do not start broad doc cleanup before the shipped/runtime identities are actually changed.

## Manual Clean Reset Guidance

Because prerelease compatibility is intentionally not preserved, it is acceptable to instruct local development threads to remove old artifacts manually before verifying the Ursus build.

That manual reset should remove old items such as:

- `/Applications/Bear MCP.app`
- `~/Applications/Bear MCP.app`
- `~/.local/bin/bear-mcp`
- `~/Library/Application Support/Bear MCP`
- `~/Library/Application Support/bear-mcp`
- `~/Library/Logs/bear-mcp`
- `~/Library/LaunchAgents/com.aft.bear-mcp.plist`

This is a manual cleanup aid, not a supported migration path.
