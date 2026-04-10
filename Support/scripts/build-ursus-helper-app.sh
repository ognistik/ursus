#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
RAW_CONFIGURATION="${CONFIGURATION:-debug}"

case "$RAW_CONFIGURATION" in
  debug|Debug)
    CONFIGURATION="debug"
    ;;
  release|Release)
    CONFIGURATION="release"
    ;;
  *)
    echo "Unsupported CONFIGURATION: $RAW_CONFIGURATION" >&2
    exit 1
    ;;
esac

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
UNIVERSAL_RELEASE="${UNIVERSAL_RELEASE:-1}"

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

if [ "$CONFIGURATION" = "release" ] && [ "$UNIVERSAL_RELEASE" = "1" ]; then
  swift build --package-path "$ROOT_DIR" -c release --arch arm64 --product "$PRODUCT_NAME"
  swift build --package-path "$ROOT_DIR" -c release --arch x86_64 --product "$PRODUCT_NAME"
  mkdir -p "$(dirname "$EXECUTABLE_SOURCE")"
  /usr/bin/lipo \
    -create \
    "$BUILD_DIR/arm64-apple-macosx/release/$PRODUCT_NAME" \
    "$BUILD_DIR/x86_64-apple-macosx/release/$PRODUCT_NAME" \
    -output "$EXECUTABLE_SOURCE"
  chmod 755 "$EXECUTABLE_SOURCE"
else
  swift build --package-path "$ROOT_DIR" $SWIFT_BUILD_ARGS --product "$PRODUCT_NAME"
fi

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
