# CHANGELOG

## UNRELEASED

### New
- Added first-class Bear YAML frontmatter support
  - bear_get_notes now returns frontmatter separately and keeps body clean; discovery summaries expose compact frontmatter metadata; and bear_replace_content now supports kind: frontmatter for add/replace/remove.
  - Simplified frontmatter payloads and improved discovery clarity by reporting frontmatter matches separately from body matches, while clarifying that expected_version is required only for full body replacement.

### Changed
- Improved bear_replace_content by adding guardrails to prevent full body replacements without the AI being aware of its content. 
  - Implemented version checks from database & temporary snapshot system
  - Ursus now has an improved built-in conflict resolution system for note body replacements when the user has manually edited a note (modifying the database version vs expected_version).