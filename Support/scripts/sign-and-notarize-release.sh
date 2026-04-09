#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DEFAULT_APP_PATH="$ROOT_DIR/.build/UrsusApp/Build/Products/Release/Ursus.app"
DEFAULT_OUTPUT_DIR="$ROOT_DIR/.build/release-artifacts"
APP_PATH="$DEFAULT_APP_PATH"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"
CREATE_DMG_BIN="${CREATE_DMG_BIN:-create-dmg}"
SKIP_NOTARIZE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Re-sign a built Ursus.app for Developer ID distribution, create a signed DMG,
and optionally notarize + staple the DMG.

Options:
  --app PATH                  Path to Ursus.app
                              Default: $DEFAULT_APP_PATH
  --output-dir PATH           Directory for staged artifacts
                              Default: $DEFAULT_OUTPUT_DIR
  --identity NAME             Developer ID Application identity
                              Default: \$DEVELOPER_ID_APPLICATION or the first
                              matching local Developer ID Application cert
  --notarytool-profile NAME   Keychain profile for xcrun notarytool
                              Default: \$NOTARYTOOL_PROFILE
  --skip-notarize             Stop after creating the signed DMG
  -h, --help                  Show this help

Examples:
  DEVELOPER_ID_APPLICATION="Developer ID Application: Roberto Perales (T25AGZF6DS)" \\
  NOTARYTOOL_PROFILE="notarytool-profile" \\
  $(basename "$0")

  $(basename "$0") --skip-notarize
EOF
}

fail() {
  echo "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

default_developer_id_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
    | head -n 1
}

plist_value() {
  plist_path="$1"
  key_path="$2"
  /usr/libexec/PlistBuddy -c "Print :$key_path" "$plist_path"
}

notary_result_value() {
  json_path="$1"
  key_path="$2"
  /usr/bin/plutil -extract "$key_path" raw -o - "$json_path"
}

sign_path() {
  target_path="$1"
  runtime_enabled="${2:-0}"
  entitlements_path="${3:-}"

  echo "Signing $(basename "$target_path")"

  if [ "$runtime_enabled" -eq 1 ] && [ -n "$entitlements_path" ]; then
    /usr/bin/codesign \
      --force \
      --sign "$IDENTITY" \
      --timestamp \
      --options runtime \
      --entitlements "$entitlements_path" \
      "$target_path"
  elif [ "$runtime_enabled" -eq 1 ]; then
    /usr/bin/codesign \
      --force \
      --sign "$IDENTITY" \
      --timestamp \
      --options runtime \
      "$target_path"
  elif [ -n "$entitlements_path" ]; then
    /usr/bin/codesign \
      --force \
      --sign "$IDENTITY" \
      --timestamp \
      --entitlements "$entitlements_path" \
      "$target_path"
  else
    /usr/bin/codesign \
      --force \
      --sign "$IDENTITY" \
      --timestamp \
      "$target_path"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      APP_PATH="$2"
      shift 2
      ;;
    --output-dir)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --identity)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      IDENTITY="$2"
      shift 2
      ;;
    --notarytool-profile)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

require_command /usr/bin/codesign
require_command /usr/bin/ditto
require_command /usr/bin/xcrun
require_command /usr/bin/security
require_command /usr/libexec/PlistBuddy

[ -d "$APP_PATH" ] || fail "App bundle not found: $APP_PATH"

if [ -z "$IDENTITY" ]; then
  IDENTITY="$(default_developer_id_identity)"
fi
[ -n "$IDENTITY" ] || fail "No Developer ID Application identity found. Pass --identity or set DEVELOPER_ID_APPLICATION."

if [ "$SKIP_NOTARIZE" -eq 0 ]; then
  [ -n "$NOTARY_PROFILE" ] || fail "No notarytool profile found. Pass --notarytool-profile or set NOTARYTOOL_PROFILE."
  require_command "$CREATE_DMG_BIN"
else
  require_command "$CREATE_DMG_BIN"
fi

APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
APP_NAME="$(basename "$APP_PATH" .app)"
APP_VERSION="$(plist_value "$APP_INFO_PLIST" CFBundleShortVersionString)"
ENTITLEMENTS_PATH="$ROOT_DIR/Support/app/Ursus.entitlements"
STAGED_APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$APP_NAME $APP_VERSION.dmg"
NOTARY_RESULT_PATH="$OUTPUT_DIR/notary-submit-result.json"

mkdir -p "$OUTPUT_DIR"
rm -rf "$STAGED_APP_PATH"
rm -f "$DMG_PATH"
rm -f "$NOTARY_RESULT_PATH"
/usr/bin/ditto "$APP_PATH" "$STAGED_APP_PATH"

echo "Using signing identity: $IDENTITY"
echo "Staging app at: $STAGED_APP_PATH"

find "$STAGED_APP_PATH/Contents" -type f \
  \( -perm +111 -o -name '*.dylib' \) \
  | while IFS= read -r executable_path; do
      case "$executable_path" in
        *.dylib)
          sign_path "$executable_path" 0
          ;;
        *)
          sign_path "$executable_path" 1
          ;;
      esac
    done

find "$STAGED_APP_PATH/Contents" -depth -type d \
  \( -name '*.app' -o -name '*.appex' -o -name '*.framework' -o -name '*.xpc' \) \
  ! -path "$STAGED_APP_PATH" \
  | while IFS= read -r nested_bundle; do
      case "$nested_bundle" in
        *.app|*.appex|*.xpc)
          sign_path "$nested_bundle" 1
          ;;
        *)
          sign_path "$nested_bundle" 0
          ;;
      esac
    done

sign_path "$STAGED_APP_PATH" 1 "$ENTITLEMENTS_PATH"

echo "Verifying app signature"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGED_APP_PATH"
/usr/sbin/spctl -a -t exec -vv "$STAGED_APP_PATH"

echo "Creating signed DMG"
"$CREATE_DMG_BIN" --overwrite --identity "$IDENTITY" "$STAGED_APP_PATH" "$OUTPUT_DIR"
[ -f "$DMG_PATH" ] || fail "Expected DMG was not created: $DMG_PATH"

if [ "$SKIP_NOTARIZE" -eq 0 ]; then
  echo "Submitting DMG for notarization"
  /usr/bin/xcrun notarytool submit \
    "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format json \
    > "$NOTARY_RESULT_PATH"

  NOTARY_STATUS="$(notary_result_value "$NOTARY_RESULT_PATH" status)"
  NOTARY_ID="$(notary_result_value "$NOTARY_RESULT_PATH" id)"

  if [ "$NOTARY_STATUS" != "Accepted" ]; then
    echo "Notarization status: $NOTARY_STATUS" >&2
    echo "Submission ID: $NOTARY_ID" >&2
    echo "Notary log:" >&2
    /usr/bin/xcrun notarytool log "$NOTARY_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fail "Notarization failed for $DMG_PATH"
  fi

  echo "Stapling DMG"
  /usr/bin/xcrun stapler staple -v "$DMG_PATH"

  echo "Validating stapled DMG"
  /usr/bin/xcrun stapler validate -v "$DMG_PATH"
  /usr/sbin/spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
fi

echo
echo "Release artifacts:"
echo "  App: $STAGED_APP_PATH"
echo "  DMG: $DMG_PATH"
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
  echo "  Notary profile: $NOTARY_PROFILE"
else
  echo "  Notarization: skipped"
fi
