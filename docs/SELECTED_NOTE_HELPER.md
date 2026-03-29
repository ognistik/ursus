# Bear MCP Helper

`bear-mcp` keeps selected-note targeting optional.

The main CLI server remains the primary MCP runtime. The selected-note callback path now prefers a background helper app bundled inside `Bear MCP.app`, so one visible app install can still launch an on-demand callback receiver without stealing focus. The canonical install path for `Bear MCP.app` is `/Applications/Bear MCP.app`; `~/Applications/Bear MCP.app` remains a fully supported user-specific install location. The companion standalone helper app remains available only as a compatibility fallback when the embedded helper is unavailable.

This helper is not meant to run all the time. It is an on-demand background callback host. The callback runtime itself lives in package code and is used by both the app shell and the helper shell.

## Why this exists

Bear's selected-note callback flow depends on a callback URL target. A real `.app` bundle is the most reliable way to register and receive that callback scheme on macOS.

This repo now includes:

- shared callback-host runtime in `BearXCallback`
- a native `Bear MCP.app` bundle that contains the visible dashboard app plus the embedded background helper
- a SwiftPM helper executable product: `bear-mcp-helper`
- a bundling script that wraps that executable in a background `.app`
- an app `Info.plist` that registers the `bearmcphelper://` callback scheme

## Build the helper app

From the repo root:

```sh
Support/scripts/build-selected-note-helper-app.sh
```

That prints the built app path, typically:

```text
.build/debug/Bear MCP Helper.app
```

For a release build:

```sh
CONFIGURATION=release Support/scripts/build-selected-note-helper-app.sh
```

## Configure bear-mcp

Install `Bear MCP.app` in `/Applications/Bear MCP.app` for the preferred path. `~/Applications/Bear MCP.app` is also fully supported for user-specific installs, but it should not be treated as the default recommendation in docs or packaging.

Use `Bear MCP.app` to manage the Bear API token in Keychain and to install or repair the public launcher at:

```text
~/.local/bin/bear-mcp
```

MCP clients should point at that launcher path, not at the app executable and not at transient SwiftPM build outputs. Install `Bear MCP Helper.app` separately only if you want to keep the standalone compatibility fallback available when the embedded helper is absent. Then run `bear-mcp doctor` to confirm the callback host detection state.

## Current behavior

- `Bear MCP.app` now ships one embedded background helper that preserves the same response-file JSON contract the CLI already used with the standalone helper
- the local app build now embeds the `bear-mcp` binary inside `Bear MCP.app`, and the dashboard can install one shared launcher at `~/.local/bin/bear-mcp` that forwards into that bundled binary
- `/Applications/Bear MCP.app` is the canonical preferred install path; `~/Applications/Bear MCP.app` remains fully supported for user-specific installs
- the preferred route now launches the embedded helper on demand and keeps the visible dashboard app out of the callback critical path
- the helper exits after the callback arrives, so it does not need to run continuously in the background
- the standalone helper is now only a secondary compatibility fallback when the embedded helper is unavailable
- The helper accepts an xcall-compatible CLI shape: `-url ... -activateApp YES|NO`
- The standalone executable is a thin AppKit shell around shared `BearSelectedNoteCallbackHost` logic in `BearXCallback`
- It injects its own success/error callback URLs
- It prints callback payload JSON to `stdout` on success and `stderr` on error
- It exits after the callback arrives, or after a short timeout
- The bundled app is background-only and intentionally has no UI

## Packaging later

The current repo still builds the helper app locally, but it does not yet produce signed/notarized release artifacts automatically. That can be layered on later without changing the CLI-side config or callback contract while the standalone helper fallback remains available.
