# Local Build And Clean Install

This document is the practical local build, install, and reset guide for the current app-centered setup.

## Build

From the repo root:

```sh
cd /Users/ognistik/Documents/GitHubRepos/bear-mcp
CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh
```

For a Release build:

```sh
cd /Users/ognistik/Documents/GitHubRepos/bear-mcp
CONFIGURATION=Release Support/scripts/build-bear-mcp-app.sh
```

Useful verification:

```sh
cd /Users/ognistik/Documents/GitHubRepos/bear-mcp
swift test
swift run bear-mcp doctor
swift run bear-mcp --help
```

Current app build outputs:

- Debug: `/Users/ognistik/Documents/GitHubRepos/bear-mcp/.build/BearMCPApp/Build/Products/Debug/Bear MCP.app`
- Release: `/Users/ognistik/Documents/GitHubRepos/bear-mcp/.build/BearMCPApp/Build/Products/Release/Bear MCP.app`

## Install The Built App

Example Debug install:

```sh
mkdir -p "$HOME/Applications"
ditto "/Users/ognistik/Documents/GitHubRepos/bear-mcp/.build/BearMCPApp/Build/Products/Debug/Bear MCP.app" "$HOME/Applications/Bear MCP.app"
open "$HOME/Applications/Bear MCP.app"
```

Example Release install:

```sh
mkdir -p "$HOME/Applications"
ditto "/Users/ognistik/Documents/GitHubRepos/bear-mcp/.build/BearMCPApp/Build/Products/Release/Bear MCP.app" "$HOME/Applications/Bear MCP.app"
open "$HOME/Applications/Bear MCP.app"
```

Canonical install guidance still prefers `/Applications/Bear MCP.app`, but `~/Applications/Bear MCP.app` remains fully supported for local development and user-specific installs.

## Current Runtime Paths

These are the current paths in code today:

- config root: `~/.config/bear-mcp`
- config file: `~/.config/bear-mcp/config.json`
- template: `~/.config/bear-mcp/template.md`
- app support root: `~/Library/Application Support/Bear MCP`
- backups: `~/Library/Application Support/Bear MCP/Backups`
- runtime lock: `~/Library/Application Support/Bear MCP/Runtime/.server.lock`
- debug log: `~/Library/Application Support/Bear MCP/Logs/debug.log`
- public launcher: `~/.local/bin/bear-mcp`
- temp fallback locks: `TMPDIR/bear-mcp/Runtime/...`

Migration note:

- config stays under `~/.config/bear-mcp`
- startup migrates legacy runtime state from `~/Library/Application Support/bear-mcp`
- startup migrates legacy debug logs from `~/Library/Logs/bear-mcp`

## Clean Reset

Use this when you want to test from a clean local starting point.

```sh
pkill -f "/Bear MCP.app/Contents/MacOS/Bear MCP" 2>/dev/null || true
rm -rf "/Applications/Bear MCP.app"
rm -rf "$HOME/Applications/Bear MCP.app"
rm -rf "$HOME/.config/bear-mcp"
rm -rf "$HOME/Library/Application Support/Bear MCP"
rm -rf "$HOME/Library/Application Support/bear-mcp"
rm -rf "$HOME/Library/Logs/bear-mcp"
rm -f "$HOME/.local/bin/bear-mcp"
```

Note:

- deleting the app bundle alone does not remove Bear MCP state
- the selected-note token is currently managed through Bear MCP's config flow, so there is no separate Keychain reset step in the current product shape

## Reinstall After Reset

One practical copy-paste flow:

```sh
cd /Users/ognistik/Documents/GitHubRepos/bear-mcp
CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh
mkdir -p "$HOME/Applications"
ditto ".build/BearMCPApp/Build/Products/Debug/Bear MCP.app" "$HOME/Applications/Bear MCP.app"
open "$HOME/Applications/Bear MCP.app"
```

## Current Direct CLI Commands

The public launcher installed by the app is:

- `~/.local/bin/bear-mcp`

Current utility commands:

- `bear-mcp --new-note`
- `bear-mcp --apply-template [note-id-or-title ...]`
- `bear-mcp --delete-note [note-id-or-title ...]`

Current selector behavior:

- `--apply-template` and `--delete-note` use the selected Bear note when no note ids or titles are passed
- passed note arguments resolve as exact note id first, then exact case-insensitive title
- quote titles with spaces

Planned next additions:

- `bear-mcp --archive-note [note-id-or-title ...]`
- richer override flags for `bear-mcp --new-note`
