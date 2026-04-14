# Ursus CLI Reference

The Ursus CLI is designed for fast terminal workflows and for automation tools like Raycast, Alfred, BTT, or Keyboard Maestro.

To find the shared launcher path on your machine, run:

```bash
which ursus
```

In most normal installs, that stable path will be `~/.local/bin/ursus`.

---

## Help Overview

Use the top-level help when you want the big picture:

```bash
ursus --help
ursus -h
```

Use scoped help when you want a focused command list:

```bash
ursus note --help
ursus update --help
ursus bridge --help
```

This keeps the terminal output easier to scan instead of forcing every command into one crowded screen.

---

## The Selected Note Flow

If you have a Bear API token saved in Ursus, several note commands become context-aware by default:

- `ursus note backup` with no arguments backs up the currently selected Bear note.
- `ursus note apply-template` with no arguments targets the currently selected Bear note.
- `ursus note restore` with no arguments restores the selected Bear note from its most recent backup.
- `ursus note new` with no modifiers uses the interactive selected-note-aware flow and can inherit tags from the note you currently have open.

---

## Note Commands

The note command group is:

```bash
ursus note ...
ursus n ...
```

Main commands:

- `ursus note new [--title TEXT] [--content TEXT] [--tags TAGS] [--replace-tags] [--open-note] [--new-window]`
- `ursus note backup [note-id-or-title ...]`
- `ursus note restore`
- `ursus note restore latest [note-id-or-title ...]`
- `ursus note restore snapshot NOTE_ID SNAPSHOT_ID [NOTE_ID SNAPSHOT_ID ...]`
- `ursus note apply-template [note-id-or-title ...]`

Creation flags:

- `--title`, `-t`: set the note title
- `--content`, `-c`: set the initial body content
- `--tags`, `-g`: add comma-separated tags; you may pass this more than once
- `--replace-tags`, `-rt`: replace tags instead of appending them
- `--open-note`, `-on`: open the note in Bear after creating it
- `--new-window`, `-nw`: open the note in a new Bear window; requires `--open-note`

Restore modes:

- `ursus note restore`: restore the selected note from its latest backup
- `ursus note restore latest "Project Notes"`: restore the latest backup for one specific note
- `ursus note restore snapshot abc123 snap001`: restore one exact note and snapshot pair
- `ursus note restore snapshot abc123 snap001 def456 snap002`: restore several exact pairs in one command

Note behavior:

- `ursus note new` with no modifiers keeps the current interactive create flow.
- Explicit `ursus note new` mode skips selected-note lookup and uses the create-adds-inbox-tags default when `--tags` is omitted.
- `ursus note backup`, `ursus note restore`, and `ursus note apply-template` use the selected Bear note when no targets are passed.
- Passed note selectors resolve as exact note id first, then exact case-insensitive title.

Examples:

```bash
$HOME/.local/bin/ursus note backup
$HOME/.local/bin/ursus note new --title "Meeting Notes" --tags work,meeting --open-note
$HOME/.local/bin/ursus note restore
$HOME/.local/bin/ursus note apply-template
```

---

## Update Commands

The update command group is:

```bash
ursus update ...
ursus u ...
```

Commands:

- `ursus update check`
- `ursus update auto-install on`
- `ursus update auto-install off`

Examples:

```bash
$HOME/.local/bin/ursus update check
$HOME/.local/bin/ursus update auto-install on
```

`on` enables Sparkle automatic installs and automatic update checks. `off` disables automatic installs without changing automatic update checks.

---

## MCP And Bridge Commands

- `ursus` or `ursus mcp`: launch the stdio MCP server
- `ursus bridge serve`: start the optional HTTP bridge
- `ursus bridge status`: check whether the bridge is healthy
- `ursus bridge print-url`: print the configured bridge MCP endpoint URL
- `ursus bridge pause` / `resume`: control the installed bridge service without removing it
- `ursus bridge remove`: fully stop and uninstall the bridge

---

## Utilities

- `ursus doctor`: validate the local Ursus setup and print diagnostics
- `ursus paths`: print the important support-file and runtime paths
