#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DEFAULT_CHANGELOG_PATH="$ROOT_DIR/CHANGELOG.md"
DEFAULT_GITHUB_REPO="ognistik/ursus"

CHANGELOG_PATH="$DEFAULT_CHANGELOG_PATH"
GITHUB_REPO="$DEFAULT_GITHUB_REPO"
VERSION=""
TAG=""
DMG_PATH=""
RELEASE_NOTES_PATH=""
RELEASE_DATE="${RELEASE_DATE:-$(date +%Y/%m/%d)}"
CREATE_GITHUB_DRAFT=1
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $(basename "$0") --version VERSION --dmg PATH [options]

Promote CHANGELOG.md's UNRELEASED notes into a versioned release section,
write a same-stem Markdown notes file beside the DMG, and create or update a
draft GitHub Release with the DMG attached.

Options:
  --version VERSION           Release version, eg 1.0.4
  --dmg PATH                  Signed/notarized DMG to attach
  --tag TAG                   GitHub release tag
                              Default: v<VERSION>
  --changelog PATH            Changelog to update
                              Default: $DEFAULT_CHANGELOG_PATH
  --release-notes PATH        Markdown notes output path
                              Default: same stem as --dmg with .md extension
  --github-repo OWNER/REPO    GitHub repository
                              Default: $DEFAULT_GITHUB_REPO
  --date YYYY/MM/DD           Release date for the changelog
                              Default: today's date
  --skip-github-draft         Only update changelog and write notes
  --dry-run                   Validate and print the GitHub commands only
  -h, --help                  Show this help

Examples:
  $(basename "$0") \\
    --version 1.0.4 \\
    --dmg "$ROOT_DIR/.build/release-artifacts/Ursus.1.0.4.dmg"
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
    --version)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      VERSION="$2"
      shift 2
      ;;
    --dmg)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      DMG_PATH="$2"
      shift 2
      ;;
    --tag)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      TAG="$2"
      shift 2
      ;;
    --changelog)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      CHANGELOG_PATH="$2"
      shift 2
      ;;
    --release-notes)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      RELEASE_NOTES_PATH="$2"
      shift 2
      ;;
    --github-repo)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      GITHUB_REPO="$2"
      shift 2
      ;;
    --date)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      RELEASE_DATE="$2"
      shift 2
      ;;
    --skip-github-draft)
      CREATE_GITHUB_DRAFT=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
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

[ -n "$VERSION" ] || fail "Missing required --version VERSION"
[ -n "$DMG_PATH" ] || fail "Missing required --dmg PATH"
[ -f "$DMG_PATH" ] || fail "DMG not found: $DMG_PATH"
[ -f "$CHANGELOG_PATH" ] || fail "Changelog not found: $CHANGELOG_PATH"

case "$VERSION" in
  v*)
    fail "--version should not include the leading v; pass --tag to override the tag"
    ;;
esac

if [ -z "$TAG" ]; then
  TAG="v$VERSION"
fi

if [ -z "$RELEASE_NOTES_PATH" ]; then
  DMG_DIR="$(dirname "$DMG_PATH")"
  DMG_BASENAME="$(basename "$DMG_PATH")"
  RELEASE_NOTES_PATH="$DMG_DIR/${DMG_BASENAME%.*}.md"
fi

require_command python3
require_command /bin/mkdir

if [ "$CREATE_GITHUB_DRAFT" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
  require_command gh
fi

/bin/mkdir -p "$(dirname "$RELEASE_NOTES_PATH")"

RELEASE_EXISTS=0
if [ "$CREATE_GITHUB_DRAFT" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
  if RELEASE_IS_DRAFT="$(gh release view "$TAG" --repo "$GITHUB_REPO" --json isDraft --jq '.isDraft' 2>/dev/null)"; then
    RELEASE_EXISTS=1
    [ "$RELEASE_IS_DRAFT" = "true" ] \
      || fail "GitHub release already exists and is not a draft: $GITHUB_REPO@$TAG"
  fi
fi

python3 - "$CHANGELOG_PATH" "$RELEASE_NOTES_PATH" "$GITHUB_REPO" "$TAG" "$RELEASE_DATE" <<'PY'
import pathlib
import re
import sys

changelog_path = pathlib.Path(sys.argv[1])
release_notes_path = pathlib.Path(sys.argv[2])
github_repo = sys.argv[3]
tag = sys.argv[4]
release_date = sys.argv[5]

text = changelog_path.read_text()
newline = "\n" if text.endswith("\n") else ""
text = text.rstrip("\n")

release_heading_re = re.compile(
    r"(?m)^## \[" + re.escape(tag) + r"\]\(https://github\.com/"
    + re.escape(github_repo)
    + r"/releases/tag/"
    + re.escape(tag)
    + r"\) - \d{4}/\d{2}/\d{2}\s*$"
)

existing_match = release_heading_re.search(text)
changed = False

if existing_match:
    body_start = text.find("\n", existing_match.end())
    if body_start == -1:
        body_start = len(text)
    else:
        body_start += 1
    next_separator = re.search(r"(?m)^---\s*$", text[body_start:])
    body_end = len(text) if next_separator is None else body_start + next_separator.start()
    notes = text[body_start:body_end].strip()
else:
    unreleased_match = re.search(r"(?m)^## UNRELEASED\s*$", text)
    if not unreleased_match:
        sys.exit("CHANGELOG.md is missing a '## UNRELEASED' section")

    unreleased_body_start = text.find("\n", unreleased_match.end())
    if unreleased_body_start == -1:
        unreleased_body_start = len(text)
    else:
        unreleased_body_start += 1

    next_release = re.search(r"(?m)^---\n## \[v", text[unreleased_body_start:])
    if not next_release:
        sys.exit("CHANGELOG.md is missing the separator before the latest release section")

    release_start = unreleased_body_start + next_release.start()
    notes = text[unreleased_body_start:release_start].strip()
    if not notes:
        sys.exit("CHANGELOG.md has no release notes under '## UNRELEASED'")

    new_section = (
        f"---\n"
        f"## [{tag}](https://github.com/{github_repo}/releases/tag/{tag}) - {release_date}\n"
        f"{notes}\n\n"
    )
    text = text[:unreleased_body_start].rstrip() + "\n\n" + new_section + text[release_start:].lstrip()
    changed = True

if not notes:
    sys.exit(f"CHANGELOG.md release section for {tag} has no notes")

release_notes_path.write_text(notes.rstrip() + "\n")
if changed:
    changelog_path.write_text(text.rstrip() + newline)

print("changed=yes" if changed else "changed=no")
PY

ASSET_LABEL="$(basename "$DMG_PATH")"

echo "Prepared release notes:"
echo "  changelog: $CHANGELOG_PATH"
echo "  notes: $RELEASE_NOTES_PATH"
echo "  tag: $TAG"

if [ "$CREATE_GITHUB_DRAFT" -eq 0 ]; then
  echo "GitHub draft release: skipped"
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "GitHub draft release dry run:"
  echo "  gh release create $TAG \"$DMG_PATH#$ASSET_LABEL\" --repo $GITHUB_REPO --draft --title $TAG --notes-file $RELEASE_NOTES_PATH"
  echo "  or, if the release exists:"
  echo "  gh release edit $TAG --repo $GITHUB_REPO --draft --title $TAG --notes-file $RELEASE_NOTES_PATH"
  echo "  gh release upload $TAG \"$DMG_PATH#$ASSET_LABEL\" --repo $GITHUB_REPO --clobber"
  exit 0
fi

if [ "$RELEASE_EXISTS" -eq 1 ]; then
  gh release edit "$TAG" \
    --repo "$GITHUB_REPO" \
    --draft \
    --title "$TAG" \
    --notes-file "$RELEASE_NOTES_PATH"
  gh release upload "$TAG" "$DMG_PATH#$ASSET_LABEL" --repo "$GITHUB_REPO" --clobber
else
  gh release create "$TAG" "$DMG_PATH#$ASSET_LABEL" \
    --repo "$GITHUB_REPO" \
    --draft \
    --title "$TAG" \
    --notes-file "$RELEASE_NOTES_PATH"
fi

echo "GitHub draft release prepared:"
echo "  https://github.com/$GITHUB_REPO/releases/tag/$TAG"
