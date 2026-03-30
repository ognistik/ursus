# Remote MCP Bridge Plan

This document is the implementation handoff for an optional HTTP bridge that exposes the local `bear-mcp` stdio server to MCP clients that do not support local stdio MCPs directly.

The bridge is intentionally small in scope. It should feel like a practical utility feature inside `Bear MCP.app`, not a separate product and not a general-purpose proxy platform.

## Outcome

Add an optional `Remote MCP Bridge` feature that lets users:

- install or remove a per-user background bridge from the app
- get one stable localhost MCP URL they can copy into other AI apps
- keep using the existing `bear-mcp` launcher and bundled CLI runtime
- run the bridge without keeping the dashboard open

The intended user-facing result is:

- app UI label: `Remote MCP Bridge`
- CLI subcommand: `bear-mcp bridge`
- default endpoint shape: `http://127.0.0.1:<port>/mcp`

## Current Status

- Completed in the first slice:
  - upgraded `swift-sdk` to `0.12.0`
  - added bridge config/domain scaffolding, URL formatting, deterministic port selection, and LaunchAgent path/label constants
  - added `bear-mcp bridge serve`, `bear-mcp bridge status`, and `bear-mcp bridge print-url`
  - verified `swift test`, `CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh`, and a localhost smoke check for `bear-mcp bridge serve`
- Completed in the second slice:
  - added native LaunchAgent install/remove/status/pause/resume support in `BearApplication`
  - switched the expected LaunchAgent plist to `~/Library/LaunchAgents/com.aft.bear-mcp.plist`
  - wired bridge stdout/stderr logs into `~/Library/Application Support/Bear MCP/Logs/`
  - exposed bridge install/remove/pause/resume/copy/status actions in `Bear MCP.app`
  - removed the deprecated `Tool.Content.text(...)` call sites in `Sources/BearMCP/BearMCPServer.swift`
- Completed in the hardening follow-up:
  - bridge install/resume now wait for the localhost endpoint to accept TCP connections before reporting success
  - dashboard bridge status now distinguishes LaunchAgent `loaded` from endpoint `reachable`
  - LaunchAgent unload now skips benign `bootout` I/O failures when the service is already gone, avoiding false-negative installs with a leftover plist
  - the bridge runtime now uses the SDK's stateless HTTP transport for better first-connect compatibility with request/response-oriented MCP clients
  - repeated `initialize` requests against the running stateless bridge now return a fresh compatibility handshake instead of `Server is already initialized`, so hosts can remove and re-add the same URL without reinstalling the bridge
- Important note from the SDK work:
  - `0.11.0` is where the server HTTP transports appear, but `0.12.0` was the smallest clean upgrade on the current toolchain because `0.11.0` failed in the dependency with strict-concurrency diagnostics in `NetworkTransport`
- Not done yet:
  - richer bridge diagnostics beyond TCP reachability, such as more direct surfacing of stderr/log-tail hints or protocol-level health
  - any CLI-facing status expansion beyond the current config/status output
  - app UI support for editing the bridge host/port before install, even though the saved port itself is already stable in config

## Product Decisions Locked In

- This feature is optional.
- The bridge should be native to this project. Do not make the shipped beginner path depend on external Python tooling such as `mcp-proxy`.
- Keep the public launcher path as the stable runtime entrypoint.
- Do not break the existing stdio MCP flow, direct CLI utilities, selected-note helper flow, or current config/template paths.
- Do not turn this into a multi-server proxy manager.
- Do not expose the bridge on non-local interfaces by default.
- Do not rename the project, binary, package targets, config paths, or MCP tool names as part of this slice.

## Why This Exists

Today, some AI apps can only connect to MCP servers over HTTP and cannot spawn local stdio MCP processes directly. The current workaround requires users to:

- install a separate proxy tool
- run a manual command
- manage host and port details themselves

That is too much setup, especially for beginners. The app should be able to install and manage a simple localhost bridge for them.

## Non-Goals

- no named servers
- no bridge for arbitrary third-party MCP servers
- no remote URL client mode
- no OAuth layer
- no public internet exposure
- no broad CORS feature set unless a real product need appears
- no dependency on the selected-note helper
- no migration to the future `Ursus` rename in this slice

## Recommended UX

### App

Add a `Remote MCP Bridge` section or tab in `Bear MCP.app` with:

- bridge status: installed/running, installed/stopped, not installed, misconfigured
- host: editable but defaulted to `127.0.0.1`
- port: editable, validated, and kept stable once chosen
- endpoint preview: `http://127.0.0.1:<port>/mcp`
- primary actions:
  - `Install Bridge`
  - `Remove Bridge`
  - `Pause` and `Resume`
  - `Copy MCP URL`
  - `Copy Example Config`
- support text explaining that this is for apps that only support HTTP MCP connections

Recommended default behavior:

- default preferred port: choose one fixed preferred default in code
- if that port is unavailable during install, find the next free port once
- save the chosen port to config
- reuse the saved port on subsequent launches

Do not silently pick a different port every time the bridge restarts.

### CLI

Add a new CLI command family:

- `bear-mcp bridge`

Recommended subcommands:

- `bear-mcp bridge serve`
- `bear-mcp bridge status`
- `bear-mcp bridge print-url`

Optional later:

- `bear-mcp bridge install-launch-agent`
- `bear-mcp bridge remove-launch-agent`

For the first slice, app-driven LaunchAgent install/remove is enough. The important CLI behavior is that `serve` exists as the headless runtime entrypoint for the agent.

## Recommended Architecture

Keep the current structure and add the bridge in the same style as the public launcher support:

- `BearCore`: bridge config types, paths, LaunchAgent identifiers, port helpers, endpoint formatting
- `BearApplication`: install/remove/status orchestration, validation, diagnostics snapshot data, agent file generation
- `BearMCPCLI`: parse and run the new `bridge` command family
- `Bear MCP.app`: install/remove/copy/status UI

Do not add this to:

- `BearXCallback`
- the selected-note helper
- the main MCP tool surface

## Runtime Shape

The bridge runtime should look like this:

1. User enables `Remote MCP Bridge` from the app.
2. The app ensures the public launcher exists at `~/.local/bin/bear-mcp`.
3. The app saves bridge settings.
4. The app installs a per-user LaunchAgent that runs:
   - `~/.local/bin/bear-mcp bridge serve`
5. The bridge process starts a local HTTP MCP transport.
6. The bridge process creates the same internal `BearService` runtime used by `bear-mcp mcp`.
7. The app shows the stable URL to copy into other AI apps.

This keeps upgrades simpler because the LaunchAgent points at the stable launcher path instead of a specific app-bundle executable path.

## Native Bridge Strategy

Implement the bridge natively with the official Swift MCP SDK instead of bundling or invoking `mcp-proxy`.

Why:

- smaller beginner setup
- fewer moving parts
- better control over product scope
- easier status reporting and diagnostics in the app
- easier integration with your current launcher and config model

The repo now uses `swift-sdk` `0.12.0`. The first slice confirmed that the official Swift SDK server HTTP transports are workable here, and the current bridge runtime uses the stateless transport with a local SwiftNIO HTTP wrapper.

## Stateful vs Stateless

Choose the smallest HTTP transport that matches the clients you care about.

Preferred rule:

- if a stateless `/mcp` transport works well with target clients, prefer that because it keeps the bridge simpler
- if client compatibility requires session-aware streaming behavior, use the stateful transport

Keep the product promise stable for users:

- one localhost URL
- one Bear server behind it
- no extra ceremony

## Configuration Additions

Add a bridge section to config under `~/.config/bear-mcp/config.json`.

Suggested shape:

```json
{
  "bridge": {
    "enabled": false,
    "host": "127.0.0.1",
    "port": 6190
  }
}
```

Notes:

- `enabled` reflects intended product state, not just whether a process is running this second
- keep `host` defaulted to `127.0.0.1`
- `port` should be user-editable and persisted

Optional later fields:

- `launchAgentInstalled`
- `lastError`

Those can also be derived dynamically, so do not add them unless they meaningfully simplify the implementation.

## LaunchAgent Design

Install a per-user LaunchAgent plist under:

- `~/Library/LaunchAgents/<bundle-or-product-specific-id>.plist`

Suggested responsibilities:

- run the bridge in the background after login
- keep it alive if it exits unexpectedly
- use the stable public launcher path
- write stdout/stderr logs into the existing app support area

Suggested launch command shape:

```sh
~/.local/bin/bear-mcp bridge serve
```

Recommended plist traits:

- `RunAtLoad = true`
- `KeepAlive = true`
- a stable label owned by this app
- `StandardOutPath` and `StandardErrorPath` under `~/Library/Application Support/Bear MCP/Logs/`

The app should own:

- install
- uninstall
- load/reload
- unload
- status checks

Removal should cleanly unload the agent and remove the plist.

## Port Selection Rules

Use a deterministic port strategy:

1. Start with a fixed preferred default port defined in code.
2. If the config already has a port, use that exact port.
3. During first install, if the preferred port is busy, scan for the next free port in a small bounded range.
4. Save the selected port immediately.
5. Reuse that saved port until the user changes it.

Validation rules:

- reject privileged ports unless you explicitly want to support them
- reject malformed or out-of-range ports
- surface a clear UI error if the chosen saved port is unavailable and the bridge cannot bind

Do not silently move to a different port once the user has already installed the bridge and copied the URL elsewhere.

## Diagnostics and Status

Add bridge-specific status to the dashboard snapshot.

Useful states:

- bridge not configured
- bridge config saved but LaunchAgent missing
- LaunchAgent installed but not loaded
- LaunchAgent loaded but endpoint unreachable
- bridge healthy at `http://127.0.0.1:<port>/mcp`

Useful checks:

- launcher exists and is executable
- config is valid
- LaunchAgent plist exists and matches expected contents
- configured port is bindable or currently served by the expected process
- HTTP health probe succeeds

Keep receipts compact and user-facing. This should mirror the current launcher install/repair model.

## Suggested File Ownership

Likely new or changed areas:

- `Sources/BearCore/BearConfiguration.swift`
- `Sources/BearCore/BearPaths.swift`
- `Sources/BearApplication/BearAppSupport.swift`
- `Sources/BearApplication/BearRuntimeBootstrap.swift`
- `Sources/BearMCPCLI/BearCLICommand.swift`
- `Sources/BearMCPCLI/BearMCPMain.swift`
- `App/BearMCPApp/BearMCPAppModel.swift`
- `App/BearMCPApp/BearMCPDashboardView.swift`

Possible new files:

- `Sources/BearCore/BearBridgeModels.swift`
- `Sources/BearCore/BearLaunchAgentPaths.swift`
- `Sources/BearApplication/BearBridgeSupport.swift`
- `Sources/BearApplication/BearBridgeLaunchAgent.swift`
- `Sources/BearMCPCLI/BearBridgeCommand.swift`

Exact file names can vary, but the layer boundaries should stay clean.

## Implementation Phases

### Phase 0: Research and SDK Upgrade

Goal:

- confirm the native HTTP MCP transport approach and upgrade `swift-sdk` safely

Status:

- done

Tasks:

- inspect the current Swift MCP SDK transport APIs
- upgrade the pinned SDK version intentionally
- adjust compile errors if any
- run the baseline verification:
  - `swift test`
  - `CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh`

Exit criteria:

- repo builds cleanly on the newer SDK
- current stdio MCP flow still works

### Phase 1: Bridge Domain and Config

Goal:

- add configuration and path primitives without changing runtime behavior yet

Status:

- done

Tasks:

- add bridge config model with defaults
- add config migration/default-loading behavior
- add LaunchAgent path/label constants
- add URL formatting helpers
- add deterministic port-selection helper

Exit criteria:

- config reads and writes remain backward compatible
- no current behavior regresses

### Phase 2: CLI Bridge Runtime

Goal:

- create a headless bridge runtime callable as `bear-mcp bridge serve`

Status:

- done

Tasks:

- extend CLI argument parsing
- create a `serve` code path that builds the same internal Bear runtime used by `mcp`
- start the HTTP transport on the configured host/port
- add a small status-printing command
- add a URL-printing command

Exit criteria:

- `bear-mcp bridge serve` starts a local HTTP MCP endpoint
- `bear-mcp mcp` still behaves exactly as before
- direct utility commands still behave exactly as before

### Phase 3: LaunchAgent Management

Goal:

- let the app install and remove a background bridge cleanly

Status:

- done

Tasks:

- generate expected LaunchAgent plist contents
- write install/uninstall/reload helpers
- connect stdout/stderr logs into app support
- detect drift between expected and actual plist contents

Exit criteria:

- app can install the bridge agent
- app can remove the bridge agent
- reinstall/repair is idempotent

### Phase 4: App UI

Goal:

- make the bridge understandable and easy for beginners

Status:

- done for install/remove/pause/resume/status/copy actions
- host/port editing in the app UI is still open

Tasks:

- add `Remote MCP Bridge` UI
- show status, host, port, and endpoint
- add copy buttons
- add install/remove controls
- add validation and friendly errors

Exit criteria:

- a new user can enable the bridge and copy the URL without using Terminal

### Phase 5: Hardening

Goal:

- make failures predictable and visible

Status:

- in progress

Tasks:

- add health checks
- improve status messages
- verify port-collision behavior
- verify app upgrade path when launcher content changes
- verify LaunchAgent repair flow

Exit criteria:

- the feature is safe to recommend as a beginner-friendly setup path

## Testing Plan

Minimum automated coverage:

- config encoding/decoding with old configs still loading
- CLI parsing for `bridge` subcommands
- deterministic port-selection behavior
- LaunchAgent plist generation
- dashboard snapshot status mapping
- bridge URL formatting

Recommended integration checks:

- `bear-mcp bridge serve` binds to localhost on the configured port
- app installs the agent and can detect that it is installed
- public launcher updates do not break the agent command path
- existing `mcp`, `doctor`, `paths`, `--new-note`, `--apply-template`, `--archive-note`, and `--delete-note` flows still work

Manual verification checklist:

1. Fresh install with no bridge configured.
2. Enable bridge from the app.
3. Confirm launcher exists.
4. Confirm LaunchAgent exists and loads.
5. Copy the localhost URL from the app.
6. Connect from an HTTP-only MCP client.
7. Quit the dashboard app and confirm the bridge remains available.
8. Reopen the app and confirm status is still healthy.
9. Remove the bridge and confirm the agent is unloaded and deleted.

## Risk List

### SDK Upgrade Risk

Upgrading `swift-sdk` may require transport API and server setup adjustments beyond the bridge feature.

Mitigation:

- land the SDK upgrade cleanly first
- verify current MCP behavior before adding the bridge runtime

### Regression Risk To Existing CLI/MCP Behavior

This project already has a healthy separation between app shell, CLI runtime, and service layer. The bridge must preserve that.

Mitigation:

- keep `bridge` as an additive command family
- reuse the existing service construction path
- do not alter the existing stdio `mcp` path except where shared helpers are intentionally extracted

### LaunchAgent Drift Risk

Users may edit or remove the plist manually, or old launcher paths may become stale.

Mitigation:

- compare actual plist contents against expected contents
- provide clear repair actions in the app
- keep the LaunchAgent target on the stable public launcher path

### Port-Collision Risk

A configured port may later be taken by another app.

Mitigation:

- surface a clear health/state error
- let the user edit the port
- do not silently move to a new port after install

## Suggested Handoff Prompt For Another AI Thread

Use this document as the source of truth and implement the `Remote MCP Bridge` feature incrementally.

Constraints:

- preserve all existing MCP tools and current CLI behavior
- keep the feature optional
- implement it natively in Swift
- use `bear-mcp bridge` as the CLI family
- keep the LaunchAgent pointed at `~/.local/bin/bear-mcp`
- keep the bridge localhost-only by default
- keep the chosen port stable once selected
- do not mix this work with the future `Ursus` rename

Suggested next implementation slice:

1. add `BearApplication` support for bridge LaunchAgent install/remove/status using the stable public launcher path
2. generate and validate the expected plist contents for `~/Library/LaunchAgents/com.aft.bearmcp.bridge.plist`
3. wire stdout/stderr logs into `~/Library/Application Support/Bear MCP/Logs/`
4. expose bridge status/install/remove/copy actions in `Bear MCP.app`
5. clean up the `Tool.Content.text(...)` deprecation warnings in `Sources/BearMCP/BearMCPServer.swift`

## Final Guidance

The right mental model for this feature is:

- `bear-mcp mcp` remains the canonical stdio server
- `bear-mcp bridge serve` is a thin HTTP wrapper around the same Bear runtime
- `Bear MCP.app` is the installer, repair tool, and status surface

If a future implementation starts to look like a full proxy platform, it is going too far.
