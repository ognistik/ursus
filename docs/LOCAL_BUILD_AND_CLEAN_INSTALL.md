# Local Build And Clean Install

This document is for local development and for testing the app from a clean starting point on macOS.

## Build Commands

Build a local Debug app bundle:

```sh
cd /Users/ognistik/Documents/GitHubRepos/bear-mcp
CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh
```

Build a local Release app bundle:

```sh
cd /Users/ognistik/Documents/GitHubRepos/bear-mcp
CONFIGURATION=Release Support/scripts/build-bear-mcp-app.sh
```

The build script prints the final app path on success.

Current output paths:

- Debug app: `/Users/ognistik/Documents/GitHubRepos/bear-mcp/.build/BearMCPApp/Build/Products/Debug/Bear MCP.app`
- Release app: `/Users/ognistik/Documents/GitHubRepos/bear-mcp/.build/BearMCPApp/Build/Products/Release/Bear MCP.app`

Optional verification commands:

```sh
cd /Users/ognistik/Documents/GitHubRepos/bear-mcp
swift test
swift run bear-mcp doctor
```

## Install The Built App

Copy the Debug build into `~/Applications`:

```sh
mkdir -p "$HOME/Applications"
ditto "/Users/ognistik/Documents/GitHubRepos/bear-mcp/.build/BearMCPApp/Build/Products/Debug/Bear MCP.app" "$HOME/Applications/Bear MCP.app"
```

Copy the Release build into `~/Applications`:

```sh
mkdir -p "$HOME/Applications"
ditto "/Users/ognistik/Documents/GitHubRepos/bear-mcp/.build/BearMCPApp/Build/Products/Release/Bear MCP.app" "$HOME/Applications/Bear MCP.app"
```

Open the installed app:

```sh
open "$HOME/Applications/Bear MCP.app"
```

## Clean Install Reset

If you want to test onboarding from the beginning, remove the app, config, app-managed runtime files, terminal command, and the Bear token stored in Keychain.

Important:

- deleting the app bundle alone does **not** remove the Bear token from Keychain
- the current Keychain item is:
  - service: `com.ognistik.bear-mcp`
  - account: `selected-note-token`

Fully reset the local Bear MCP state:

```sh
pkill -f "/Bear MCP.app/Contents/MacOS/Bear MCP" 2>/dev/null || true
rm -rf "/Applications/Bear MCP.app"
rm -rf "$HOME/Applications/Bear MCP.app"
rm -rf "$HOME/.config/bear-mcp"
rm -rf "$HOME/Library/Application Support/bear-mcp"
rm -rf "$HOME/Library/Logs/bear-mcp"
rm -f "$HOME/bin/bear-mcp"
security delete-generic-password -s "com.ognistik.bear-mcp" -a "selected-note-token" 2>/dev/null || true
```

After that, launching the app should behave like a fresh install.

## Reinstall After A Clean Reset

One practical copy-paste flow for a fresh local test:

```sh
cd /Users/ognistik/Documents/GitHubRepos/bear-mcp
CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh
mkdir -p "$HOME/Applications"
ditto ".build/BearMCPApp/Build/Products/Debug/Bear MCP.app" "$HOME/Applications/Bear MCP.app"
open "$HOME/Applications/Bear MCP.app"
```

## Notes About The CLI

The app can currently install:

- an app-managed CLI at `~/Library/Application Support/bear-mcp/bin/bear-mcp`
- a terminal command at `~/bin/bear-mcp`

If you are testing from a clean start, remove both the Application Support directory and `~/bin/bear-mcp`.

## Notes About `--update-config`

`bear-mcp --update-config` still exists as a compatibility helper right now.

Planned direction:

- keep it only until the app provides a fully easy path for config migration and CLI refresh/update flows
- remove it afterward rather than keeping dead compatibility code around
