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

DERIVED_DATA_DIR="$ROOT_DIR/.build/BearMCPApp"
PROJECT_PATH="$ROOT_DIR/BearMCPApp.xcodeproj"
SCHEME_NAME="Bear MCP"

SWIFT_BUILD_CONFIGURATION="$(printf '%s' "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')"
APP_BUNDLE_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/Bear MCP.app"
BUNDLED_CLI_SOURCE="$ROOT_DIR/.build/$SWIFT_BUILD_CONFIGURATION/bear-mcp"
BUNDLED_CLI_DESTINATION="$APP_BUNDLE_PATH/Contents/Resources/bin/bear-mcp"
EMBEDDED_HELPER_SOURCE="$ROOT_DIR/.build/$SWIFT_BUILD_CONFIGURATION/Bear MCP Helper.app"
EMBEDDED_HELPER_DESTINATION="$APP_BUNDLE_PATH/Contents/Library/Helpers/Bear MCP Helper.app"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO \
  build

CONFIGURATION="$SWIFT_BUILD_CONFIGURATION" "$ROOT_DIR/Support/scripts/build-selected-note-helper-app.sh" >/dev/null
sh "$ROOT_DIR/Support/scripts/patch-swift-sdk-networktransport.sh"

swift build \
  --package-path "$ROOT_DIR" \
  --configuration "$SWIFT_BUILD_CONFIGURATION" \
  --product bear-mcp

mkdir -p "$(dirname "$BUNDLED_CLI_DESTINATION")"
cp "$BUNDLED_CLI_SOURCE" "$BUNDLED_CLI_DESTINATION"
chmod 755 "$BUNDLED_CLI_DESTINATION"

mkdir -p "$(dirname "$EMBEDDED_HELPER_DESTINATION")"
rm -rf "$EMBEDDED_HELPER_DESTINATION"
ditto "$EMBEDDED_HELPER_SOURCE" "$EMBEDDED_HELPER_DESTINATION"

echo "$APP_BUNDLE_PATH"
