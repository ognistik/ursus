#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
SWIFT_BUILD_ARGS=""
if [ "$CONFIGURATION" = "release" ]; then
  SWIFT_BUILD_ARGS="-c release"
fi
BUILD_DIR="$ROOT_DIR/.build"
APP_NAME="Ursus Helper.app"
PRODUCT_NAME="ursus-helper"
EXECUTABLE_SOURCE="$BUILD_DIR/$CONFIGURATION/$PRODUCT_NAME"
APP_DIR="$BUILD_DIR/$CONFIGURATION/$APP_NAME"
CODE_SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
CODESIGN_ENTITLEMENTS="${CODESIGN_ENTITLEMENTS:-}"

swift build --package-path "$ROOT_DIR" $SWIFT_BUILD_ARGS --product "$PRODUCT_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$ROOT_DIR/Support/helper/Info.plist" "$APP_DIR/Contents/Info.plist"
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
