import BearCore
import Foundation

public struct BearHostAppSetupSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let appName: String
    public let configPath: String?
    public let status: BearDoctorCheckStatus
    public let statusTitle: String
    public let detail: String
    public let snippetTitle: String?
    public let snippetLanguage: String?
    public let snippet: String?
    public let mergeNote: String?
    public let checks: [String]

    public init(
        id: String,
        appName: String,
        configPath: String? = nil,
        status: BearDoctorCheckStatus,
        statusTitle: String,
        detail: String,
        snippetTitle: String? = nil,
        snippetLanguage: String? = nil,
        snippet: String? = nil,
        mergeNote: String? = nil,
        checks: [String] = []
    ) {
        self.id = id
        self.appName = appName
        self.configPath = configPath
        self.status = status
        self.statusTitle = statusTitle
        self.detail = detail
        self.snippetTitle = snippetTitle
        self.snippetLanguage = snippetLanguage
        self.snippet = snippet
        self.mergeNote = mergeNote
        self.checks = checks
    }
}

enum BearHostAppSupport {
    static func loadSetups(
        fileManager: FileManager = .default,
        launcherURL: URL = BearMCPCLILocator.publicLauncherURL,
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> [BearHostAppSetupSnapshot] {
        makeResults(
            fileManager: fileManager,
            launcherURL: launcherURL,
            homeDirectoryURL: homeDirectoryURL
        ).map(\.setup)
    }

    static func diagnostics(
        fileManager: FileManager = .default,
        launcherURL: URL = BearMCPCLILocator.publicLauncherURL,
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> [BearDoctorCheck] {
        makeResults(
            fileManager: fileManager,
            launcherURL: launcherURL,
            homeDirectoryURL: homeDirectoryURL
        ).compactMap(\.doctorCheck)
    }

    private static func makeResults(
        fileManager: FileManager,
        launcherURL: URL,
        homeDirectoryURL: URL
    ) -> [HostAppResult] {
        [
            genericLocalHostResult(fileManager: fileManager, launcherURL: launcherURL),
            codexResult(fileManager: fileManager, launcherURL: launcherURL, homeDirectoryURL: homeDirectoryURL),
            claudeDesktopResult(fileManager: fileManager, launcherURL: launcherURL, homeDirectoryURL: homeDirectoryURL),
            chatGPTResult(),
        ]
    }

    private static func genericLocalHostResult(
        fileManager: FileManager,
        launcherURL: URL
    ) -> HostAppResult {
        let cliPath = launcherURL.path
        let snippet = """
        {
          "type": "stdio",
          "command": "\(cliPath)",
          "args": ["mcp"]
        }
        """
        let checks = [
            "Install or repair the public launcher at \(cliPath) from Ursus.app.",
            "In any local stdio MCP host, point `command` at that path and set `args` to `[\"mcp\"]`.",
            "Restart the host app after saving so it reloads the Ursus server definition.",
        ]

        if fileManager.fileExists(atPath: cliPath), fileManager.isExecutableFile(atPath: cliPath) {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "generic-local-stdio",
                    appName: "Any Local MCP Host",
                    status: .ok,
                    statusTitle: "Ready",
                    detail: "Use the public launcher path below with any local stdio MCP host, not just Codex or Claude Desktop.",
                    snippetTitle: "Generic stdio example",
                    snippetLanguage: "json",
                    snippet: snippet,
                    mergeNote: "Host apps name their fields differently, but the important values are the executable path plus `args = [\"mcp\"]`.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-local-stdio",
                    value: cliPath,
                    status: .ok,
                    detail: "public launcher target for any local stdio MCP host"
                )
            )
        }

        return HostAppResult(
            setup: BearHostAppSetupSnapshot(
                id: "generic-local-stdio",
                appName: "Any Local MCP Host",
                status: .missing,
                statusTitle: "Launcher not installed yet",
                detail: "Install the public launcher first, then reuse the same command path in any local stdio MCP host.",
                snippetTitle: "Generic stdio example",
                snippetLanguage: "json",
                snippet: snippet,
                mergeNote: "Ursus.app should stay host-agnostic here: copy the command and args into whichever local MCP host you use.",
                checks: checks
            ),
            doctorCheck: BearDoctorCheck(
                key: "host-local-stdio",
                value: cliPath,
                status: .missing,
                detail: "install the public launcher before wiring it into local MCP hosts"
            )
        )
    }

    private static func codexResult(
        fileManager: FileManager,
        launcherURL: URL,
        homeDirectoryURL: URL
    ) -> HostAppResult {
        let configURL = homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
        let cliPath = launcherURL.path
        let snippet = """
        [mcp_servers.ursus]
        enabled = true
        command = "\(cliPath)"
        args = ["mcp"]
        """
        let checks = [
            "Use Ursus.app to install or repair the launcher at \(cliPath).",
            "Add or update the `[mcp_servers.ursus]` section in `\(configURL.path)` so `command` points at that launcher path and `args` contains `\"mcp\"`.",
            "Restart Codex after saving the config so it reloads the Ursus MCP server definition.",
        ]

        guard fileManager.fileExists(atPath: configURL.path) else {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "codex",
                    appName: "Codex",
                    configPath: configURL.path,
                    status: .missing,
                    statusTitle: "Config file not found",
                    detail: "Create `\(configURL.path)` or let Codex create it, then add the `ursus` server section below so Codex uses the public launcher instead of a repo-local build output.",
                    snippetTitle: "Codex `config.toml` section",
                    snippetLanguage: "toml",
                    snippet: snippet,
                    mergeNote: "If you already have other MCP servers configured, keep them and append this `[mcp_servers.ursus]` section.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-codex",
                    value: configURL.path,
                    status: .missing,
                    detail: "config.toml not found; add the `ursus` server entry pointing at \(cliPath)"
                )
            )
        }

        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "codex",
                    appName: "Codex",
                    configPath: configURL.path,
                    status: .invalid,
                    statusTitle: "Config file unreadable",
                    detail: "Ursus.app could see `\(configURL.path)` but could not read it. Fix file permissions or contents, then point `mcp_servers.ursus` at the public launcher.",
                    snippetTitle: "Codex `config.toml` section",
                    snippetLanguage: "toml",
                    snippet: snippet,
                    mergeNote: "Keep any existing Codex settings and MCP servers; just make sure the Ursus section matches this command path.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-codex",
                    value: configURL.path,
                    status: .invalid,
                    detail: "config.toml exists but Ursus.app could not read it"
                )
            )
        }

        let hasUrsusSection = contents.contains("[mcp_servers.ursus]") || contents.contains("[mcp_servers.\"ursus\"]")
        let hasLegacyBearSection = contents.contains("[mcp_servers.bear]") || contents.contains("[mcp_servers.\"bear\"]")
        let hasStablePath = contents.contains("command = \"\(cliPath)\"")
        let hasMCPArgs = contents.range(
            of: #"args\s*=\s*\[[^\]]*"mcp"[^\]]*\]"#,
            options: .regularExpression
        ) != nil

        if hasUrsusSection && hasStablePath && hasMCPArgs {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "codex",
                    appName: "Codex",
                    configPath: configURL.path,
                    status: .ok,
                    statusTitle: "Configured",
                    detail: "Codex already points `mcp_servers.ursus` at the public launcher path.",
                    snippetTitle: "Current recommended section",
                    snippetLanguage: "toml",
                    snippet: snippet,
                    mergeNote: "No change is needed unless you want to repair the launcher from Ursus.app.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-codex",
                    value: configURL.path,
                    status: .ok,
                    detail: "configured to launch Ursus from the public launcher path"
                )
            )
        }

        if hasUrsusSection {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "codex",
                    appName: "Codex",
                    configPath: configURL.path,
                    status: .invalid,
                    statusTitle: "Needs update",
                    detail: "Codex already has an `ursus` server entry, but it is not using the public launcher path and `args = [\"mcp\"]` shape together yet.",
                    snippetTitle: "Replace the `ursus` section with",
                    snippetLanguage: "toml",
                    snippet: snippet,
                    mergeNote: "Update the existing `ursus` section rather than adding a duplicate server entry.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-codex",
                    value: configURL.path,
                    status: .invalid,
                    detail: "Bear entry detected, but it is not aligned with the public launcher path at \(cliPath)"
                )
            )
        }

        if hasLegacyBearSection {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "codex",
                    appName: "Codex",
                    configPath: configURL.path,
                    status: .invalid,
                    statusTitle: "Needs rename",
                    detail: "Codex still uses a legacy `bear` server entry. Rename that section to `ursus` so the host config matches the Ursus server identity.",
                    snippetTitle: "Rename the section to",
                    snippetLanguage: "toml",
                    snippet: snippet,
                    mergeNote: "Rename the existing `bear` section to `ursus` and keep any other configured MCP servers.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-codex",
                    value: configURL.path,
                    status: .invalid,
                    detail: "legacy `bear` server entry detected; rename it to `ursus`"
                )
            )
        }

        return HostAppResult(
            setup: BearHostAppSetupSnapshot(
                id: "codex",
                appName: "Codex",
                configPath: configURL.path,
                status: .notConfigured,
                statusTitle: "Ursus Server Not Added Yet",
                detail: "Codex is installed, but `\(configURL.path)` does not yet contain an `ursus` server entry.",
                snippetTitle: "Add this Ursus section",
                snippetLanguage: "toml",
                snippet: snippet,
                mergeNote: "Append this section to the existing file; do not remove other MCP server entries.",
                checks: checks
            ),
            doctorCheck: BearDoctorCheck(
                key: "host-codex",
                value: configURL.path,
                status: .notConfigured,
                detail: "config.toml exists, but no `ursus` server entry was detected"
            )
        )
    }

    private static func claudeDesktopResult(
        fileManager: FileManager,
        launcherURL: URL,
        homeDirectoryURL: URL
    ) -> HostAppResult {
        let candidateURLs = [
            homeDirectoryURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Claude", isDirectory: true)
                .appendingPathComponent("claude_desktop_config.json", isDirectory: false),
            homeDirectoryURL
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("claude", isDirectory: true)
                .appendingPathComponent("claude_desktop_config.json", isDirectory: false),
        ]
        let configURL = candidateURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) ?? candidateURLs[0]
        let cliPath = launcherURL.path
        let snippet = """
        {
          "mcpServers": {
            "ursus": {
              "type": "stdio",
              "command": "\(cliPath)",
              "args": ["mcp"],
              "env": {}
            }
          }
        }
        """
        let checks = [
            "Use Ursus.app to install or repair the launcher at \(cliPath).",
            "Add or merge the `ursus` server entry into `mcpServers` inside `\(configURL.path)` so Claude Desktop launches the public launcher.",
            "Restart Claude Desktop after saving the JSON so it reloads the local MCP server.",
        ]

        guard fileManager.fileExists(atPath: configURL.path) else {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "claude-desktop",
                    appName: "Claude Desktop",
                    configPath: configURL.path,
                    status: .missing,
                    statusTitle: "Config file not found",
                    detail: "Create `\(configURL.path)` or configure a local MCP server from Claude Desktop, then merge the Ursus entry below so Claude uses the public launcher path.",
                    snippetTitle: "Claude Desktop JSON example",
                    snippetLanguage: "json",
                    snippet: snippet,
                    mergeNote: "If `claude_desktop_config.json` already contains other servers, merge just the `ursus` object into the existing `mcpServers` dictionary instead of replacing the whole file.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-claude-desktop",
                    value: configURL.path,
                    status: .missing,
                    detail: "claude_desktop_config.json not found; add an `ursus` stdio entry pointing at \(cliPath)"
                )
            )
        }

        guard
            let data = fileManager.contents(atPath: configURL.path),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "claude-desktop",
                    appName: "Claude Desktop",
                    configPath: configURL.path,
                    status: .invalid,
                    statusTitle: "Config file invalid",
                    detail: "`\(configURL.path)` could not be parsed as JSON. Fix the file, then merge the Ursus stdio entry below.",
                    snippetTitle: "Claude Desktop JSON example",
                    snippetLanguage: "json",
                    snippet: snippet,
                    mergeNote: "The file needs to stay valid JSON after you add the Ursus server object.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-claude-desktop",
                    value: configURL.path,
                    status: .invalid,
                    detail: "claude_desktop_config.json exists but is not valid JSON"
                )
            )
        }

        let mcpServers = root["mcpServers"] as? [String: Any]
        let ursusServer = mcpServers?["ursus"] as? [String: Any]
        let legacyBearServer = mcpServers?["bear"] as? [String: Any]
        let command = ursusServer?["command"] as? String
        let args = ursusServer?["args"] as? [String] ?? []
        let transportType = ursusServer?["type"] as? String

        if ursusServer != nil {
            let commandMatches = command == cliPath
            let argsMatch = args.contains("mcp")
            let typeMatches = transportType == nil || transportType == "stdio"

            if commandMatches && argsMatch && typeMatches {
                return HostAppResult(
                    setup: BearHostAppSetupSnapshot(
                        id: "claude-desktop",
                        appName: "Claude Desktop",
                        configPath: configURL.path,
                        status: .ok,
                        statusTitle: "Configured",
                        detail: "Claude Desktop already has an Ursus stdio server entry pointing at the public launcher path.",
                        snippetTitle: "Current recommended JSON",
                        snippetLanguage: "json",
                        snippet: snippet,
                        mergeNote: "No change is needed unless you want to repair the public launcher from Ursus.app.",
                        checks: checks
                    ),
                    doctorCheck: BearDoctorCheck(
                        key: "host-claude-desktop",
                        value: configURL.path,
                        status: .ok,
                        detail: "configured to launch Ursus from the public launcher path"
                    )
                )
            }

            let detail = if !commandMatches {
                "Claude Desktop already has an Ursus entry, but `command` is not `\(cliPath)` yet."
            } else if !argsMatch {
                "Claude Desktop already has an Ursus entry, but `args` does not include `\"mcp\"` yet."
            } else if !typeMatches {
                "Claude Desktop already has an Ursus entry, but it is not marked as a stdio server."
            } else {
                "Claude Desktop already has an Ursus entry, but it does not match the current recommended shape."
            }

            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "claude-desktop",
                    appName: "Claude Desktop",
                    configPath: configURL.path,
                    status: .invalid,
                    statusTitle: "Needs update",
                    detail: detail,
                    snippetTitle: "Update the Ursus server entry to",
                    snippetLanguage: "json",
                    snippet: snippet,
                    mergeNote: "Replace only the existing `ursus` object inside `mcpServers`; keep any other configured Claude servers.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-claude-desktop",
                    value: configURL.path,
                    status: .invalid,
                    detail: "Bear entry detected, but it is not aligned with the public launcher path at \(cliPath)"
                )
            )
        }

        if legacyBearServer != nil {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "claude-desktop",
                    appName: "Claude Desktop",
                    configPath: configURL.path,
                    status: .invalid,
                    statusTitle: "Needs rename",
                    detail: "Claude Desktop still uses a legacy `bear` server entry. Rename that object to `ursus` so the host config matches the Ursus server identity.",
                    snippetTitle: "Rename the server object to",
                    snippetLanguage: "json",
                    snippet: snippet,
                    mergeNote: "Rename the existing `bear` object inside `mcpServers` to `ursus` and keep any other configured Claude servers.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-claude-desktop",
                    value: configURL.path,
                    status: .invalid,
                    detail: "legacy `bear` server entry detected; rename it to `ursus`"
                )
            )
        }

        return HostAppResult(
            setup: BearHostAppSetupSnapshot(
                id: "claude-desktop",
                appName: "Claude Desktop",
                configPath: configURL.path,
                status: .notConfigured,
                statusTitle: "Ursus Server Not Added Yet",
                detail: "Claude Desktop config exists, but no `mcpServers.ursus` entry was detected.",
                snippetTitle: "Add this `ursus` server object",
                snippetLanguage: "json",
                snippet: snippet,
                mergeNote: "Merge the `ursus` object into the existing `mcpServers` dictionary rather than replacing the entire file.",
                checks: checks
            ),
            doctorCheck: BearDoctorCheck(
                key: "host-claude-desktop",
                value: configURL.path,
                status: .notConfigured,
                detail: "claude_desktop_config.json exists, but no `ursus` server entry was detected"
            )
        )
    }

    private static func chatGPTResult() -> HostAppResult {
        let checks = [
            "Do not point ChatGPT at the local Ursus launcher path; current ChatGPT MCP support is remote-only.",
            "If you want Bear in ChatGPT, deploy a remote MCP server over streaming HTTP or SSE instead of using the local stdio binary.",
            "Use Ursus.app for local host apps like Codex and Claude Desktop, and treat ChatGPT as a separate remote-connector path for now.",
        ]

        return HostAppResult(
            setup: BearHostAppSetupSnapshot(
                id: "chatgpt",
                appName: "ChatGPT",
                status: .notConfigured,
                statusTitle: "Remote MCP only",
                detail: "ChatGPT developer mode currently supports remote MCP servers, not local stdio binaries, so the Ursus launcher path is not the right integration target here.",
                checks: checks
            ),
            doctorCheck: BearDoctorCheck(
                key: "host-chatgpt",
                value: "remote MCP only",
                status: .notConfigured,
                detail: "ChatGPT developer mode currently supports remote streaming HTTP or SSE servers rather than local stdio binaries"
            )
        )
    }

}

private struct HostAppResult {
    let setup: BearHostAppSetupSnapshot
    let doctorCheck: BearDoctorCheck?
}
