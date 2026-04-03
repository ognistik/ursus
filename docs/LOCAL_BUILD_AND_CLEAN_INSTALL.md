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

- Debug: `./.build/UrsusApp/Build/Products/Debug/Ursus.app`
- Release: `./.build/UrsusApp/Build/Products/Release/Ursus.app`
- App executable that also serves hidden CLI mode: `Contents/MacOS/Ursus`

The installed public launcher at `~/.local/bin/ursus` forwards into that app executable with a hidden `--ursus-cli` flag, so replacing `Ursus.app` updates bridge and Terminal launches together.
For compatibility with older already-installed launchers, the app bundle also includes a tiny forwarding shim at `Contents/Resources/bin/ursus`.

## Install The Built App

Example Debug install:

```sh
mkdir -p "$HOME/Applications"
ditto ".build/UrsusApp/Build/Products/Debug/Ursus.app" "$HOME/Applications/Ursus.app"
open "$HOME/Applications/Ursus.app"
```

Example Release install:

```sh
mkdir -p "$HOME/Applications"
ditto ".build/UrsusApp/Build/Products/Release/Ursus.app" "$HOME/Applications/Ursus.app"
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
- the selected-note token now lives in macOS Keychain under Ursus-managed storage, so a full reset should also clear that Keychain item if you want a completely clean local state

## Reinstall After Reset

One practical copy-paste flow:

```sh
CONFIGURATION=Debug Support/scripts/build-ursus-app.sh
mkdir -p "$HOME/Applications"
ditto ".build/UrsusApp/Build/Products/Debug/Ursus.app" "$HOME/Applications/Ursus.app"
open "$HOME/Applications/Ursus.app"
```

## Current Direct CLI Commands

The public launcher installed by the app is:

- `~/.local/bin/ursus`

Current utility commands:

- `ursus --new-note [--title TEXT] [--content TEXT] [--tags TAGS] [--replace-tags] [--open-note] [--new-window]`
- `ursus --backup-note [note-id-or-title ...]`
- `ursus --restore-note NOTE_ID SNAPSHOT_ID [NOTE_ID SNAPSHOT_ID ...]`
- `ursus --apply-template [note-id-or-title ...]`
- `ursus bridge serve`
- `ursus bridge status`
- `ursus bridge print-url`

Current selector behavior:

- `--new-note` with no extra flags preserves the current interactive editing-note flow
- explicit `--new-note` mode skips selected-note lookup, makes omitted `--tags` follow the create-adds-inbox-tags default, defaults to append semantics unless `--replace-tags` is passed, and leaves the note closed unless `--open-note` is present
- `--tags` accepts a comma-separated list and may be passed more than once
- `--new-window` requires `--open-note`
- `--apply-template` and `--backup-note` use the selected Bear note when no note ids or titles are passed
- `--restore-note` requires exact `NOTE_ID SNAPSHOT_ID` pairs
- passed note arguments resolve as exact note id first, then exact case-insensitive title
- quote titles with spaces
