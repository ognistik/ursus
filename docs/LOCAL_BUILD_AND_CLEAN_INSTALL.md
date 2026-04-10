# Local Build And Clean Install

This document is the practical local build, install, and reset guide for the current app-centered setup.

---
## Daily Development Loop

For normal feature work and bug fixes, use a Debug app build:

```sh
CONFIGURATION=Debug Support/scripts/build-ursus-app.sh
```

If you want to install that Debug build locally:

```sh
mkdir -p "$HOME/Applications"
ditto ".build/UrsusApp/Build/Products/Debug/Ursus.app" "$HOME/Applications/Ursus.app"
open "$HOME/Applications/Ursus.app"
```

Useful local checks:

```sh
swift test
swift run ursus doctor
swift run ursus --help
```

---
## Release Checklist

Use this when you are ready to ship a public release.

1. Bump the app version and build number in Xcode.

Set `MARKETING_VERSION` to the release version, for example `0.2.2`.
Set `CURRENT_PROJECT_VERSION` to the next integer build number, for example `3`.

If the MCP server behavior changed, also bump:

```text
Sources/BearMCP/UrsusMCPServer.swift
```

2. Build, Developer ID sign, notarize, and create the DMG.

Keep your signing values in a local ignored `.release.env` file. That file should exist on your machine, but it should not be committed.

Example `.release.env` shape:

```sh
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export DEVELOPER_ID_PROVISIONING_PROFILE="/path/to/Ursus_Developer_ID.provisionprofile"
export NOTARYTOOL_PROFILE="notarytool-profile"
```

Then copy-paste this exact release build block:

```sh
rm -rf .build/UrsusApp .build/release .build/debug
CONFIGURATION=Release Support/scripts/build-ursus-app.sh

. ./.release.env
Support/scripts/sign-and-notarize-release.sh
```

The script outputs one final DMG filename in `.build/release-artifacts`:

- `Ursus.0.2.2.dmg`: the GitHub/Sparkle upload file

Release builds are intended to support both Apple Silicon and Intel Macs on macOS 14 or later. The build and signing scripts fail if the app executable or embedded helper are missing either `arm64` or `x86_64`, but you can also inspect them directly:

```sh
lipo -archs ".build/UrsusApp/Build/Products/Release/Ursus.app/Contents/MacOS/Ursus"
lipo -archs ".build/UrsusApp/Build/Products/Release/Ursus.app/Contents/Library/Helpers/Ursus Helper.app/Contents/MacOS/ursus-helper"
```

Both commands should print:

```text
x86_64 arm64
```

Upload that dotted DMG to the GitHub Release, and write the release notes in the GitHub Release body.

3. Generate the Sparkle appcast entry.

Do not run Sparkle's raw `generate_appcast` over the whole `release-artifacts` folder. Use the helper script and point it at the exact dotted DMG you uploaded:

```sh
Support/scripts/generate-sparkle-appcast.sh \
  --archive "$PWD/.build/release-artifacts/Ursus.0.2.2.dmg" \
  --tag v0.2.2
```

This fetches the release notes from the GitHub Release body with `gh` and updates `docs/appcast.xml`. To override that body locally, pass `--release-notes "$PWD/.build/release-artifacts/Ursus.0.2.2.md"` or place a same-stem `.md`, `.html`, or `.txt` file beside the dotted DMG.

For a universal DMG, the new appcast item should keep `sparkle:minimumSystemVersion` at `14.0` and should not include `<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>` for the new release. Do not edit older appcast entries to widen hardware support unless the already-uploaded asset for that entry is replaced with a universal build.

4. Commit and push the release changes.

At minimum, this should include the version bump and the updated `docs/appcast.xml`. After GitHub Pages publishes the new appcast, Sparkle should see the update.

---
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
- App executable with the hidden embedded CLI mode: `Contents/MacOS/Ursus`

The installed public launcher at `~/.local/bin/ursus` invokes the app executable with the hidden `--ursus-cli` flag, so replacing `Ursus.app` still updates bridge and Terminal launches together.

If the bridge process ever gets stuck relaunching, use one of these recovery commands:

```sh
~/.local/bin/ursus bridge pause
~/.local/bin/ursus bridge resume
~/.local/bin/ursus bridge remove
```

---
## Current Runtime Paths

These are the current paths in code today:

- config root: `~/Library/Application Support/Ursus`
- config file: `~/Library/Application Support/Ursus/config.json`
- template: `~/Library/Application Support/Ursus/template.md`
- app support root: `~/Library/Application Support/Ursus`
- backups: `~/Library/Application Support/Ursus/Backups`
- runtime lock: `~/Library/Application Support/Ursus/Runtime/.server.lock`
- runtime-state SQLite: `~/Library/Application Support/Ursus/Runtime/runtime-state.sqlite`
- debug log: `~/Library/Application Support/Ursus/Logs/debug.log`
- public launcher: `~/.local/bin/ursus`
- temp fallback locks: `TMPDIR/ursus/Runtime/...`

---
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

---
## Debug Donation Prompt Testing

The donation prompt state is stored locally per machine in:

```sh
$HOME/Library/Application\ Support/Ursus/Runtime/runtime-state.sqlite
```

Debug builds now accept hidden donation-testing CLI flags. They are intentionally not shown in normal CLI help:

- `ursus --debug-donation-trigger`
- `ursus --debug-donation-reset`
- `ursus --debug-donation-status`

Release builds do not include these commands.

### Manual Reset / Re-Test

If you want to retest from zero without using the hidden Debug command:

```sh
pkill -f "/Ursus.app/Contents/MacOS/Ursus" 2>/dev/null || true
rm -f "$HOME/Library/Application Support/Ursus/Runtime/runtime-state.sqlite"
open "$HOME/Applications/Ursus.app"
```

If you want to inspect the current donation state directly:

```sh
sqlite3 "$HOME/Library/Application Support/Ursus/Runtime/runtime-state.sqlite" \
  'select total_successful_operation_count, next_prompt_operation_count, permanent_suppression_reason from donation_prompt_state;'
```

If you prefer the hidden CLI summary instead:

```sh
ursus --debug-donation-status
```

---
## Release Reference

The checklist at the top is the normal release path. These are the key rules behind it:

- `Support/scripts/sign-and-notarize-release.sh` creates the signed/notarized release artifacts under `.build/release-artifacts`.
- `CONFIGURATION=Release Support/scripts/build-ursus-app.sh` builds the app through Xcode's generic macOS destination so the main app executable is universal.
- `Support/scripts/build-ursus-helper-app.sh` builds separate `arm64` and `x86_64` helper slices for Release and merges them with `lipo` before embedding.
- The script embeds the Developer ID provisioning profile required by the Bear token keychain access group.
- The dotted DMG, for example `Ursus.0.2.2.dmg`, is the one to upload to GitHub and pass to Sparkle appcast generation.
- `Support/scripts/generate-sparkle-appcast.sh` updates `docs/appcast.xml` from one exact archive path, so the `.app` folder in `.build/release-artifacts` does not matter.
- The appcast helper prefers explicitly passed release notes, then same-stem local notes beside the archive, then the GitHub Release body for the passed tag.
- The appcast helper uses temporary staging under `.build/sparkle-appcast/work` while it runs, then cleans that staging folder before it exits.
- Do not edit or re-upload the DMG after generating `docs/appcast.xml`; Sparkle validates the exact bytes from the appcast signature.
- The published feed URL is `https://ognistik.github.io/ursus/appcast.xml`.

One-time Sparkle setup, only needed on a new release-signing Mac:

```sh
SPARKLE_BIN="$PWD/.build/UrsusApp/SourcePackages/artifacts/sparkle/Sparkle/bin"
"$SPARKLE_BIN/generate_keys"
```

`generate_keys` stores the private key in your login Keychain and prints the public key that must match `SUPublicEDKey` in `Support/app/Info.plist`.

---
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

---
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

---
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

---
## Testing Sparkle Update Checks

The simplest test reset is to clear Sparkle’s stored `SULastCheckTime`.

Use:
```
defaults delete com.aft.ursus SULastCheckTime
```

You can inspect it first:
```
defaults read com.aft.ursus SULastCheckTime
```
