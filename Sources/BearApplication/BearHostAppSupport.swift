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
        appManagedCLIURL: URL = BearMCPCLILocator.appManagedInstallURL,
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> [BearHostAppSetupSnapshot] {
        makeResults(
            fileManager: fileManager,
            appManagedCLIURL: appManagedCLIURL,
            homeDirectoryURL: homeDirectoryURL
        ).map(\.setup)
    }

    static func diagnostics(
        fileManager: FileManager = .default,
        appManagedCLIURL: URL = BearMCPCLILocator.appManagedInstallURL,
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> [BearDoctorCheck] {
        makeResults(
            fileManager: fileManager,
            appManagedCLIURL: appManagedCLIURL,
            homeDirectoryURL: homeDirectoryURL
        ).compactMap(\.doctorCheck)
    }

    private static func makeResults(
        fileManager: FileManager,
        appManagedCLIURL: URL,
        homeDirectoryURL: URL
    ) -> [HostAppResult] {
        [
            codexResult(fileManager: fileManager, appManagedCLIURL: appManagedCLIURL, homeDirectoryURL: homeDirectoryURL),
            claudeDesktopResult(fileManager: fileManager, appManagedCLIURL: appManagedCLIURL, homeDirectoryURL: homeDirectoryURL),
            chatGPTResult(),
        ]
    }

    private static func codexResult(
        fileManager: FileManager,
        appManagedCLIURL: URL,
        homeDirectoryURL: URL
    ) -> HostAppResult {
        let configURL = homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
        let cliPath = appManagedCLIURL.path
        let snippet = """
        [mcp_servers.bear]
        enabled = true
        command = "\(cliPath)"
        args = ["mcp"]
        """
        let checks = [
            "Use Bear MCP.app to install or refresh the CLI at \(cliPath).",
            "Add or update the `[mcp_servers.bear]` section in `\(configURL.path)` so `command` points at that stable CLI path and `args` contains `\"mcp\"`.",
            "Restart Codex after saving the config so it reloads the MCP server definition.",
        ]

        guard fileManager.fileExists(atPath: configURL.path) else {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "codex",
                    appName: "Codex",
                    configPath: configURL.path,
                    status: .missing,
                    statusTitle: "Config file not found",
                    detail: "Create `\(configURL.path)` or let Codex create it, then add the Bear MCP section below so Codex uses the stable app-managed CLI instead of a repo-local build output.",
                    snippetTitle: "Codex `config.toml` section",
                    snippetLanguage: "toml",
                    snippet: snippet,
                    mergeNote: "If you already have other MCP servers configured, keep them and append this `[mcp_servers.bear]` section.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-codex",
                    value: configURL.path,
                    status: .missing,
                    detail: "config.toml not found; add the Bear server entry pointing at \(cliPath)"
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
                    detail: "Bear MCP.app could see `\(configURL.path)` but could not read it. Fix file permissions or contents, then point `mcp_servers.bear` at the stable app-managed CLI.",
                    snippetTitle: "Codex `config.toml` section",
                    snippetLanguage: "toml",
                    snippet: snippet,
                    mergeNote: "Keep any existing Codex settings and MCP servers; just make sure the Bear section matches this command path.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-codex",
                    value: configURL.path,
                    status: .invalid,
                    detail: "config.toml exists but Bear MCP.app could not read it"
                )
            )
        }

        let hasBearSection = contents.contains("[mcp_servers.bear]") || contents.contains("[mcp_servers.\"bear\"]")
        let hasStablePath = contents.contains("command = \"\(cliPath)\"")
        let hasMCPArgs = contents.range(
            of: #"args\s*=\s*\[[^\]]*"mcp"[^\]]*\]"#,
            options: .regularExpression
        ) != nil

        if hasBearSection && hasStablePath && hasMCPArgs {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "codex",
                    appName: "Codex",
                    configPath: configURL.path,
                    status: .ok,
                    statusTitle: "Configured",
                    detail: "Codex already points `mcp_servers.bear` at the stable app-managed CLI path.",
                    snippetTitle: "Current recommended section",
                    snippetLanguage: "toml",
                    snippet: snippet,
                    mergeNote: "No change is needed unless you want to refresh the CLI copy from Bear MCP.app.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-codex",
                    value: configURL.path,
                    status: .ok,
                    detail: "configured to launch Bear MCP from the app-managed CLI path"
                )
            )
        }

        if hasBearSection {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "codex",
                    appName: "Codex",
                    configPath: configURL.path,
                    status: .invalid,
                    statusTitle: "Needs update",
                    detail: "Codex already has a Bear MCP entry, but it is not using the stable app-managed CLI path and `args = [\"mcp\"]` shape together yet.",
                    snippetTitle: "Replace the Bear section with",
                    snippetLanguage: "toml",
                    snippet: snippet,
                    mergeNote: "Update the existing Bear section rather than adding a duplicate server entry.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-codex",
                    value: configURL.path,
                    status: .invalid,
                    detail: "Bear entry detected, but it is not aligned with the stable CLI path at \(cliPath)"
                )
            )
        }

        return HostAppResult(
            setup: BearHostAppSetupSnapshot(
                id: "codex",
                appName: "Codex",
                configPath: configURL.path,
                status: .notConfigured,
                statusTitle: "Bear MCP not added yet",
                detail: "Codex is installed, but `\(configURL.path)` does not yet contain a Bear MCP server entry.",
                snippetTitle: "Add this Codex section",
                snippetLanguage: "toml",
                snippet: snippet,
                mergeNote: "Append this section to the existing file; do not remove other MCP server entries.",
                checks: checks
            ),
            doctorCheck: BearDoctorCheck(
                key: "host-codex",
                value: configURL.path,
                status: .notConfigured,
                detail: "config.toml exists, but no Bear MCP server entry was detected"
            )
        )
    }

    private static func claudeDesktopResult(
        fileManager: FileManager,
        appManagedCLIURL: URL,
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
        let cliPath = appManagedCLIURL.path
        let snippet = """
        {
          "mcpServers": {
            "bear": {
              "type": "stdio",
              "command": "\(cliPath)",
              "args": ["mcp"],
              "env": {}
            }
          }
        }
        """
        let checks = [
            "Use Bear MCP.app to install or refresh the CLI at \(cliPath).",
            "Add or merge the `bear` server entry into `mcpServers` inside `\(configURL.path)` so Claude Desktop launches the stable app-managed CLI.",
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
                    detail: "Create `\(configURL.path)` or configure a local MCP server from Claude Desktop, then merge the Bear entry below so Claude uses the stable app-managed CLI path.",
                    snippetTitle: "Claude Desktop JSON example",
                    snippetLanguage: "json",
                    snippet: snippet,
                    mergeNote: "If `claude_desktop_config.json` already contains other servers, merge just the `bear` object into the existing `mcpServers` dictionary instead of replacing the whole file.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-claude-desktop",
                    value: configURL.path,
                    status: .missing,
                    detail: "claude_desktop_config.json not found; add a Bear stdio entry pointing at \(cliPath)"
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
                    detail: "`\(configURL.path)` could not be parsed as JSON. Fix the file, then merge the Bear stdio entry below.",
                    snippetTitle: "Claude Desktop JSON example",
                    snippetLanguage: "json",
                    snippet: snippet,
                    mergeNote: "The file needs to stay valid JSON after you add the Bear server object.",
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
        let bearServer = mcpServers?["bear"] as? [String: Any]
        let command = bearServer?["command"] as? String
        let args = bearServer?["args"] as? [String] ?? []
        let transportType = bearServer?["type"] as? String

        if bearServer != nil {
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
                        detail: "Claude Desktop already has a Bear stdio server entry pointing at the stable app-managed CLI path.",
                        snippetTitle: "Current recommended JSON",
                        snippetLanguage: "json",
                        snippet: snippet,
                        mergeNote: "No change is needed unless you want to refresh the app-managed CLI copy from Bear MCP.app.",
                        checks: checks
                    ),
                    doctorCheck: BearDoctorCheck(
                        key: "host-claude-desktop",
                        value: configURL.path,
                        status: .ok,
                        detail: "configured to launch Bear MCP from the app-managed CLI path"
                    )
                )
            }

            let detail = if !commandMatches {
                "Claude Desktop already has a Bear entry, but `command` is not `\(cliPath)` yet."
            } else if !argsMatch {
                "Claude Desktop already has a Bear entry, but `args` does not include `\"mcp\"` yet."
            } else if !typeMatches {
                "Claude Desktop already has a Bear entry, but it is not marked as a stdio server."
            } else {
                "Claude Desktop already has a Bear entry, but it does not match the current recommended shape."
            }

            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "claude-desktop",
                    appName: "Claude Desktop",
                    configPath: configURL.path,
                    status: .invalid,
                    statusTitle: "Needs update",
                    detail: detail,
                    snippetTitle: "Update the Bear server entry to",
                    snippetLanguage: "json",
                    snippet: snippet,
                    mergeNote: "Replace only the existing `bear` object inside `mcpServers`; keep any other configured Claude servers.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-claude-desktop",
                    value: configURL.path,
                    status: .invalid,
                    detail: "Bear entry detected, but it is not aligned with the stable CLI path at \(cliPath)"
                )
            )
        }

        return HostAppResult(
            setup: BearHostAppSetupSnapshot(
                id: "claude-desktop",
                appName: "Claude Desktop",
                configPath: configURL.path,
                status: .notConfigured,
                statusTitle: "Bear MCP not added yet",
                detail: "Claude Desktop config exists, but no `mcpServers.bear` entry was detected.",
                snippetTitle: "Add this Bear server object",
                snippetLanguage: "json",
                snippet: snippet,
                mergeNote: "Merge the `bear` object into the existing `mcpServers` dictionary rather than replacing the entire file.",
                checks: checks
            ),
            doctorCheck: BearDoctorCheck(
                key: "host-claude-desktop",
                value: configURL.path,
                status: .notConfigured,
                detail: "claude_desktop_config.json exists, but no Bear MCP server entry was detected"
            )
        )
    }

    private static func chatGPTResult() -> HostAppResult {
        let checks = [
            "Do not point ChatGPT at the local app-managed CLI path; current ChatGPT MCP support is remote-only.",
            "If you want Bear in ChatGPT, deploy a remote MCP server over streaming HTTP or SSE instead of using the local stdio binary.",
            "Use Bear MCP.app for local host apps like Codex and Claude Desktop, and treat ChatGPT as a separate remote-connector path for now.",
        ]

        return HostAppResult(
            setup: BearHostAppSetupSnapshot(
                id: "chatgpt",
                appName: "ChatGPT",
                status: .notConfigured,
                statusTitle: "Remote MCP only",
                detail: "ChatGPT developer mode currently supports remote MCP servers, not local stdio binaries, so the app-managed CLI path is not the right integration target here.",
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
