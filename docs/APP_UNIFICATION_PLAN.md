# Bear MCP App Unification Plan

This document is the implementation plan for moving `bear-mcp` from:

- `bear-mcp` CLI
- plus a separate `Bear MCP Helper.app`

to:

- one canonical signed macOS app bundle
- with the callback receiver built in
- with the CLI still preserved as the headless MCP execution layer

This plan is intentionally incremental. It is designed to preserve the working system and reduce product/design friction without rewriting the server.

## Status Checkpoint

As of 2026-03-28:

- Phase 1 has started in the repo: selected-note callback-host behavior now lives in shared package code at `Sources/BearXCallback/BearSelectedNoteCallbackHost.swift`.
- `Sources/BearSelectedNoteHelper/main.swift` is now a thin AppKit shell that forwards launch and callback handling into that shared host.
- Phase 2 has now landed in the repo: `BearMCPApp.xcodeproj` builds a minimal `Bear MCP.app`, links the shared package through a new `BearApplication` library product, registers `bearmcp://`, and renders basic diagnostics/settings scaffolding.
- Phase 3 has now landed incrementally in the repo: selected-note resolution prefers `Bear MCP.app`, preserves the CLI response-file contract, uses `bearmcp://` for callbacks, and now reuses an already-running dashboard instance instead of requiring the app to quit first.
- Phase 4 has now started in the repo: selected-note token lookup prefers Keychain, the CLI still falls back to legacy `config.token`, diagnostics now report whether the token is coming from Keychain or legacy config, `Bear MCP.app` now has a first token-management UI for save/import/remove flows, and the preferred app-installed selected-note path now injects the managed token inside the app so ordinary CLI startup does not need to probe Keychain.
- Routine doctor/dashboard status loading now relies on the non-secret Keychain hint by default instead of eagerly reading Keychain, so normal diagnostics do not trigger authorization prompts unless the user explicitly opens token-management actions that need the secret.
- Phase 5 has now started in the repo: the local app build now embeds `bear-mcp` inside `Bear MCP.app`, the dashboard can install or refresh that bundled CLI to `~/Library/Application Support/bear-mcp/bin/bear-mcp`, and doctor/app diagnostics now distinguish between the bundled app copy and the stable host-facing CLI path.
- The onboarding slice has now widened into a more host-agnostic Phase 5 direction: the dashboard/settings surface still includes host-specific guided checks for common apps, but it now also includes generic local-stdio guidance that is not tied to Codex or Claude Desktop.
- Broader settings editing is no longer just pending: the app now has a real editable configuration flow for core defaults, discovery limits, inbox tags, and tool availability.
- Tool availability can now be controlled from config/app UI, and the live MCP tool catalog filters out disabled tools.
- The app can now install a copied terminal executable at `~/bin/bear-mcp` so the CLI is easier to run directly outside host-app onboarding, and older terminal installs are now treated as refreshable migration state rather than the preferred setup.
- The standalone helper app remains available as a narrow helper fallback when the preferred app is not installed.
- `/Applications/Bear MCP.app` is now the canonical preferred install location. `~/Applications/Bear MCP.app` remains a fully supported user-specific install location.
- Local development builds are available through `Support/scripts/build-bear-mcp-app.sh`.

## Decisions Locked In

These decisions should be treated as the working product direction unless explicitly changed later.

- The project remains a local macOS MCP server for Bear.
- The CLI remains the MCP execution/runtime layer for stdio/headless use.
- The app becomes the control center for install, config editing, token setup, diagnostics, and optional advanced features.
- Host guidance should stay generic-first, with app-specific snippets treated as convenience layers rather than hard-coded product assumptions.
- Basic MCP usage must not require the GUI to be manually open.
- Config stays JSON-based for now.
- Product-level tool enable/disable belongs in config/app state, not only in host-app UX.
- The Bear token should move out of JSON config and into Keychain.
- The callback URL scheme should be simplified from `bearmcphelper://` to `bearmcp://`.
- The separate helper app should be absorbed into the main app bundle.
- The old direct-localhost callback experiment should not be treated as the primary path, because it was tried already and did not behave correctly in real use.
- No XPC is required for the first app-centered architecture.
- No Sparkle.
- Updates should be GitHub-based and simple enough for a free/open-source project.
- A Homebrew cask is a good distribution path, but the app itself may also check GitHub for updates directly.

## Current Architecture Summary

The current codebase already has a strong separation of responsibilities. The goal is to preserve that.

### Swift package products

- `bear-mcp` executable
- `bear-mcp-helper` executable

See:

- `Package.swift`

### Current layers

- `BearCore`
  - config types
  - paths
  - domain models
  - process lock
  - helper locator
- `BearDB`
  - read-only SQLite access
- `BearXCallback`
  - Bear URL construction
  - Bear app launch
  - selected-note helper launch
- `BearApplication`
  - orchestration
  - template-aware mutation planning
  - doctor/bootstrap
  - backup store
- `BearMCP`
  - MCP tool registration
  - argument decoding
- `BearMCPCLI`
  - command entrypoint
  - `mcp`, `doctor`, `paths`, `--update-config`

### Important current files

- `Sources/BearMCPCLI/main.swift`
- `Sources/BearApplication/BearRuntimeBootstrap.swift`
- `Sources/BearApplication/BearService.swift`
- `Sources/BearDB/BearDatabaseReader.swift`
- `Sources/BearXCallback/BearXCallbackTransport.swift`
- `Sources/BearXCallback/BearXCallbackURLBuilder.swift`
- `Sources/BearXCallback/BearSelectedNoteHelperRunner.swift`
- `Sources/BearSelectedNoteHelper/main.swift`
- `Sources/BearCore/BearConfiguration.swift`
- `Sources/BearCore/BearPaths.swift`
- `Sources/BearCore/BearSelectedNoteHelperLocator.swift`
- `Support/helper/Info.plist`
- `Support/scripts/build-selected-note-helper-app.sh`

### Current callback flow

Current selected-note resolution works like this:

1. CLI builds a Bear `open-note?selected=yes&token=...` x-callback URL.
2. If `Bear MCP.app` is not running, the CLI launches it in headless callback-host mode with the existing response-file contract.
3. If `Bear MCP.app` is already running in dashboard mode, the CLI sends it a `bearmcp://x-callback-url/start-selected-note-host?...` request so the live app instance can start an in-process callback session.
4. The app-hosted callback session rewrites `x-success` and `x-error` to `bearmcp://`.
5. Bear calls back into `Bear MCP.app`.
6. The app writes JSON back to the CLI and either exits its headless instance or returns to dashboard mode.

The standalone helper path still exists as a narrow fallback when `Bear MCP.app` is not installed.

## Target Product Shape

The desired architecture is:

- `Bear MCP.app` is the canonical install artifact.
- The app owns:
  - callback URL handling
  - onboarding
  - settings/config editor
  - token management
  - diagnostics
  - update checks
  - CLI installation/exposure
- The app should expose both:
  - a stable host-facing CLI path for MCP hosts
  - an optional terminal-friendly copied executable for direct shell usage
- The CLI remains a separate executable binary inside the product, used by MCP clients for stdio operation.
- The app does not become the stdio MCP server.

This means the product becomes app-centered, not app-only.

## Recommended Architecture

### 1. Keep the package layers

Do not flatten or redesign the server.

Keep:

- `BearCore`
- `BearDB`
- `BearXCallback`
- `BearApplication`
- `BearMCP`
- `BearMCPCLI`

These are already the right long-term seams.

### 2. Add a real app target

Add a proper macOS app target in Xcode that links the Swift package code.

Recommended shape:

- keep `Package.swift` for libraries + CLI
- add an Xcode project for the app bundle
- the app target depends on local package products

Why:

- signing, notarization, archive/export, URL schemes, resources, and app bundling are all easier in a native app target than trying to force the whole product through SwiftPM-only packaging
- this preserves the Swift package as the reusable/core implementation layer

### 3. Replace the separate helper with an app-hosted callback mode

Do not invent a whole new IPC system first.

Instead, preserve the current helper contract:

- CLI launches the app in a headless callback-host mode
- CLI passes the Bear x-callback request and a response-file path
- app receives Bear callback on `bearmcp://`
- app writes JSON result to the response file
- CLI waits for the file result exactly like today

This is the lowest-risk migration because it keeps the already-proven control flow and only changes where that logic lives.

### 4. Keep config JSON, move secrets out

Short-term:

- keep `~/.config/bear-mcp/config.json`
- keep `template.md`
- keep current config keys for compatibility

Change:

- move Bear token storage to Keychain
- leave a compatibility migration path from `config.token`

Recommended behavior:

- app UI edits JSON-backed settings directly
- app stores token in Keychain
- CLI reads Keychain first
- if Keychain is empty and `config.token` exists:
  - use it
  - optionally migrate it into Keychain
  - then clear it from config on explicit save/update flow

### 5. Keep update behavior simple

Because this is a free/open-source project, avoid Sparkle and avoid building a complex self-patching updater.

Recommended update model:

- app checks GitHub Releases for the latest version
- app compares latest available version vs current app version
- app can auto-check on launch or on a periodic schedule if enabled in settings
- app offers:
  - `Check for Updates`
  - optional automatic background check
  - download latest release asset directly from GitHub

Recommended release assets:

- signed and notarized `.zip` or `.dmg` containing `Bear MCP.app`

Important tradeoff:

- fully automatic in-place app replacement is the part that usually becomes fragile without Sparkle
- the low-complexity path is:
  - auto-check
  - show available version
  - download
  - guide/install via a controlled replacement flow

If later you decide you truly want fully silent app replacement, that should be a separate phase and treated as extra complexity, not as day-one scope.

### 6. Use a Homebrew cask, not a formula, for app distribution

Recommended distribution:

- GitHub Releases as canonical artifacts
- Homebrew cask for discoverability/install convenience

Why:

- a cask matches a signed `.app` bundle
- a formula is better for CLI-first distribution
- the product is moving to app-first packaging

The CLI can still be bundled inside the app and exposed for MCP clients.

## What Stays in the CLI

The CLI should keep responsibility for:

- stdio MCP runtime
- process lock management
- parent-process shutdown logic
- MCP tool registration
- DB reads
- x-callback write submission
- note mutation verification/polling
- headless diagnostics
- config loading
- Keychain token lookup

Do not move these into the GUI unless there is a strong reason.

## What Moves Into the App

The app should own:

- callback URL registration using `bearmcp://`
- callback result handling
- onboarding/setup flow
- settings UI
- config editing
- token entry/removal
- update checks
- diagnostics UI
- CLI installation/exposure

Optional later additions:

- log viewer
- broader host coverage beyond Codex / Claude Desktop / ChatGPT
- deeper automated validation for host-specific config state and restart flows

## CLI/App Communication Plan

Do not start with XPC.

### First implementation contract

Use a simple app-launch + response-file contract:

1. CLI creates a temporary response file path.
2. CLI launches `Bear MCP.app` with arguments describing the callback request.
3. App enters a headless callback-host mode.
4. App launches the Bear x-callback URL.
5. Bear calls `bearmcp://...`.
6. App writes JSON result to the response file.
7. CLI reads the file, parses it, and continues.

This is basically the current helper protocol, but hosted by the main app.

### Why not XPC now

XPC would add:

- another communication layer
- another lifecycle surface
- more signing/entitlement complexity
- more debugging overhead

For the current product goals, it is unnecessary.

## Token Storage Plan

### Target behavior

- store the Bear API token in the user Keychain
- do not keep it as the long-term source of truth in `config.json`

### Recommended ownership split

- app UI is the friendly editor for token entry/removal
- core/token-access code is shared so CLI can read it headlessly

### Migration behavior

Phase 1:

- add shared Keychain wrapper
- CLI checks Keychain first
- if missing, falls back to `config.token`

Phase 2:

- app offers “Import token from config” if found
- after successful import, remove token from config during explicit save/update

### Files likely involved

- `Sources/BearCore/BearConfiguration.swift`
- `Sources/BearApplication/BearRuntimeBootstrap.swift`
- new shared Keychain helper file, likely in `BearCore` or `BearApplication`

## Callback Handling Plan

### Current source of truth

The existing working behavior is in:

- `Sources/BearSelectedNoteHelper/main.swift`
- `Sources/BearXCallback/BearSelectedNoteHelperRunner.swift`

### Target

Move that logic into the main app bundle and rename the callback scheme to `bearmcp://`.

### Important note

There is also callback-related localhost listener code in:

- `Sources/BearXCallback/BearSelectedNoteCallbackSession.swift`
- `Sources/BearXCallback/BearXCallbackURLBuilder.swift`

That code should not be treated as the primary path for the unified product because it was previously not reliable in real use.

Recommended action:

- do not wire new architecture around it
- once the app-hosted callback path is stable, either:
  - remove it, or
  - clearly mark it as unused experimental code

This will reduce future confusion.

## Config Management Plan

### Keep

- `~/.config/bear-mcp/config.json`
- `~/.config/bear-mcp/template.md`

### Change

- app becomes the main editor for these files
- CLI remains compatible with manual edits

### UX recommendation

The app settings UI can be intentionally simple:

- a form for common fields
- an “advanced JSON” editor/view if desired
- template file open/reveal buttons

You do not need a complicated settings architecture to ship this.

## Diagnostics Plan

Keep the existing doctor logic as the base.

### Current doctor source

- `Sources/BearApplication/BearRuntimeBootstrap.swift`

### Evolve it into two surfaces

- CLI:
  - keep `bear-mcp doctor`
- app:
  - render the same checks in a diagnostics screen

Add checks for:

- app installed correctly
- callback scheme registration
- embedded CLI presence
- CLI executable permissions
- Bear DB readable
- config readable
- template present
- Keychain token present
- Bear app installed
- selected-note callback round-trip health

## Update Check Plan

### Recommended minimum viable updater

1. App setting: `Automatically check for updates`
2. App reads current version from bundle metadata
3. App fetches latest version metadata from GitHub Releases or a tiny version manifest in the repo
4. App compares versions
5. If newer version exists:
   - show release notes
   - offer download/open release page
   - optionally download the release asset directly

### Recommendation

Start with:

- auto-check
- notify
- download/open release asset

Do not start with:

- fully silent background self-replacement

That keeps the updater small and maintainable.

### Possible metadata sources

Option A:

- GitHub Releases API

Option B:

- a small `latest.json` file hosted from the repo or release assets

Recommendation:

- GitHub Releases API first, unless rate limiting or release metadata control becomes annoying

## Packaging And Distribution Plan

### Canonical artifact

- signed + notarized `Bear MCP.app`

### Release channel

- GitHub Releases

### Convenience install path

- Homebrew cask

### CLI exposure

Recommended options:

- app bundles the CLI binary internally
- app offers an “Install CLI” action that copies it to a stable user path

Recommended stable path:

- `~/Library/Application Support/bear-mcp/bin/bear-mcp`

Recommended terminal path:

- `~/bin/bear-mcp`

Preferred behavior:

- treat the app-managed CLI copy as the source of truth
- let the app install or refresh a direct executable copy at predictable user paths
- avoid exposing long app-bundle-internal paths in onboarding snippets
- treat copied terminal executables as the polished default, with any older terminal installs refreshed forward

The app should also expose the absolute CLI path for users who want to point MCP clients at it directly.

## 2026-03-28 Product Follow-Ups

This section captures product direction raised after the initial Phase 5 onboarding/config work. These items are not all implemented yet, but they should guide the next slices.

### 1. App-first CLI lifecycle

The product should feel like one app with a bundled CLI, not a collection of loose pieces.

Direction:

- `Bear MCP.app` should remain the control center
- the app should be able to install or refresh the bundled CLI into stable user-facing locations
- over time, first run and post-update flows should check whether the installed CLI copy is missing or stale and offer a lightweight refresh
- user-facing setup copy should prefer predictable paths like `~/bin/bear-mcp` over long `Application Support` internals when that can be done safely

Important note:

- the copied `~/bin/bear-mcp` install has now landed, but first-run and post-update refresh prompts for missing or stale copies are still pending

### 2. CLI surface should expand for direct user actions

The CLI should remain useful even when the user is working directly in Bear without an MCP host.

Planned additions:

- `bear-mcp --new-note`
  - create a new note through the existing template-aware flow
  - title defaults to the current local date/time format like `yyMMdd - hh:mm a`
  - use Bear URL flags `new_window=no`, `open_note=yes`, and `edit=yes`
  - if a selected note exists, copy only that note’s tags into the new note
  - if no selected-note tags exist, fall back to configured inbox tags
- `bear-mcp --delete-note [ids...]`
  - if no ids are passed, trash the currently selected Bear note
  - if one or more ids are passed, trash those explicit notes in batch
  - keep this CLI-only for now rather than exposing trashing in MCP tools
- `bear-mcp --apply-template [ids...]`
  - if no ids are passed, apply the current template to the selected note
  - if ids are passed, normalize those notes with the same template logic already used by `bear_apply_template`

### 3. `--update-config` is now compatibility-first

Current behavior is still useful because it rewrites `config.json` into the latest known shape without dropping values.

Longer-term direction:

- app-managed save/migration flows should become the main way configuration evolves
- once the app owns config migration and CLI refresh cleanly enough, `--update-config` should be removed rather than kept around as dead compatibility code
- do not remove it before the app provides an easy update path for both configuration shape changes and CLI refresh behavior

### 4. UI simplification now matters more than deeper host automation

The dashboard has crossed the line from “missing features” into “too much surface area”.

Next UX goals:

- reduce mental load on first launch
- remove low-value implementation details from primary views
- keep version/build/bundle diagnostics in an About surface rather than the main dashboard
- show host-specific setup only when the corresponding app is actually installed or relevant
- keep generic local-stdio guidance as the baseline
- move the configuration flow toward inline validation plus auto-save rather than explicit draft/save ceremony
- rename scary or ambiguous actions to clearer language
- consider folding token management into configuration instead of keeping it as a heavyweight separate tab
- treat closing the main window as quitting the app unless a background mode is introduced later

Concrete polish candidates:

- replace `Save Configuration` with auto-save
- replace `Reset Draft` with clearer wording such as `Reset to Saved` or `Reset to Defaults`, depending on behavior
- prefer `Reveal Configuration` over encouraging direct JSON editing
- add template viewing/editing from the app once the core configuration flow is calmer

### 5. Runtime cleanup and naming cleanup should be coordinated

Several cleanup items are desirable, but they affect compatibility and should be grouped thoughtfully.

Planned cleanup items:

- move debug logging from `~/Library/Logs/bear-mcp/` into `~/Library/Application Support/bear-mcp/`
- stop writing `"token": null` when no legacy config token exists
- migrate app/bundle/keychain naming away from user-specific prefixes toward a stable identifier such as `com.aft.bear-mcp`

Important migration note:

- bundle identifier, URL metadata, and Keychain service naming should be updated together to avoid accidental token duplication or loss during the transition

## File-By-File Impact Map

This section is intended to help a new conversation pick up implementation quickly.

### Keep and reuse

- `Sources/BearMCPCLI/main.swift`
  - CLI stays the MCP runtime
- `Sources/BearApplication/BearService.swift`
  - no redesign required
- `Sources/BearDB/BearDatabaseReader.swift`
  - no redesign required
- `Sources/BearMCP/BearMCPServer.swift`
  - no redesign required
- `Sources/BearXCallback/BearXCallbackTransport.swift`
  - keep as write transport
- `Sources/BearXCallback/BearXCallbackURLBuilder.swift`
  - keep Bear URL construction

### Refactor soon

- `Sources/BearSelectedNoteHelper/main.swift`
  - extract callback-host logic into shared code
  - stop treating it as a standalone product endpoint
- `Sources/BearXCallback/BearSelectedNoteHelperRunner.swift`
  - replace helper-app launching with main-app callback-host launching
- `Sources/BearCore/BearSelectedNoteHelperLocator.swift`
  - replace helper-specific locator with app bundle / embedded tool locator
- `Support/helper/Info.plist`
  - replace or supersede with the main app bundle Info.plist

### Likely add

- app target sources
  - app entrypoint
  - settings window
  - diagnostics window/view
  - update checker
  - callback app delegate/router
- shared token/keychain helper
- shared callback-host service extracted from current helper main
- shared CLI installer helper
- shared release/update metadata helper

### Likely clean up later

- `Sources/BearXCallback/BearSelectedNoteCallbackSession.swift`
  - remove or explicitly mark unused if the app-hosted callback scheme replaces it
- `docs/SELECTED_NOTE_HELPER.md`
  - rewrite as app-hosted callback documentation
- `docs/HELPER_RELEASE_AND_TESTING.md`
  - replace with unified app release/testing docs

## Recommended Phases

## Phase 0: Planning and cleanup docs

Goal:

- capture the target design clearly before implementation starts

Tasks:

- add this plan document
- stop future threads from treating the separate helper as the long-term product shape
- note that the localhost callback experiment is not the intended architecture

## Phase 1: Extract callback-host logic

Goal:

- separate “callback-host behavior” from the standalone helper executable

Status:

- Landed on 2026-03-28. The helper now hosts shared callback logic instead of implementing the full flow inline.

Tasks:

- move helper request parsing, callback URL rewrite, response-file writing, and timeout behavior into shared code
- keep the current helper product working while doing this
- add tests around the shared callback-host logic

Why first:

- highest leverage
- lowest risk
- unlocks the main-app migration cleanly

## Phase 2: Add the macOS app target

Goal:

- create `Bear MCP.app` as a real bundle using the existing package code

Status:

- Landed on 2026-03-28. The repo now includes a minimal Xcode app target, local app build script, `bearmcp://` registration, and diagnostics/settings shell views while the separate helper remains the primary callback runtime.

Tasks:

- add Xcode app target
- register `bearmcp://`
- create minimal app shell
- add settings and diagnostics skeleton views
- link shared package modules

Deliverable:

- local app build that launches and can render diagnostics, with signing still deferred to release packaging

## Phase 3: Re-route selected-note callback flow through the app

Goal:

- make the main app replace the standalone helper for callback handling

Status:

- Landed incrementally on 2026-03-28 and manually validated end-to-end the same day against the real Bear app. The CLI now prefers `Bear MCP.app` as the callback host, preserves the response-file JSON contract, and can reuse an already-running dashboard instance through a `bearmcp://` start-request flow. The standalone helper remains available only as a narrow fallback when the preferred app is not installed.

Tasks:

- update the runner code to launch the main app in headless callback mode
- change callback scheme to `bearmcp://`
- preserve response-file JSON contract
- verify selected-note resolution works exactly like today
- support selected-note callback handling inside an already-running dashboard instance without relaunching the app

Deliverable:

- preferred selected-note callback path now runs through `Bear MCP.app` for both app-launch and already-running-app flows, with helper fallback narrowed to the preferred-app-missing case

## Phase 4: Move token storage to Keychain

Goal:

- remove plaintext token as the preferred storage source

Tasks:

- add shared Keychain wrapper
- change CLI token lookup order to Keychain first, config fallback second
- add token save/remove UI in the app
- add optional migration from `config.token`

Current repo status:

- shared Keychain wrapper: done
- CLI/selected-note lookup order: done
- app token save/remove/import UI: done
- compatibility fallback from `config.token`: done
- preferred app-installed selected-note flow now keeps Keychain access in `Bear MCP.app`, with non-secret config metadata used to avoid eager CLI Keychain reads: done
- broader settings editing beyond token management: still pending

Deliverable:

- selected-note targeting works with token stored in Keychain

## Phase 5: Bundle and expose the CLI from the app

Goal:

- make the app the canonical installation, while preserving a stable CLI path for MCP hosts

Tasks:

- embed the CLI binary in the app bundle or produce it alongside the app during build
- add an app action to install/expose the CLI to a stable path
- add diagnostics for CLI presence and permissions
- document how host apps should point to the CLI

Current repo status:

- local `Support/scripts/build-bear-mcp-app.sh` now embeds `bear-mcp` at `Bear MCP.app/Contents/Resources/bin/bear-mcp`: done
- app dashboard now has install/refresh, copy, and reveal controls for the stable CLI path at `~/Library/Application Support/bear-mcp/bin/bear-mcp`: done
- doctor/dashboard now report `bundled-cli` and `app-managed-cli` separately, which makes stale installed app bundles obvious: done
- terminal CLI installs at `~/bin/bear-mcp` now use a copied executable, and the app flags older terminal installs for refresh: done
- app settings and doctor now surface host-specific onboarding state for Codex and Claude Desktop, with ChatGPT explicitly called out as remote-only for now: done
- broader distribution/install polish around signed releases and automatic replacement of an older installed app bundle: still pending

Deliverable:

- users can install one app and get a working CLI path from it

## Phase 6: Add GitHub-based update checks

Goal:

- simple update checks without Sparkle

Tasks:

- implement release metadata fetch
- compare versions
- add settings toggle for automatic checks
- add manual “Check for Updates”
- add release notes / download UI

Deliverable:

- app can inform users of new versions and send them directly to the GitHub-hosted release asset

## Phase 7: Release packaging and cleanup

Goal:

- ship a coherent public product

Tasks:

- sign and notarize app
- publish GitHub release assets
- add Homebrew cask
- rewrite docs around the unified app-centered install
- remove stale helper-only language
- remove or clearly retire unused experimental callback code

Deliverable:

- first public release candidate

## What Not To Do

- do not rewrite the service layer
- do not move MCP stdio serving into the GUI app
- do not make basic CLI runtime depend on the app being visibly open
- do not add XPC before the simple response-file contract is exhausted
- do not switch config away from JSON yet
- do not build a complicated updater before basic GitHub update checks exist
- do not leave both the old helper path and the new app path half-configured without clear ownership

## Recommended Starting Task For The Next Implementation Thread

If a new conversation is going to begin implementation, the best first task is:

1. start Phase 2 by adding a minimal macOS app target that links the existing package modules
2. wire the app target for diagnostics/settings scaffolding and register `bearmcp://`
3. keep the current helper path working until the app-hosted callback route is verified end-to-end

That keeps momentum up while still preserving the currently working selected-note flow.

## Suggested Prompt For The Next Conversation

Use this as a starting point in a fresh implementation thread:

> Read `PROJECT_STATUS.md` and `docs/APP_UNIFICATION_PLAN.md`. Phase 1 is already landed. Start Phase 2 only: add a minimal macOS app target that links the existing package modules, registers `bearmcp://`, and renders basic diagnostics/settings scaffolding. Do not reroute the selected-note callback flow through the app yet. Keep the CLI runtime unchanged, keep the current helper path working, and avoid architecture rewrites. Update docs/tests as needed.
