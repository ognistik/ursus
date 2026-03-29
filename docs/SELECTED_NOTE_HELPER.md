# Selected Note Helper

This doc is intentionally short because the standalone helper is no longer a primary product surface.

## What It Is

Selected-note targeting now prefers the callback flow hosted by `Bear MCP.app`.

The standalone helper exists only as a compatibility fallback when that preferred app path is unavailable. Most contributors can ignore it unless they are working specifically on selected-note callback fallback behavior.

## Current Shape

- shared callback-host runtime lives in package code
- `Bear MCP.app` is the preferred callback host
- the standalone helper remains a thin shell around the shared callback-host logic
- the helper is background-only and on-demand

## Build The Standalone Fallback Helper

From the repo root:

```sh
Support/scripts/build-selected-note-helper-app.sh
```

For release mode:

```sh
CONFIGURATION=release Support/scripts/build-selected-note-helper-app.sh
```

## When To Care About It

Touch the standalone helper only when you are:

- fixing fallback selected-note resolution
- validating behavior when `Bear MCP.app` is unavailable
- keeping the old fallback path from regressing while app-hosted callback handling remains the preferred route

If you are working on normal app, CLI, MCP, template, or config flows, this helper is not the center of the product anymore.
