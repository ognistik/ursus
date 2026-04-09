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

## App Icon Workflow

Apple's current supported path is to use an Icon Composer `.icon` file directly in Xcode as the app icon source. The intended workflow is:

- keep the Icon Composer source file outside `Assets.xcassets`
- keep the `.icon` file in the app target's synced project folder
- set the target's App Icon field to the filename without the `.icon` extension

Current repo status:

- `App/UrsusApp/AppIcon.icon` is the checked-in Icon Composer source of truth
- the `Ursus` target's App Icon setting points at `AppIcon`

### If You Edit The `.icon` File

This repo now uses the native Icon Composer workflow. After saving changes in Icon Composer, just rebuild:

```sh
CONFIGURATION=Debug Support/scripts/build-ursus-app.sh
```

If you edit the file in Xcode's Project navigator and keep the filename as `AppIcon.icon`, saving the document and rebuilding should be enough. The build should regenerate the native app icon payload automatically.

Current app build outputs:

- Debug: `./.build/UrsusApp/Build/Products/Debug/Ursus.app`
- Release: `./.build/UrsusApp/Build/Products/Release/Ursus.app`
- App executable that also serves hidden CLI mode: `Contents/MacOS/Ursus`

The installed public launcher at `~/.local/bin/ursus` forwards into that app executable with a hidden `--ursus-cli` flag, so replacing `Ursus.app` updates bridge and Terminal launches together.

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

## Bridge URL Notes

- The HTTP bridge serves MCP at the configured endpoint path, which defaults to `/mcp`.
- Local probes can use `http://127.0.0.1:6190/mcp` unless the saved port was changed.
- When exposing the bridge through a personal tunnel, the remote connector URL should still include the MCP path, for example `https://your-domain.example/mcp`.
- The bare bridge origin such as `https://your-domain.example/` is not itself the MCP endpoint.

Current selector behavior:

- `--new-note` with no extra flags preserves the current interactive editing-note flow
- explicit `--new-note` mode skips selected-note lookup, makes omitted `--tags` follow the create-adds-inbox-tags default, defaults to append semantics unless `--replace-tags` is passed, and leaves the note closed unless `--open-note` is present
- `--tags` accepts a comma-separated list and may be passed more than once
- `--new-window` requires `--open-note`
- `--apply-template` and `--backup-note` use the selected Bear note when no note ids or titles are passed
- `--restore-note` requires exact `NOTE_ID SNAPSHOT_ID` pairs
- passed note arguments resolve as exact note id first, then exact case-insensitive title
- quote titles with spaces

## Testing Bridge OAuth Flow
- Register a temporary public client:

```
curl -s http://127.0.0.1:6190/oauth/register \
  -H 'Content-Type: application/json' \
  -d '{"redirect_uris":["https://example.com/callback"],"client_name":"OAuth UI Preview7","token_endpoint_auth_method":"none"}'

```

- Copy the returned client_id.
- Generate a PKCE challenge:

```
VERIFIER='preview-verifier-abcdefghijklmnopqrstuvwxyz-0123456789'
CHALLENGE=$(python3 - <<'PY'
import base64, hashlib
v = b"preview-verifier-abcdefghijklmnopqrstuvwxyz-0123456789"
print(base64.urlsafe_b64encode(hashlib.sha256(v).digest()).rstrip(b"=").decode())
PY
)
echo "$CHALLENGE"
```

- Open the consent page in your browser:

```
open "http://127.0.0.1:6190/oauth/authorize?response_type=code&client_id=PASTE_CLIENT_ID_HERE&redirect_uri=https://example.com/callback&state=preview-state&resource=http://127.0.0.1:6190/mcp&scope=mcp&code_challenge=$CHALLENGE&code_challenge_method=S256"
```

- To trigger the error page directly:
```
curl -s -X POST http://127.0.0.1:6190/oauth/decision > /tmp/ursus-oauth-error.html
open /tmp/ursus-oauth-error.html
```