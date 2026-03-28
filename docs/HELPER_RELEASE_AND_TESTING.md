# Bear MCP Helper Release And Testing

This file is a practical checklist for local testing now and release prep later.

Phase 3 now prefers `Bear MCP.app` as the selected-note callback host, and that app-hosted route has been manually validated end-to-end against the real Bear app for both app-launch and already-running-app flows. The canonical app install target is `/Applications/Bear MCP.app`; `~/Applications/Bear MCP.app` remains a fully supported user-specific install location. The helper app remains available only as a narrow fallback when `Bear MCP.app` is not installed. Its runtime behavior still lives in shared package code.

## Local build outputs

`swift build` in the repo builds the helper executable target too, but it does not create a macOS app bundle by itself.

Useful commands:

```sh
swift build --product bear-mcp-helper
```

That produces the raw executable at:

```text
.build/debug/bear-mcp-helper
```

To build the actual app bundle that registers the callback scheme:

```sh
Support/scripts/build-selected-note-helper-app.sh
```

For release mode:

```sh
CONFIGURATION=release Support/scripts/build-selected-note-helper-app.sh
```

## Local install for testing

Recommended local test path for the standalone helper only:

1. Build the app bundle with `Support/scripts/build-selected-note-helper-app.sh`.
2. Move or copy `.build/debug/Bear MCP Helper.app` into `/Applications`. If needed, `~/Applications` is also fully supported for user-specific installs.
3. Launch it once manually with Finder or `open "/Applications/Bear MCP Helper.app"` so Launch Services registers the callback scheme cleanly.
4. Put your Bear API token in `~/.config/bear-mcp/config.json`.
5. Run `swift run bear-mcp doctor` and confirm the helper shows as detected and valid.

For the preferred path, install `Bear MCP.app` in `/Applications/Bear MCP.app` and verify selected-note MCP calls with the app both closed and already open in dashboard mode. If a user cannot install there, `~/Applications/Bear MCP.app` is also fully supported as a user-specific install path.

## Manual behavior checks

Before testing MCP end-to-end:

1. Put a valid Bear API token in config.
2. Select a note in Bear.
3. Run a selected-note tool flow through the MCP server.
4. Confirm the resolved note matches the currently selected Bear note.
5. Confirm no browser window opens and the helper stays background-only.

Good local scenarios to test:

- `selected: true` on `bear_open_notes`
- `selected: true` on `bear_insert_text`
- `selected: true` on `bear_replace_content`
- no selected note in Bear
- invalid token
- invalid helper path
- helper app not installed
- callback timeout

## Release recommendation

My recommendation is:

- ship `bear-mcp` as the main Homebrew formula
- ship `Bear MCP Helper.app` as a separate signed release asset first
- keep the helper install location simple: prefer `/Applications`, but continue fully supporting `~/Applications` for user-specific installs
- later, consider a dedicated Homebrew cask for `Bear MCP Helper`

That keeps the release simple while you preserve a narrow compatibility fallback. It should be treated as a transition release strategy until the helper can be retired completely.

## Why not fully automate install yet

The helper is an app bundle with a callback URL scheme, so macOS app placement and registration matter more than for a plain CLI binary. Asking early users to place it in `/Applications`, while still fully supporting `~/Applications` for user-specific installs, is a reasonable first-release tradeoff.

Once the release flow feels stable, you can decide between:

- separate Homebrew cask for `Bear MCP Helper`
- helper auto-detection in standard app locations
- bundling/installing the helper from the main distribution flow

## Signing and notarization later

When you are ready to release broadly, the next layer is:

1. Sign `Bear MCP Helper.app` with your Developer ID Application certificate.
2. Notarize the app.
3. Staple the notarization ticket.
4. Publish the app as a release asset.
5. Document the expected install location and config path.

I would do that only after a few days of local validation.
