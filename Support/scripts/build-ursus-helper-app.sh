#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
SWIFT_BUILD_ARGS=""
if [ "$CONFIGURATION" = "release" ]; then
  SWIFT_BUILD_ARGS="-c release"
fi
XCODE_CONFIGURATION="Debug"
if [ "$CONFIGURATION" = "release" ]; then
  XCODE_CONFIGURATION="Release"
fi
BUILD_DIR="$ROOT_DIR/.build"
APP_NAME="Ursus Helper.app"
PRODUCT_NAME="ursus-helper"
EXECUTABLE_SOURCE="$BUILD_DIR/$CONFIGURATION/$PRODUCT_NAME"
APP_DIR="$BUILD_DIR/$CONFIGURATION/$APP_NAME"
CODE_SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
CODESIGN_ENTITLEMENTS="${CODESIGN_ENTITLEMENTS:-}"

resolve_xcode_build_setting() {
  setting_name="$1"
  value="$(
    xcodebuild \
      -project "$ROOT_DIR/UrsusApp.xcodeproj" \
      -scheme Ursus \
      -configuration "$XCODE_CONFIGURATION" \
      -showBuildSettings 2>/dev/null \
      | sed -n "s/^[[:space:]]*$setting_name = //p" \
      | head -n 1
  )"

  if [ -z "$value" ]; then
    echo "Failed to resolve Xcode build setting: $setting_name" >&2
    exit 1
  fi

  printf '%s' "$value"
}

MARKETING_VERSION="${MARKETING_VERSION:-$(resolve_xcode_build_setting MARKETING_VERSION)}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-$(resolve_xcode_build_setting CURRENT_PROJECT_VERSION)}"

swift build --package-path "$ROOT_DIR" $SWIFT_BUILD_ARGS --product "$PRODUCT_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$ROOT_DIR/Support/helper/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CURRENT_PROJECT_VERSION" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE_SOURCE" "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
chmod 755 "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"

if [ -n "$CODE_SIGN_IDENTITY" ]; then
  if [ -n "$CODESIGN_ENTITLEMENTS" ]; then
    /usr/bin/codesign \
      --force \
      --sign "$CODE_SIGN_IDENTITY" \
      --timestamp=none \
      --entitlements "$CODESIGN_ENTITLEMENTS" \
      "$APP_DIR"
  else
    /usr/bin/codesign \
      --force \
      --sign "$CODE_SIGN_IDENTITY" \
      --timestamp=none \
      "$APP_DIR"
  fi
fi

echo "$APP_DIR"
