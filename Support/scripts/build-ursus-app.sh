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

  /usr/bin/codesign \
    --force \
    --sign "$signing_identity" \
    --timestamp=none \
    "$target_path"
}

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  build

APP_CODESIGN_IDENTITY="$(codesign_identity_for "$APP_BUNDLE_PATH")"

CONFIGURATION="$SWIFT_BUILD_CONFIGURATION" CODESIGN_IDENTITY="$APP_CODESIGN_IDENTITY" "$ROOT_DIR/Support/scripts/build-ursus-helper-app.sh" >/dev/null
sh "$ROOT_DIR/Support/scripts/patch-swift-sdk-networktransport.sh"

swift build \
  --package-path "$ROOT_DIR" \
  --configuration "$SWIFT_BUILD_CONFIGURATION" \
  --product ursus

mkdir -p "$(dirname "$BUNDLED_CLI_DESTINATION")"
cp "$BUNDLED_CLI_SOURCE" "$BUNDLED_CLI_DESTINATION"
chmod 755 "$BUNDLED_CLI_DESTINATION"
codesign_path "$BUNDLED_CLI_DESTINATION" "$APP_CODESIGN_IDENTITY"

mkdir -p "$(dirname "$EMBEDDED_HELPER_DESTINATION")"
rm -rf "$EMBEDDED_HELPER_DESTINATION"
ditto "$EMBEDDED_HELPER_SOURCE" "$EMBEDDED_HELPER_DESTINATION"
codesign_path "$EMBEDDED_HELPER_DESTINATION" "$APP_CODESIGN_IDENTITY"
codesign_path "$APP_BUNDLE_PATH" "$APP_CODESIGN_IDENTITY"

echo "$APP_BUNDLE_PATH"
