# Bear MCP Helper

`bear-mcp` keeps selected-note targeting optional.

The main CLI server remains the primary product. Advanced users who want `selected: true` can install a small companion helper app in `/Applications` or `~/Applications`.

This helper is now a transition host for shared callback logic, not the long-term product center. The callback runtime itself lives in package code so a future unified `Bear MCP.app` can reuse the same contract.

## Why this exists

Bear's selected-note callback flow depends on a callback URL target. A real `.app` bundle is the most reliable way to register and receive that callback scheme on macOS.

This repo now includes:

- shared callback-host runtime in `BearXCallback`
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

Install `Bear MCP Helper.app` in `/Applications` or `~/Applications`, then run `bear-mcp doctor` to confirm it was detected.

## Current behavior

- The helper accepts an xcall-compatible CLI shape: `-url ... -activateApp YES|NO`
- The standalone executable is a thin AppKit shell around shared `BearSelectedNoteCallbackHost` logic in `BearXCallback`
- It injects its own success/error callback URLs
- It prints callback payload JSON to `stdout` on success and `stderr` on error
- It exits after the callback arrives, or after a short timeout
- The bundled app is background-only and intentionally has no UI

## Packaging later

The current repo builds the helper app locally, but does not yet produce a signed/notarized release artifact automatically. That can be layered on later without changing the CLI-side config or callback contract, and the same callback-host runtime is intended to move into the future unified app bundle.
