# Local Build And Clean Install

This document is the practical local build, install, and reset guide for the current app-centered setup.

## Build

From the repo root:

```sh
CONFIGURATION=Debug Support/scripts/build-ursus-app.sh
```

For a Release build:

```sh
CONFIGURATION=Release Support/scripts/build-ursus-app.sh
```

Useful verification:

```sh
swift test
swift run ursus doctor
swift run ursus --help
```

Current app build outputs:

- Debug: `./.build/BearMCPApp/Build/Products/Debug/Ursus.app`
- Release: `./.build/BearMCPApp/Build/Products/Release/Ursus.app`

## Install The Built App

Example Debug install:

```sh
mkdir -p "$HOME/Applications"
ditto ".build/BearMCPApp/Build/Products/Debug/Ursus.app" "$HOME/Applications/Ursus.app"
open "$HOME/Applications/Ursus.app"
```

Example Release install:

```sh
mkdir -p "$HOME/Applications"
ditto ".build/BearMCPApp/Build/Products/Release/Ursus.app" "$HOME/Applications/Ursus.app"
open "$HOME/Applications/Ursus.app"
```

Canonical install guidance now prefers `/Applications/Ursus.app`, but `~/Applications/Ursus.app` remains fully supported for local development and user-specific installs.

## Current Runtime Paths

These are the current paths in code today:

- config root: `~/Library/Application Support/Ursus`
- config file: `~/Library/Application Support/Ursus/config.json`
- template: `~/Library/Application Support/Ursus/template.md`
- app support root: `~/Library/Application Support/Ursus`
- backups: `~/Library/Application Support/Ursus/Backups`
- runtime lock: `~/Library/Application Support/Ursus/Runtime/.server.lock`
- debug log: `~/Library/Application Support/Ursus/Logs/debug.log`
- public launcher: `~/.local/bin/ursus`
- temp fallback locks: `TMPDIR/ursus/Runtime/...`

## Clean Reset

Use this when you want to test from a clean local starting point.

```sh
pkill -f "/Ursus.app/Contents/MacOS/Ursus" 2>/dev/null || true
rm -rf "/Applications/Ursus.app"
rm -rf "$HOME/Applications/Ursus.app"
rm -rf "$HOME/Library/Application Support/Ursus"
rm -f "$HOME/Library/LaunchAgents/com.aft.ursus.plist"
rm -f "$HOME/.local/bin/ursus"
```

Note:

- deleting the app bundle alone does not remove Ursus state
- the selected-note token is currently managed through Ursus's config flow, so there is no separate Keychain reset step in the current product shape

## Optional Prerelease Cleanup

If you are resetting a machine that previously ran the prerelease identity, it is acceptable to remove those old artifacts manually before verifying the current Ursus build:

```sh
rm -rf "/Applications/Bear MCP.app"
rm -rf "$HOME/Applications/Bear MCP.app"
rm -rf "$HOME/Library/Application Support/Bear MCP"
rm -rf "$HOME/Library/Application Support/bear-mcp"
rm -rf "$HOME/Library/Logs/bear-mcp"
rm -f "$HOME/Library/LaunchAgents/com.aft.bear-mcp.plist"
rm -f "$HOME/.local/bin/bear-mcp"
```

This is a manual cleanup aid only, not a supported migration path.

## Reinstall After Reset

One practical copy-paste flow:

```sh
CONFIGURATION=Debug Support/scripts/build-ursus-app.sh
mkdir -p "$HOME/Applications"
ditto ".build/BearMCPApp/Build/Products/Debug/Ursus.app" "$HOME/Applications/Ursus.app"
open "$HOME/Applications/Ursus.app"
```

## Current Direct CLI Commands

The public launcher installed by the app is:

- `~/.local/bin/ursus`

Current utility commands:

- `ursus --new-note [--title TEXT] [--content TEXT] [--tags TAGS] [--tag-merge-mode append|replace] [--open-note yes|no] [--new-window yes|no]`
- `ursus --apply-template [note-id-or-title ...]`
- `ursus --archive-note [note-id-or-title ...]`
- `ursus --delete-note [note-id-or-title ...]`

Current selector behavior:

- `--new-note` with no extra flags preserves the current interactive editing-note flow
- explicit `--new-note` mode skips selected-note lookup, defaults omitted `--tags` to configured inbox tags, and defaults `--tag-merge-mode` to `append`
- `--tags` accepts a comma-separated list and may be passed more than once
- `--apply-template`, `--archive-note`, and `--delete-note` use the selected Bear note when no note ids or titles are passed
- passed note arguments resolve as exact note id first, then exact case-insensitive title
- quote titles with spaces
