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

For a totally clean Release build:
```
rm -rf .build/UrsusApp .build/release .build/debug
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
- runtime-state SQLite: `~/Library/Application Support/Ursus/Runtime/runtime-state.sqlite`
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

### Fast Debug Flow

1. Build, install, and open a Debug app:

```sh
CONFIGURATION=Debug Support/scripts/build-ursus-app.sh
mkdir -p "$HOME/Applications"
ditto ".build/UrsusApp/Build/Products/Debug/Ursus.app" "$HOME/Applications/Ursus.app"
open "$HOME/Applications/Ursus.app"
```

2. Reset donation state:

```sh
ursus --debug-donation-reset
```

3. Trigger donation eligibility immediately:

```sh
ursus --debug-donation-trigger
```

4. Switch to another app and then back to `Ursus`, or quit and relaunch `Ursus.app`.

5. Verify that the `Support Ursus` prompt appears.

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

## Sparkle Local Prep

The Sparkle command-line tools resolved by this repo currently live at:

```sh
$PWD/.build/UrsusApp/SourcePackages/artifacts/sparkle/Sparkle/bin
```

Generate an EdDSA keypair once on the Mac you will use for signing releases:

```sh
SPARKLE_BIN="$PWD/.build/UrsusApp/SourcePackages/artifacts/sparkle/Sparkle/bin"
"$SPARKLE_BIN/generate_keys"
```

`generate_keys` stores the private key in your login Keychain and prints the public key you should copy into `SUPublicEDKey`.

For a local appcast test:

```sh
SPARKLE_BIN="$PWD/.build/UrsusApp/SourcePackages/artifacts/sparkle/Sparkle/bin"
UPDATES_DIR="$HOME/tmp/ursus-sparkle-updates"

CONFIGURATION=Release Support/scripts/build-ursus-app.sh
mkdir -p "$UPDATES_DIR"
ditto -c -k --keepParent \
  ".build/UrsusApp/Build/Products/Release/Ursus.app" \
  "$UPDATES_DIR/Ursus-0.2.0.zip"
"$SPARKLE_BIN/generate_appcast" "$UPDATES_DIR"
```

If you also place a matching release-notes file beside the archive, Sparkle will pick it up automatically:

- `Ursus-0.2.0.html`
- `Ursus-0.2.0.md`

To serve the generated appcast locally for development testing:

```sh
cd "$UPDATES_DIR"
python3 -m http.server 8000
```

Then temporarily point `SUFeedURL` at:

```sh
http://127.0.0.1:8000/appcast.xml
```

For GitHub Pages, the likely project-pages feed URL for this repo is:

```sh
https://ognistik.github.io/ursus/appcast.xml
```

For GitHub Releases-hosted archives plus GitHub Pages-hosted appcast, generate the new appcast entry with a release-asset prefix for the current tag:

```sh
TAG="v0.2.0"
SPARKLE_BIN="$PWD/.build/UrsusApp/SourcePackages/artifacts/sparkle/Sparkle/bin"
UPDATES_DIR="$HOME/tmp/ursus-sparkle-updates"

"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/ognistik/ursus/releases/download/$TAG/" \
  --embed-release-notes \
  "$UPDATES_DIR"
```

That keeps the generated `appcast.xml` on Pages while each new archive URL points at the matching GitHub Release asset for that tag.

Important:

- `generate_appcast` uses the exact local archive basename when it builds the enclosure URL.
- That means the local filename must exactly match the uploaded GitHub Release asset filename.
- If your uploaded asset is `Ursus.0.2.1.dmg`, do not generate the appcast from a local file named `Ursus 0.2.1.dmg`.

For repeatable releases, prefer the helper script:

```sh
Support/scripts/generate-sparkle-appcast.sh \
  --archive "/absolute/path/to/Ursus.0.2.1.dmg" \
  --tag v0.2.1 \
  --release-notes "/absolute/path/to/Ursus.0.2.1.md"
```

The helper script:

- preserves the exact archive basename you pass in
- reuses the existing `docs/appcast.xml` feed if present
- writes the updated feed back to `docs/appcast.xml`
- uses the GitHub Releases download prefix for the provided tag by default

Before real Sparkle update checks will work, both of these Info.plist placeholders must be replaced:

- `SUFeedURL`
- `SUPublicEDKey`

## Release Signing And Notarization

`CONFIGURATION=Release Support/scripts/build-ursus-app.sh` gives you a local
release build, but it does not produce a distribution-ready notarized artifact
on its own.

Current release packaging flow:

```sh
CONFIGURATION=Release Support/scripts/build-ursus-app.sh

DEVELOPER_ID_APPLICATION="Developer ID Application: Roberto Perales (T25AGZF6DS)" \
NOTARYTOOL_PROFILE="notarytool-profile" \
Support/scripts/sign-and-notarize-release.sh
```

That script:

- copies the built app into `.build/release-artifacts`
- re-signs the staged `Ursus.app` with `Developer ID Application`
- enables hardened runtime on the app-facing bundles it signs
- creates a signed DMG with `create-dmg`
- submits the DMG with `notarytool`
- staples and validates the notarized DMG

Useful variants:

```sh
# Create a Developer ID-signed DMG without submitting to Apple.
Support/scripts/sign-and-notarize-release.sh --skip-notarize

# Use a different app bundle or output directory.
Support/scripts/sign-and-notarize-release.sh \
  --app /path/to/Ursus.app \
  --output-dir /tmp/ursus-release
```

Important notes:

- `create-dmg` signing the DMG does not replace signing the app itself. The app
  still needs a proper `Developer ID Application` signature before notarization.
- The current script notarizes the DMG. If you later want a Sparkle ZIP release
  asset, notarize that ZIP separately; a stapled DMG ticket does not staple the
  `.app` copy inside it.

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
