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
EMBEDDED_HELPER_SOURCE="$ROOT_DIR/.build/$SWIFT_BUILD_CONFIGURATION/Ursus Helper.app"
EMBEDDED_HELPER_DESTINATION="$APP_BUNDLE_PATH/Contents/Library/Helpers/Ursus Helper.app"
LEGACY_BUNDLED_CLI_PATH="$APP_BUNDLE_PATH/Contents/Resources/bin/ursus"

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

CONFIGURATION="$SWIFT_BUILD_CONFIGURATION" CODESIGN_IDENTITY="$APP_CODESIGN_IDENTITY" "$ROOT_DIR/Support/scripts/build-ursus-helper-app.sh" >/dev/null
sh "$ROOT_DIR/Support/scripts/patch-swift-sdk-networktransport.sh"
rm -f "$LEGACY_BUNDLED_CLI_PATH"
rmdir "$(dirname "$LEGACY_BUNDLED_CLI_PATH")" 2>/dev/null || true

mkdir -p "$(dirname "$EMBEDDED_HELPER_DESTINATION")"
rm -rf "$EMBEDDED_HELPER_DESTINATION"
ditto "$EMBEDDED_HELPER_SOURCE" "$EMBEDDED_HELPER_DESTINATION"
codesign_path "$EMBEDDED_HELPER_DESTINATION" "$APP_CODESIGN_IDENTITY"
codesign_path "$APP_BUNDLE_PATH" "$APP_CODESIGN_IDENTITY" "" "identifier,entitlements,requirements,flags,runtime"

echo "$APP_BUNDLE_PATH"
