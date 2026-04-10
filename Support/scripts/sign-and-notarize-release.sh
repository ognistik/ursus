#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DEFAULT_APP_PATH="$ROOT_DIR/.build/UrsusApp/Build/Products/Release/Ursus.app"
DEFAULT_OUTPUT_DIR="$ROOT_DIR/.build/release-artifacts"
APP_PATH="$DEFAULT_APP_PATH"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"
PROVISIONING_PROFILE="${DEVELOPER_ID_PROVISIONING_PROFILE:-}"
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
  --provisioning-profile PATH Developer ID provisioning profile to embed
                              Default: \$DEVELOPER_ID_PROVISIONING_PROFILE
  --skip-notarize             Stop after creating the signed DMG
  -h, --help                  Show this help

Examples:
  DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \\
  DEVELOPER_ID_PROVISIONING_PROFILE="/path/to/Ursus_Developer_ID.provisionprofile" \\
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

plist_has_key() {
  plist_path="$1"
  key_path="$2"
  /usr/libexec/PlistBuddy -c "Print :$key_path" "$plist_path" >/dev/null 2>&1
}

notary_result_value() {
  json_path="$1"
  key_path="$2"
  /usr/bin/plutil -extract "$key_path" raw -o - "$json_path"
}

extract_entitlements() {
  signed_path="$1"
  output_path="$2"

  /usr/bin/codesign -d --entitlements :- "$signed_path" >"$output_path" 2>/dev/null || true
  [ -s "$output_path" ] || return 1

  /usr/bin/plutil -convert xml1 "$output_path" >/dev/null 2>&1 || return 1
  return 0
}

profile_value() {
  profile_plist="$1"
  key_path="$2"
  /usr/libexec/PlistBuddy -c "Print :$key_path" "$profile_plist"
}

profile_matches_bundle_identifier() {
  profile_app_identifier="$1"
  bundle_identifier="$2"

  case "$profile_app_identifier" in
    *.*)
      profile_bundle_identifier="${profile_app_identifier#*.}"
      ;;
    *)
      return 1
      ;;
  esac

  case "$profile_bundle_identifier" in
    \*)
      return 0
      ;;
    *\*)
      profile_bundle_prefix="${profile_bundle_identifier%\*}"
      case "$bundle_identifier" in
        "$profile_bundle_prefix"*)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    *)
      [ "$profile_bundle_identifier" = "$bundle_identifier" ]
      ;;
  esac
}

sign_path() {
  target_path="$1"
  runtime_enabled="${2:-0}"
  entitlements_path="${3:-}"
  effective_entitlements_path="$entitlements_path"
  extracted_entitlements_path=""

  echo "Signing $(basename "$target_path")"

  if [ -z "$effective_entitlements_path" ] && [ -n "${TEMP_DIR:-}" ]; then
    extracted_entitlements_path="$(mktemp "${TEMP_DIR}/$(basename "$target_path").entitlements.XXXXXX.plist")"
    if extract_entitlements "$target_path" "$extracted_entitlements_path"; then
      effective_entitlements_path="$extracted_entitlements_path"
    else
      rm -f "$extracted_entitlements_path"
      extracted_entitlements_path=""
    fi
  fi

  if [ "$runtime_enabled" -eq 1 ] && [ -n "$effective_entitlements_path" ]; then
    /usr/bin/codesign \
      --force \
      --sign "$IDENTITY" \
      --timestamp \
      --options runtime \
      --entitlements "$effective_entitlements_path" \
      "$target_path"
  elif [ "$runtime_enabled" -eq 1 ]; then
    /usr/bin/codesign \
      --force \
      --sign "$IDENTITY" \
      --timestamp \
      --options runtime \
      "$target_path"
  elif [ -n "$effective_entitlements_path" ]; then
    /usr/bin/codesign \
      --force \
      --sign "$IDENTITY" \
      --timestamp \
      --entitlements "$effective_entitlements_path" \
      "$target_path"
  else
    /usr/bin/codesign \
      --force \
      --sign "$IDENTITY" \
      --timestamp \
      "$target_path"
  fi

  if [ -n "$extracted_entitlements_path" ]; then
    rm -f "$extracted_entitlements_path"
  fi
}

require_universal_binary() {
  target_path="$1"
  has_arm64=0
  has_x86_64=0
  architectures="$(/usr/bin/lipo -archs "$target_path" 2>/dev/null || true)"

  case " $architectures " in
    *" arm64 "*) has_arm64=1 ;;
  esac
  case " $architectures " in
    *" x86_64 "*) has_x86_64=1 ;;
  esac

  if [ "$has_arm64" -eq 1 ] && [ "$has_x86_64" -eq 1 ]; then
    return 0
  fi

  fail "Expected universal arm64+x86_64 binary at $target_path; found: ${architectures:-unknown}"
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
    --provisioning-profile)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      PROVISIONING_PROFILE="$2"
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
require_command /usr/bin/openssl
require_command /bin/cp
require_command /bin/mv
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
APP_BUNDLE_IDENTIFIER="$(plist_value "$APP_INFO_PLIST" CFBundleIdentifier)"
APP_EXECUTABLE_NAME="$(plist_value "$APP_INFO_PLIST" CFBundleExecutable)"
DMG_PATH="$OUTPUT_DIR/$APP_NAME $APP_VERSION.dmg"
RELEASE_ASSET_DMG_PATH="$OUTPUT_DIR/$APP_NAME.$APP_VERSION.dmg"
NOTARY_RESULT_PATH="$OUTPUT_DIR/notary-submit-result.json"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ursus-sign.XXXXXX")"
EXPANDED_ENTITLEMENTS_PATH="$TEMP_DIR/Ursus.release.entitlements"
PROFILE_PLIST_PATH="$TEMP_DIR/provisioning-profile.plist"
STAGED_APP_PATH="$TEMP_DIR/$APP_NAME.app"
STAGED_PROFILE_PATH="$STAGED_APP_PATH/Contents/embedded.provisionprofile"
STAGED_HELPER_EXECUTABLE_PATH="$STAGED_APP_PATH/Contents/Library/Helpers/Ursus Helper.app/Contents/MacOS/ursus-helper"
REMOVE_SOURCE_APP_ON_SUCCESS=0
RELEASE_SUCCEEDED=0
if [ "$APP_PATH" = "$DEFAULT_APP_PATH" ]; then
  REMOVE_SOURCE_APP_ON_SUCCESS=1
fi
cleanup() {
  if [ "$RELEASE_SUCCEEDED" -eq 1 ] && [ "$REMOVE_SOURCE_APP_ON_SUCCESS" -eq 1 ]; then
    rm -rf "$APP_PATH"
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

if ! extract_entitlements "$APP_PATH" "$EXPANDED_ENTITLEMENTS_PATH"; then
  fail "Failed to extract signing entitlements from $APP_PATH. Build the app with Xcode signing before running this release script."
fi

/usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$EXPANDED_ENTITLEMENTS_PATH" >/dev/null 2>&1 || true

RESTRICTED_KEYCHAIN_GROUPS=0
if plist_has_key "$EXPANDED_ENTITLEMENTS_PATH" "keychain-access-groups"; then
  RESTRICTED_KEYCHAIN_GROUPS=1
fi

if [ -n "$PROVISIONING_PROFILE" ]; then
  [ -f "$PROVISIONING_PROFILE" ] || fail "Provisioning profile not found: $PROVISIONING_PROFILE"
  /usr/bin/security cms -D -i "$PROVISIONING_PROFILE" >"$PROFILE_PLIST_PATH" \
    || fail "Failed to decode provisioning profile: $PROVISIONING_PROFILE"

  ENTITLEMENTS_TEAM_IDENTIFIER="$(plist_value "$EXPANDED_ENTITLEMENTS_PATH" "com.apple.developer.team-identifier" 2>/dev/null || true)"
  PROFILE_TEAM_IDENTIFIER="$(profile_value "$PROFILE_PLIST_PATH" "TeamIdentifier:0" 2>/dev/null || true)"
  PROFILE_APP_IDENTIFIER="$(profile_value "$PROFILE_PLIST_PATH" "Entitlements:com.apple.application-identifier" 2>/dev/null || true)"
  IDENTITY_SHA1S="$(/usr/bin/security find-certificate -a -c "$IDENTITY" -Z 2>/dev/null | sed -n 's/^SHA-1 hash: //p' | tr -d ':')"

  [ -n "$PROFILE_TEAM_IDENTIFIER" ] || fail "Provisioning profile is missing TeamIdentifier: $PROVISIONING_PROFILE"
  [ -n "$PROFILE_APP_IDENTIFIER" ] || fail "Provisioning profile is missing com.apple.application-identifier entitlement: $PROVISIONING_PROFILE"
  [ -n "$IDENTITY_SHA1S" ] || fail "Could not find local signing certificate for identity: $IDENTITY"
  if [ -n "$ENTITLEMENTS_TEAM_IDENTIFIER" ] && [ "$PROFILE_TEAM_IDENTIFIER" != "$ENTITLEMENTS_TEAM_IDENTIFIER" ]; then
    fail "Provisioning profile team '$PROFILE_TEAM_IDENTIFIER' does not match app entitlements team '$ENTITLEMENTS_TEAM_IDENTIFIER'."
  fi

  profile_matches_bundle_identifier "$PROFILE_APP_IDENTIFIER" "$APP_BUNDLE_IDENTIFIER" \
    || fail "Provisioning profile app identifier '$PROFILE_APP_IDENTIFIER' does not match bundle identifier '$APP_BUNDLE_IDENTIFIER'."

  PROFILE_CERTIFICATE_MATCH=0
  PROFILE_CERTIFICATE_SHA1S=""
  PROFILE_CERTIFICATE_INDEX=0
  while :; do
    PROFILE_CERTIFICATE_PATH="$TEMP_DIR/profile-certificate-$PROFILE_CERTIFICATE_INDEX.der"
    if ! /usr/libexec/PlistBuddy -c "Print :DeveloperCertificates:$PROFILE_CERTIFICATE_INDEX" "$PROFILE_PLIST_PATH" >"$PROFILE_CERTIFICATE_PATH" 2>/dev/null; then
      break
    fi

    PROFILE_CERTIFICATE_SHA1="$(/usr/bin/openssl x509 -inform DER -in "$PROFILE_CERTIFICATE_PATH" -noout -fingerprint -sha1 2>/dev/null | sed 's/^.*Fingerprint=//; s/://g')"
    if [ -n "$PROFILE_CERTIFICATE_SHA1" ]; then
      PROFILE_CERTIFICATE_SHA1S="$PROFILE_CERTIFICATE_SHA1S $PROFILE_CERTIFICATE_SHA1"
      for IDENTITY_SHA1 in $IDENTITY_SHA1S; do
        if [ "$PROFILE_CERTIFICATE_SHA1" = "$IDENTITY_SHA1" ]; then
          PROFILE_CERTIFICATE_MATCH=1
        fi
      done
    fi

    PROFILE_CERTIFICATE_INDEX=$((PROFILE_CERTIFICATE_INDEX + 1))
  done

  if [ "$PROFILE_CERTIFICATE_MATCH" -ne 1 ]; then
    fail "Provisioning profile does not include the signing certificate '$IDENTITY'. Local certificate SHA-1: $IDENTITY_SHA1S. Profile certificate SHA-1(s):$PROFILE_CERTIFICATE_SHA1S. Regenerate the Developer ID provisioning profile with the same certificate used for signing."
  fi
elif [ "$RESTRICTED_KEYCHAIN_GROUPS" -eq 1 ]; then
  fail "This app uses keychain-access-groups, so the Developer ID build also needs a matching provisioning profile. Pass --provisioning-profile or set DEVELOPER_ID_PROVISIONING_PROFILE."
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"
rm -f "$RELEASE_ASSET_DMG_PATH"
rm -f "$NOTARY_RESULT_PATH"
/usr/bin/ditto "$APP_PATH" "$STAGED_APP_PATH"
rm -f "$STAGED_PROFILE_PATH"

require_universal_binary "$STAGED_APP_PATH/Contents/MacOS/$APP_EXECUTABLE_NAME"
[ -f "$STAGED_HELPER_EXECUTABLE_PATH" ] || fail "Expected embedded helper executable not found: $STAGED_HELPER_EXECUTABLE_PATH"
require_universal_binary "$STAGED_HELPER_EXECUTABLE_PATH"

if [ -n "$PROVISIONING_PROFILE" ]; then
  /bin/cp "$PROVISIONING_PROFILE" "$STAGED_PROFILE_PATH"
fi

echo "Using signing identity: $IDENTITY"
echo "Staging app at: $STAGED_APP_PATH"
if [ -n "$PROVISIONING_PROFILE" ]; then
  echo "Embedding provisioning profile: $PROVISIONING_PROFILE"
fi

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

sign_path "$STAGED_APP_PATH" 1 "$EXPANDED_ENTITLEMENTS_PATH"

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

if [ "$RELEASE_ASSET_DMG_PATH" != "$DMG_PATH" ]; then
  echo "Renaming DMG for GitHub/Sparkle: $RELEASE_ASSET_DMG_PATH"
  /bin/mv "$DMG_PATH" "$RELEASE_ASSET_DMG_PATH"
  DMG_PATH="$RELEASE_ASSET_DMG_PATH"
fi

RELEASE_SUCCEEDED=1

echo
echo "Release artifacts:"
echo "  DMG: $DMG_PATH"
if [ "$REMOVE_SOURCE_APP_ON_SUCCESS" -eq 1 ]; then
  echo "  Source app kept: no"
else
  echo "  Source app kept: yes"
fi
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
  echo "  Notary profile: $NOTARY_PROFILE"
else
  echo "  Notarization: skipped"
fi
