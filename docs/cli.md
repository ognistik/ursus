# Ursus CLI Reference

The Ursus CLI is designed for fast, terminal-based interactions and deep integration with system automation tools like Raycast, Alfred, BTT, or Keyboard Maestro.

**Pro-Tip:** To use Ursus in your own automation scripts, find the path to the executable first by running:
```bash
which ursus
```
Then, use that absolute path in your automation workflows. In most normal installs, that stable shared path will be `~/.local/bin/ursus`.

---

## The "Selected Note" Flow
One of the most powerful features of Ursus is its awareness of your selected note in Bear. If you have a Bear API token saved in your Ursus setup, many commands become "context-aware" by default:

*   **Bare commands**: Running `ursus --backup-note` or `ursus --apply-template` with no arguments automatically targets the **currently selected Bear note**.
*   **Intelligent Creation**: When you use the bare `ursus --new-note` command, Ursus looks at the note you have open. It can automatically inherit those tags, ensuring your new notes are consistent with your current project—all while following your defined template.

---

## Note Operations

*   **`ursus --new-note`**: Creates a new note. 
    *   **Interactive Flow**: Running this bare creates a note seeded with the selected note’s tags. If no selected notes are found, it uses your inbox tags.
    *   **Explicit Flow**: Add flags for total control:
        *   `--title`: Set the note title.
        *   `--content`: Set the initial note body.
        *   `--tags`: Add a comma-separated list of tags. Use `--replace-tags` if you want to overwrite your inbox tags rather than append.
        *   `--open-note` / `--new-window`: Immediately bring the note into focus in Bear. `--new-window` requires `--open-note`.
*   **`ursus --backup-note`**: Takes a snapshot of your notes. If you pass no arguments, it snapshots the currently selected note. Backups are automatically created by Ursus before AI edit operations, but you can also use this to manually and securely save your work at any stage.
*   **`ursus --restore-note`**: Brings a note back to a previous state. 
    *   **Selected note**: Running this bare restores the currently selected note from its most recent backup.
    *   **Specific**: Use the `NOTE_ID SNAPSHOT_ID` format to roll back to a specific point in time.
*   **`ursus --apply-template`**: Re-applies your template to a note (or the selected note if no target is specified). It ensures your tags land in the `{{tags}}` slot and your content stays clean.

---

## MCP & Bridge Management

*   **`ursus` / `ursus mcp`**: Launches the stdio MCP server. This is the default mode used when connecting Ursus to local clients like Claude Desktop or Codex.
*   **`ursus bridge serve`**: Starts the optional HTTP bridge. This is essential for remote or browser-based AI connectors (like ChatGPT) that need to connect to an MCP URL. This is also set directly from the UI.
*   **Bridge Utilities**:
    *   `ursus bridge status`: Quickly check if the bridge is healthy.
    *   `ursus bridge print-url`: Get your current bridge endpoint URL.
    *   `ursus bridge pause` / `resume`: Control the bridge service without removing it.
    *   `ursus bridge remove`: Fully stop and uninstall the bridge.

---

## Utilities & Maintenance

*   **`ursus doctor`**: Your first stop for troubleshooting. It validates your local setup and flags any issues.
*   **`ursus paths`**: Quickly print the location of your config, logs, and other support files.
*   **Updates**: 
    *   `ursus --check-updates`: Checks for updates via Sparkle.
    *   `ursus --auto-install-updates true|false`: Configure whether Ursus handles its own updates automatically.

---

## Automation Examples

**1. Backup the Selected Note (Keyboard Maestro / Raycast)**
```bash
$HOME/.local/bin/ursus --backup-note
```
*Creates a safety snapshot of whatever you are currently working on in Bear.*

**2. Smart Capture**
```bash
$HOME/.local/bin/ursus --new-note --title "Meeting Notes" --tags work,meeting --open-note
```
*Creates a new tagged note and immediately opens in Bear so you can start typing.*

**3. Template Refresh**
```bash
$HOME/.local/bin/ursus --apply-template
```
*Quickly run this if you've changed your template and want your selected note to reflect the new structure.*
