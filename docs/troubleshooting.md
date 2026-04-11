# Ursus Troubleshooting

Ursus is designed to be self-healing. When you open the app, it automatically repairs the shared launcher (`~/.local/bin/ursus`) and reconciles your setup. Most "issues" are resolved by simply restarting your AI client or reloading the bridge.

If things still aren't working, follow this guide to isolate and fix the problem.

---

## 1. Quick Health Checks
Run these commands in your terminal to see if the core runtime is healthy:

*   **`ursus doctor`**: The primary diagnostic tool. It checks path integrity, launch configurations, and internal states.
*   **`ursus bridge status`**: Checks if the optional HTTP bridge is running and reachable.
*   **`ursus paths`**: Lists where Ursus is looking for your config, templates, and logs. Use this if you think Ursus is reading the "wrong" file.

---

## 2. Common Issues & Fixes

### If your MCP client cannot connect
*   **Check the Path**: Ensure your client is pointing to `~/.local/bin/ursus`.
*   **Check the Args**: For stdio clients (Claude Desktop, Codex), your configuration **must** include `["mcp"]` in the arguments.
*   **Restart the Client**: Most MCP clients only load the server definition on startup. After changing your config, completely quit and restart your AI app.

### If Selected-Note workflows aren't working
*   **Token Check**: Go to the `Setup` tab in Ursus. If the Bear API token field is empty, Ursus cannot target the note you have selected.
*   **Restart the Runtime**: If you just added or removed a token, the running MCP process doesn't know yet. Restart your MCP client (or the bridge) to pick up the change.
*   **Bundle Context**: In a development setup... if you are running `swift run ursus` from a terminal instead of using the installed `Ursus.app`, macOS entitlement restrictions may block keychain access. Always use the installed `Ursus.app` for real workflows.

### If the HTTP Bridge seems stuck
*   **Reload**: Run `ursus bridge pause` followed by `ursus bridge resume`.
*   **Check the exact URL**: Run `ursus bridge print-url` and make sure your client is using the full MCP endpoint, including `/mcp`.
*   **Clean Reinstall**: Run `ursus bridge remove` to clear the bridge's LaunchAgent, then go to the `Setup` tab in the Ursus app to re-enable/re-install the bridge.

### If you changed Preferences, Tools, or Templates
*   **Reload**: Any change to the configuration (via Preferences or the Tools tab) requires the MCP client to re-initialize. Restart your client. If you are using the bridge, restart the bridge first.

---

## 3. Advanced Logs
If a command fails, the logs are the best place to find the "why."

*   **Main debug log**: `~/Library/Application Support/Ursus/Logs/debug.log`
*   **Bridge stdout/stderr**:
    *   `~/Library/Application Support/Ursus/Logs/bridge.stdout.log`
    *   `~/Library/Application Support/Ursus/Logs/bridge.stderr.log`

---

## 4. How to Report an Issue
If you can't fix it yourself, please open a [GitHub Issue](https://github.com/ognistik/ursus/issues). To help me debug, include:

1.  **The output of `ursus doctor`**.
2.  **Which AI host you are using** (e.g., Claude Desktop, Codex, ChatGPT via bridge).
3.  **Your MCP configuration** for the host app you're actually using. For example, that might be `~/.codex/config.toml`, `claude_desktop_config.json`, or `~/.claude.json`. If the problem looks Ursus-specific, `~/Library/Application Support/Ursus/config.json` can also help.
4.  **The relevant log file** from `~/Library/Application Support/Ursus/Logs/` if a crash or error occurred. `bridge.stderr.log` and `bridge.stdout.log` may also help diagnose and fix bridge issues.
5.  **A quick description of the expected vs. actual behavior**. System information and steps to reproduce are the most useful.

---

## 5. Clean Reset
If Ursus is behaving completely unexpectedly, you can reset it to a factory-fresh state:

```bash
# 1. Kill all running Ursus processes
pkill -f "/Ursus.app/Contents/MacOS/Ursus" 2>/dev/null || true

# 2. Remove app data and configuration
rm -rf "$HOME/Library/Application Support/Ursus"

# 3. Remove the shared launcher and bridge agent
rm -f "$HOME/Library/LaunchAgents/com.aft.ursus.plist"
rm -f "$HOME/.local/bin/ursus"
```
