# Bear MCP Helper Fallback

`bear-mcp` keeps selected-note targeting optional.

The main CLI server remains the primary MCP runtime. Phase 3 now prefers `Bear MCP.app` as the selected-note callback host through `bearmcp://`, and that app-hosted route has been manually validated end-to-end against the real Bear app for both app-launch and already-running-app flows. The companion helper app can still be installed in `/Applications` or `~/Applications` as a narrow legacy fallback when `Bear MCP.app` is not installed.

This helper is a transition host for shared callback logic, not the long-term product center. The callback runtime itself lives in package code and is now used by both the main app and the helper shell.

## Why this exists

Bear's selected-note callback flow depends on a callback URL target. A real `.app` bundle is the most reliable way to register and receive that callback scheme on macOS.

This repo now includes:

- shared callback-host runtime in `BearXCallback`
- a native `Bear MCP.app` bundle that registers `bearmcp://` and can run headless as the preferred callback host
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

Add your Bear API token to `~/.config/bear-mcp/config.json`:

```json
{
  "token": "YOUR_BEAR_TOKEN"
}
```

Install `Bear MCP.app` in `/Applications` or `~/Applications` for the preferred path. MCP clients should continue pointing at the `bear-mcp` CLI binary, not at the app executable. Install `Bear MCP Helper.app` only if you want to keep the legacy fallback available when the preferred app is absent. Then run `bear-mcp doctor` to confirm the callback host detection state.

## Current behavior

- `Bear MCP.app` is now the preferred callback host and preserves the same response-file JSON contract the CLI already used with the helper
- the preferred app-hosted route works end-to-end when `Bear MCP.app` is installed and not already running
- if `Bear MCP.app` is already open in dashboard mode, the CLI now reuses that running app instance through a `bearmcp://x-callback-url/start-selected-note-host?...` request instead of falling back to the helper
- the helper is now only needed as a legacy compatibility path when `Bear MCP.app` is not installed
- The helper accepts an xcall-compatible CLI shape: `-url ... -activateApp YES|NO`
- The standalone executable is a thin AppKit shell around shared `BearSelectedNoteCallbackHost` logic in `BearXCallback`
- It injects its own success/error callback URLs
- It prints callback payload JSON to `stdout` on success and `stderr` on error
- It exits after the callback arrives, or after a short timeout
- The bundled app is background-only and intentionally has no UI

## Packaging later

The current repo still builds the helper app locally, but it does not yet produce signed/notarized release artifacts automatically. That can be layered on later without changing the CLI-side config or callback contract while the legacy fallback remains available.
