#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DEFAULT_SPARKLE_BIN_DIR="$ROOT_DIR/.build/UrsusApp/SourcePackages/artifacts/sparkle/Sparkle/bin"
DEFAULT_OUTPUT_PATH="$ROOT_DIR/docs/appcast.xml"
DEFAULT_STAGING_DIR="$ROOT_DIR/.build/sparkle-appcast"
DEFAULT_DOWNLOAD_BASE="https://github.com/ognistik/ursus/releases/download"

SPARKLE_BIN_DIR="$DEFAULT_SPARKLE_BIN_DIR"
OUTPUT_PATH="$DEFAULT_OUTPUT_PATH"
STAGING_DIR="$DEFAULT_STAGING_DIR"
ARCHIVE_PATH=""
RELEASE_NOTES_PATH=""
TAG=""
DOWNLOAD_URL_PREFIX=""
ACCOUNT="ed25519"

usage() {
  cat <<EOF
Usage: $(basename "$0") --archive PATH --tag TAG [options]

Generate or update Sparkle appcast.xml for Ursus using the exact archive
basename that was uploaded to GitHub Releases, then copy the result into the
Pages-published appcast path.

Options:
  --archive PATH              Path to the signed DMG or ZIP uploaded to the release
  --tag TAG                   GitHub release tag, eg v0.2.1
  --release-notes PATH        Optional .md/.html/.txt release notes file
  --output PATH               Destination appcast.xml path
                              Default: $DEFAULT_OUTPUT_PATH
  --staging-dir PATH          Temporary staging directory
                              Default: $DEFAULT_STAGING_DIR
  --download-url-prefix URL   Override the release asset prefix
                              Default: $DEFAULT_DOWNLOAD_BASE/<tag>/
  --sparkle-bin-dir PATH      Sparkle bin directory
                              Default: $DEFAULT_SPARKLE_BIN_DIR
  --account NAME              Keychain EdDSA account for generate_appcast
                              Default: ed25519
  -h, --help                  Show this help

Notes:
  - The archive filename must exactly match the uploaded GitHub Release asset
    basename, because generate_appcast uses that basename for enclosure URLs.
  - If an existing appcast.xml is present at the output path, it is copied into
    the staging directory first so generate_appcast can append to the current feed.

Example:
  $(basename "$0") \\
    --archive "/Users/you/Downloads/Ursus.0.2.1.dmg" \\
    --tag v0.2.1 \\
    --release-notes "/Users/you/Downloads/Ursus.0.2.1.md"
EOF
}

fail() {
  echo "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --tag)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      TAG="$2"
      shift 2
      ;;
    --release-notes)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      RELEASE_NOTES_PATH="$2"
      shift 2
      ;;
    --output)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --staging-dir)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      STAGING_DIR="$2"
      shift 2
      ;;
    --download-url-prefix)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      DOWNLOAD_URL_PREFIX="$2"
      shift 2
      ;;
    --sparkle-bin-dir)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      SPARKLE_BIN_DIR="$2"
      shift 2
      ;;
    --account)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      ACCOUNT="$2"
      shift 2
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

[ -n "$ARCHIVE_PATH" ] || fail "Missing required --archive PATH"
[ -n "$TAG" ] || fail "Missing required --tag TAG"
[ -f "$ARCHIVE_PATH" ] || fail "Archive not found: $ARCHIVE_PATH"

GENERATE_APPCAST_BIN="$SPARKLE_BIN_DIR/generate_appcast"
[ -x "$GENERATE_APPCAST_BIN" ] || fail "generate_appcast not found or not executable: $GENERATE_APPCAST_BIN"

require_command /usr/bin/basename
require_command /usr/bin/dirname
require_command /bin/cp
require_command /bin/mkdir
require_command /bin/rm

ARCHIVE_BASENAME="$(basename "$ARCHIVE_PATH")"
ARCHIVE_STEM="${ARCHIVE_BASENAME%.*}"
ARCHIVE_EXTENSION="${ARCHIVE_BASENAME##*.}"
[ "$ARCHIVE_EXTENSION" != "$ARCHIVE_BASENAME" ] || fail "Archive must have a file extension: $ARCHIVE_BASENAME"

if [ -z "$DOWNLOAD_URL_PREFIX" ]; then
  DOWNLOAD_URL_PREFIX="$DEFAULT_DOWNLOAD_BASE/$TAG/"
fi

mkdir -p "$STAGING_DIR"
rm -rf "$STAGING_DIR/work"
mkdir -p "$STAGING_DIR/work"
WORK_DIR="$STAGING_DIR/work"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

if [ -f "$OUTPUT_PATH" ]; then
  cp "$OUTPUT_PATH" "$WORK_DIR/appcast.xml"
fi

cp "$ARCHIVE_PATH" "$WORK_DIR/$ARCHIVE_BASENAME"

if [ -n "$RELEASE_NOTES_PATH" ]; then
  [ -f "$RELEASE_NOTES_PATH" ] || fail "Release notes file not found: $RELEASE_NOTES_PATH"
  RELEASE_NOTES_EXTENSION="${RELEASE_NOTES_PATH##*.}"
  cp "$RELEASE_NOTES_PATH" "$WORK_DIR/$ARCHIVE_STEM.$RELEASE_NOTES_EXTENSION"
else
  ARCHIVE_DIR="$(dirname "$ARCHIVE_PATH")"
  for extension in html md txt; do
    CANDIDATE="$ARCHIVE_DIR/$ARCHIVE_STEM.$extension"
    if [ -f "$CANDIDATE" ]; then
      cp "$CANDIDATE" "$WORK_DIR/$ARCHIVE_STEM.$extension"
      break
    fi
  done
fi

"$GENERATE_APPCAST_BIN" \
  --account "$ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --embed-release-notes \
  "$WORK_DIR"

mkdir -p "$(dirname "$OUTPUT_PATH")"
cp "$WORK_DIR/appcast.xml" "$OUTPUT_PATH"

echo "Updated appcast:"
echo "  archive: $ARCHIVE_BASENAME"
echo "  output: $OUTPUT_PATH"
echo "  download-prefix: $DOWNLOAD_URL_PREFIX"
echo
echo "Next:"
echo "  1. Commit and push $OUTPUT_PATH"
echo "  2. Confirm the enclosure URL matches the uploaded release asset"
