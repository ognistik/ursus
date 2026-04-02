#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
RAW_CONFIGURATION="${CONFIGURATION:-Debug}"

case "$RAW_CONFIGURATION" in
  debug|Debug)
    CONFIGURATION="Debug"
    ;;
  release|Release)
    CONFIGURATION="Release"
    ;;
  *)
    echo "Unsupported CONFIGURATION: $RAW_CONFIGURATION" >&2
    exit 1
    ;;
esac

DERIVED_DATA_DIR="$ROOT_DIR/.build/UrsusApp"
PROJECT_PATH="$ROOT_DIR/UrsusApp.xcodeproj"
SCHEME_NAME="Ursus"

SWIFT_BUILD_CONFIGURATION="$(printf '%s' "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')"
APP_BUNDLE_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/Ursus.app"
BUNDLED_CLI_SOURCE="$ROOT_DIR/.build/$SWIFT_BUILD_CONFIGURATION/ursus"
BUNDLED_CLI_DESTINATION="$APP_BUNDLE_PATH/Contents/Resources/bin/ursus"
EMBEDDED_HELPER_SOURCE="$ROOT_DIR/.build/$SWIFT_BUILD_CONFIGURATION/Ursus Helper.app"
EMBEDDED_HELPER_DESTINATION="$APP_BUNDLE_PATH/Contents/Library/Helpers/Ursus Helper.app"
ENTITLEMENTS_TEMPLATE_PATH="$ROOT_DIR/Support/scripts/keychain-access-groups-entitlements.template.plist"

codesign_identity_for() {
  local bundle_path="$1"
  local authority

  authority="$(/usr/bin/codesign -dv --verbose=4 "$bundle_path" 2>&1 | sed -n 's/^Authority=//p' | head -n 1 || true)"
  if [ -n "$authority" ]; then
    printf '%s' "$authority"
    return 0
  fi

  printf '%s' '-'
}

codesign_team_identifier_for() {
  local bundle_path="$1"
  /usr/bin/codesign -dv --verbose=4 "$bundle_path" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -n 1
}

codesign_path() {
  local target_path="$1"
  local signing_identity="$2"
  local entitlements_path="${3:-}"
  local preserve_metadata="${4:-}"

  if [ -n "$entitlements_path" ] && [ -n "$preserve_metadata" ]; then
    /usr/bin/codesign \
      --force \
      --sign "$signing_identity" \
      --timestamp=none \
      --entitlements "$entitlements_path" \
      --preserve-metadata="$preserve_metadata" \
      "$target_path"
  elif [ -n "$entitlements_path" ]; then
    /usr/bin/codesign \
      --force \
      --sign "$signing_identity" \
      --timestamp=none \
      --entitlements "$entitlements_path" \
      "$target_path"
  elif [ -n "$preserve_metadata" ]; then
    /usr/bin/codesign \
      --force \
      --sign "$signing_identity" \
      --timestamp=none \
      --preserve-metadata="$preserve_metadata" \
      "$target_path"
  else
    /usr/bin/codesign \
      --force \
      --sign "$signing_identity" \
      --timestamp=none \
      "$target_path"
  fi
}

create_keychain_entitlements() {
  local application_identifier="$1"
  local team_identifier="$2"
  local output_path="$3"
  local keychain_access_group="$team_identifier.com.aft.ursus.shared-token"

  sed \
    -e "s|__APPLICATION_IDENTIFIER__|$application_identifier|g" \
    -e "s|__TEAM_IDENTIFIER__|$team_identifier|g" \
    -e "s|__KEYCHAIN_ACCESS_GROUP__|$keychain_access_group|g" \
    "$ENTITLEMENTS_TEMPLATE_PATH" > "$output_path"
}

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -allowProvisioningUpdates \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  build

APP_CODESIGN_IDENTITY="$(codesign_identity_for "$APP_BUNDLE_PATH")"
APP_TEAM_IDENTIFIER="$(codesign_team_identifier_for "$APP_BUNDLE_PATH")"
HELPER_ENTITLEMENTS_PATH="$(mktemp "${TMPDIR:-/tmp}/ursus-helper-entitlements.XXXXXX.plist")"
CLI_ENTITLEMENTS_PATH="$(mktemp "${TMPDIR:-/tmp}/ursus-cli-entitlements.XXXXXX.plist")"
trap 'rm -f "$HELPER_ENTITLEMENTS_PATH" "$CLI_ENTITLEMENTS_PATH"' EXIT

create_keychain_entitlements "$APP_TEAM_IDENTIFIER.com.aft.ursus-helper" "$APP_TEAM_IDENTIFIER" "$HELPER_ENTITLEMENTS_PATH"
create_keychain_entitlements "$APP_TEAM_IDENTIFIER.ursus" "$APP_TEAM_IDENTIFIER" "$CLI_ENTITLEMENTS_PATH"

CONFIGURATION="$SWIFT_BUILD_CONFIGURATION" CODESIGN_IDENTITY="$APP_CODESIGN_IDENTITY" CODESIGN_ENTITLEMENTS="$HELPER_ENTITLEMENTS_PATH" "$ROOT_DIR/Support/scripts/build-ursus-helper-app.sh" >/dev/null
sh "$ROOT_DIR/Support/scripts/patch-swift-sdk-networktransport.sh"

swift build \
  --package-path "$ROOT_DIR" \
  --configuration "$SWIFT_BUILD_CONFIGURATION" \
  --product ursus

mkdir -p "$(dirname "$BUNDLED_CLI_DESTINATION")"
cp "$BUNDLED_CLI_SOURCE" "$BUNDLED_CLI_DESTINATION"
chmod 755 "$BUNDLED_CLI_DESTINATION"
codesign_path "$BUNDLED_CLI_DESTINATION" "$APP_CODESIGN_IDENTITY" "$CLI_ENTITLEMENTS_PATH"

mkdir -p "$(dirname "$EMBEDDED_HELPER_DESTINATION")"
rm -rf "$EMBEDDED_HELPER_DESTINATION"
ditto "$EMBEDDED_HELPER_SOURCE" "$EMBEDDED_HELPER_DESTINATION"
codesign_path "$EMBEDDED_HELPER_DESTINATION" "$APP_CODESIGN_IDENTITY" "$HELPER_ENTITLEMENTS_PATH"
codesign_path "$APP_BUNDLE_PATH" "$APP_CODESIGN_IDENTITY" "" "identifier,entitlements,requirements,flags,runtime"

echo "$APP_BUNDLE_PATH"
