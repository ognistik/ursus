# Selected Note Helper

This doc is intentionally short because the selected-note helper is an internal implementation detail, not a primary product surface.

## What It Is

Selected-note targeting uses the helper app bundled inside `Ursus.app`.

Most contributors can ignore it unless they are working specifically on selected-note callback behavior.

## Current Shape

- shared callback-host runtime lives in package code
- `Ursus.app` is the container for the embedded helper
- the helper bundle is shipped as `Ursus Helper.app` with the `ursushelper://` callback scheme
- the embedded helper remains a thin shell around the shared callback-host logic
- the helper is background-only and on-demand

## Build The Helper Bundle

From the repo root:

```sh
Support/scripts/build-ursus-helper-app.sh
```

For release mode:

```sh
CONFIGURATION=Release Support/scripts/build-ursus-helper-app.sh
```

## When To Care About It

Touch the helper only when you are:

- fixing embedded selected-note resolution
- validating the helper bundle embedded in `Ursus.app`
- working on the shared callback-host logic used by the helper

If you are working on normal app, CLI, MCP, template, or config flows, this helper is not the center of the product.
