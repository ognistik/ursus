import BearCore
import Foundation

public enum BearHostAppIntegrationState: String, Codable, Hashable, Sendable {
    case installNeeded
    case installed
    case repairNeeded

    init(status: BearDoctorCheckStatus) {
        switch status {
        case .ok, .configured:
            self = .installed
        case .invalid, .failed:
            self = .repairNeeded
        case .missing, .notConfigured:
            self = .installNeeded
        }
    }
}

public enum BearHostAppPrimaryAction: String, Codable, Hashable, Sendable {
    case install
    case repair

    public var title: String {
        switch self {
        case .install:
            return "Install"
        case .repair:
            return "Repair"
        }
    }
}

public struct BearHostAppSetupSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let appName: String
    public let configPath: String?
    public let presentInSetup: Bool
    public let integrationState: BearHostAppIntegrationState
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
        presentInSetup: Bool = true,
        integrationState: BearHostAppIntegrationState? = nil,
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
        self.presentInSetup = presentInSetup
        self.integrationState = integrationState ?? BearHostAppIntegrationState(status: status)
        self.status = status
        self.statusTitle = statusTitle
        self.detail = detail
        self.snippetTitle = snippetTitle
        self.snippetLanguage = snippetLanguage
        self.snippet = snippet
        self.mergeNote = mergeNote
        self.checks = checks
    }

    public var primaryAction: BearHostAppPrimaryAction? {
        switch integrationState {
        case .installNeeded:
            return .install
        case .repairNeeded:
            return .repair
        case .installed:
            return nil
        }
    }
}

enum BearHostAppSupport {
    static func loadSetups(
        fileManager: FileManager = .default,
        launcherURL: URL = UrsusCLILocator.publicLauncherURL,
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
        launcherURL: URL = UrsusCLILocator.publicLauncherURL,
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
            claudeCLIResult(fileManager: fileManager, launcherURL: launcherURL, homeDirectoryURL: homeDirectoryURL),
            chatGPTResult(),
        ]
    }

    static func installIntegration(
        id: String,
        fileManager: FileManager,
        launcherURL: URL,
        homeDirectoryURL: URL
    ) throws {
        switch id {
        case "codex":
            try installCodexIntegration(
                fileManager: fileManager,
                launcherURL: launcherURL,
                homeDirectoryURL: homeDirectoryURL
            )
        case "claude-desktop":
            try installClaudeDesktopIntegration(
                fileManager: fileManager,
                launcherURL: launcherURL,
                homeDirectoryURL: homeDirectoryURL
            )
        case "claude-cli":
            try installClaudeCLIIntegration(
                fileManager: fileManager,
                launcherURL: launcherURL,
                homeDirectoryURL: homeDirectoryURL
            )
        default:
            throw BearError.unsupported("Ursus does not support one-click setup for this app yet.")
        }
    }

    static func removeIntegration(
        id: String,
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) throws {
        switch id {
        case "codex":
            try removeCodexIntegration(
                fileManager: fileManager,
                homeDirectoryURL: homeDirectoryURL
            )
        case "claude-desktop":
            try removeClaudeDesktopIntegration(
                fileManager: fileManager,
                homeDirectoryURL: homeDirectoryURL
            )
        case "claude-cli":
            try removeClaudeCLIIntegration(
                fileManager: fileManager,
                homeDirectoryURL: homeDirectoryURL
            )
        default:
            throw BearError.unsupported("Ursus does not support removing this app integration yet.")
        }
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
                    presentInSetup: false,
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
                presentInSetup: false,
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
        let isDetected = codexIsDetected(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        )
        let configURL = homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
        let cliPath = launcherURL.path
        let snippet = codexSnippet(forLauncherPath: cliPath)
        let launcherIsReady = launcherReady(fileManager: fileManager, launcherURL: launcherURL)
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
                    presentInSetup: isDetected,
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
                    presentInSetup: isDetected,
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
        let hasStablePath = contents.contains("command = \"\(cliPath)\"")
        let hasMCPArgs = contents.range(
            of: #"args\s*=\s*\[[^\]]*"mcp"[^\]]*\]"#,
            options: .regularExpression
        ) != nil

        if hasUrsusSection && hasStablePath && hasMCPArgs {
            if !launcherIsReady {
                return HostAppResult(
                    setup: BearHostAppSetupSnapshot(
                        id: "codex",
                        appName: "Codex",
                        configPath: configURL.path,
                        presentInSetup: isDetected,
                        status: .invalid,
                        statusTitle: "Needs update",
                        detail: "Codex points at the Ursus launcher path, but the launcher is not installed or executable yet.",
                        snippetTitle: "Current recommended section",
                        snippetLanguage: "toml",
                        snippet: snippet,
                        mergeNote: "Repair the launcher from Ursus.app so Codex can launch Ursus again.",
                        checks: checks
                    ),
                    doctorCheck: BearDoctorCheck(
                        key: "host-codex",
                        value: configURL.path,
                        status: .invalid,
                        detail: "configured entry found, but the public launcher at \(cliPath) is unavailable"
                    )
                )
            }

            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "codex",
                    appName: "Codex",
                    configPath: configURL.path,
                    presentInSetup: isDetected,
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
                    presentInSetup: isDetected,
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
                    detail: "`ursus` entry detected, but it is not aligned with the public launcher path at \(cliPath)"
                )
            )
        }

        return HostAppResult(
            setup: BearHostAppSetupSnapshot(
                id: "codex",
                appName: "Codex",
                configPath: configURL.path,
                presentInSetup: isDetected,
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
        let isDetected = claudeDesktopIsDetected(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        )
        let configURL = claudeDesktopConfigURL(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        )
        let cliPath = launcherURL.path
        let snippet = claudeJSONSnippet(forLauncherPath: cliPath)
        let launcherIsReady = launcherReady(fileManager: fileManager, launcherURL: launcherURL)
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
                    presentInSetup: isDetected,
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
                    presentInSetup: isDetected,
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
        let command = ursusServer?["command"] as? String
        let args = ursusServer?["args"] as? [String] ?? []
        let transportType = ursusServer?["type"] as? String

        if ursusServer != nil {
            let commandMatches = command == cliPath
            let argsMatch = args.contains("mcp")
            let typeMatches = transportType == nil || transportType == "stdio"

            if commandMatches && argsMatch && typeMatches {
                if !launcherIsReady {
                    return HostAppResult(
                        setup: BearHostAppSetupSnapshot(
                            id: "claude-desktop",
                            appName: "Claude Desktop",
                            configPath: configURL.path,
                            presentInSetup: isDetected,
                            status: .invalid,
                            statusTitle: "Needs update",
                            detail: "Claude Desktop points at the Ursus launcher path, but the launcher is not installed or executable yet.",
                            snippetTitle: "Current recommended JSON",
                            snippetLanguage: "json",
                            snippet: snippet,
                            mergeNote: "Repair the launcher from Ursus.app so Claude Desktop can launch Ursus again.",
                            checks: checks
                        ),
                        doctorCheck: BearDoctorCheck(
                            key: "host-claude-desktop",
                            value: configURL.path,
                            status: .invalid,
                            detail: "configured entry found, but the public launcher at \(cliPath) is unavailable"
                        )
                    )
                }

                return HostAppResult(
                    setup: BearHostAppSetupSnapshot(
                        id: "claude-desktop",
                        appName: "Claude Desktop",
                        configPath: configURL.path,
                        presentInSetup: isDetected,
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
                    presentInSetup: isDetected,
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
                    detail: "`ursus` entry detected, but it is not aligned with the public launcher path at \(cliPath)"
                )
            )
        }

        return HostAppResult(
            setup: BearHostAppSetupSnapshot(
                id: "claude-desktop",
                appName: "Claude Desktop",
                configPath: configURL.path,
                presentInSetup: isDetected,
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

    private static func claudeCLIResult(
        fileManager: FileManager,
        launcherURL: URL,
        homeDirectoryURL: URL
    ) -> HostAppResult {
        let isDetected = claudeCLIIsDetected(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        )
        let configURL = claudeCLIConfigURL(homeDirectoryURL: homeDirectoryURL)
        let cliPath = launcherURL.path
        let snippet = claudeJSONSnippet(forLauncherPath: cliPath)
        let launcherIsReady = launcherReady(fileManager: fileManager, launcherURL: launcherURL)
        let checks = [
            "Use Ursus.app to install or repair the launcher at \(cliPath).",
            "Add or merge the `ursus` server entry into `mcpServers` inside `\(configURL.path)` so Claude CLI can launch Ursus across your projects.",
            "Restart Claude CLI sessions after saving so new shells pick up the Ursus MCP server.",
        ]

        guard fileManager.fileExists(atPath: configURL.path) else {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "claude-cli",
                    appName: "Claude CLI",
                    configPath: configURL.path,
                    presentInSetup: isDetected,
                    status: .missing,
                    statusTitle: "Config file not found",
                    detail: "Create `\(configURL.path)` or let Claude CLI create it, then add the Ursus entry below.",
                    snippetTitle: "Claude CLI JSON example",
                    snippetLanguage: "json",
                    snippet: snippet,
                    mergeNote: "If the file already contains other Claude CLI settings, merge only the `ursus` object into `mcpServers`.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-claude-cli",
                    value: configURL.path,
                    status: .missing,
                    detail: ".claude.json not found; add an `ursus` stdio entry pointing at \(cliPath)"
                )
            )
        }

        guard
            let data = fileManager.contents(atPath: configURL.path),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "claude-cli",
                    appName: "Claude CLI",
                    configPath: configURL.path,
                    presentInSetup: isDetected,
                    status: .invalid,
                    statusTitle: "Config file invalid",
                    detail: "`\(configURL.path)` could not be parsed as JSON. Fix the file, then merge the Ursus stdio entry below.",
                    snippetTitle: "Claude CLI JSON example",
                    snippetLanguage: "json",
                    snippet: snippet,
                    mergeNote: "The file needs to stay valid JSON after you add the Ursus server object.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-claude-cli",
                    value: configURL.path,
                    status: .invalid,
                    detail: ".claude.json exists but is not valid JSON"
                )
            )
        }

        let mcpServers = root["mcpServers"] as? [String: Any]
        let ursusServer = mcpServers?["ursus"] as? [String: Any]
        let command = ursusServer?["command"] as? String
        let args = ursusServer?["args"] as? [String] ?? []
        let transportType = ursusServer?["type"] as? String

        if ursusServer != nil {
            let commandMatches = command == cliPath
            let argsMatch = args.contains("mcp")
            let typeMatches = transportType == nil || transportType == "stdio"

            if commandMatches && argsMatch && typeMatches {
                if !launcherIsReady {
                    return HostAppResult(
                        setup: BearHostAppSetupSnapshot(
                            id: "claude-cli",
                            appName: "Claude CLI",
                            configPath: configURL.path,
                            presentInSetup: isDetected,
                            status: .invalid,
                            statusTitle: "Needs update",
                            detail: "Claude CLI points at the Ursus launcher path, but the launcher is not installed or executable yet.",
                            snippetTitle: "Current recommended JSON",
                            snippetLanguage: "json",
                            snippet: snippet,
                            mergeNote: "Repair the launcher from Ursus.app so Claude CLI can launch Ursus again.",
                            checks: checks
                        ),
                        doctorCheck: BearDoctorCheck(
                            key: "host-claude-cli",
                            value: configURL.path,
                            status: .invalid,
                            detail: "configured entry found, but the public launcher at \(cliPath) is unavailable"
                        )
                    )
                }

                return HostAppResult(
                    setup: BearHostAppSetupSnapshot(
                        id: "claude-cli",
                        appName: "Claude CLI",
                        configPath: configURL.path,
                        presentInSetup: isDetected,
                        status: .ok,
                        statusTitle: "Configured",
                        detail: "Claude CLI already has an Ursus stdio server entry pointing at the public launcher path.",
                        snippetTitle: "Current recommended JSON",
                        snippetLanguage: "json",
                        snippet: snippet,
                        mergeNote: "No change is needed unless you want to repair the public launcher from Ursus.app.",
                        checks: checks
                    ),
                    doctorCheck: BearDoctorCheck(
                        key: "host-claude-cli",
                        value: configURL.path,
                        status: .ok,
                        detail: "configured to launch Ursus from the public launcher path"
                    )
                )
            }

            let detail = if !commandMatches {
                "Claude CLI already has an Ursus entry, but `command` is not `\(cliPath)` yet."
            } else if !argsMatch {
                "Claude CLI already has an Ursus entry, but `args` does not include `\"mcp\"` yet."
            } else if !typeMatches {
                "Claude CLI already has an Ursus entry, but it is not marked as a stdio server."
            } else {
                "Claude CLI already has an Ursus entry, but it does not match the current recommended shape."
            }

            return HostAppResult(
                setup: BearHostAppSetupSnapshot(
                    id: "claude-cli",
                    appName: "Claude CLI",
                    configPath: configURL.path,
                    presentInSetup: isDetected,
                    status: .invalid,
                    statusTitle: "Needs update",
                    detail: detail,
                    snippetTitle: "Update the Ursus server entry to",
                    snippetLanguage: "json",
                    snippet: snippet,
                    mergeNote: "Replace only the existing `ursus` object inside `mcpServers`; keep any other Claude CLI settings.",
                    checks: checks
                ),
                doctorCheck: BearDoctorCheck(
                    key: "host-claude-cli",
                    value: configURL.path,
                    status: .invalid,
                    detail: "`ursus` entry detected, but it is not aligned with the public launcher path at \(cliPath)"
                )
            )
        }

        return HostAppResult(
            setup: BearHostAppSetupSnapshot(
                id: "claude-cli",
                appName: "Claude CLI",
                configPath: configURL.path,
                presentInSetup: isDetected,
                status: .notConfigured,
                statusTitle: "Ursus Server Not Added Yet",
                detail: "Claude CLI config exists, but no `mcpServers.ursus` entry was detected.",
                snippetTitle: "Add this `ursus` server object",
                snippetLanguage: "json",
                snippet: snippet,
                mergeNote: "Merge the `ursus` object into the existing `mcpServers` dictionary rather than replacing the entire file.",
                checks: checks
            ),
            doctorCheck: BearDoctorCheck(
                key: "host-claude-cli",
                value: configURL.path,
                status: .notConfigured,
                detail: ".claude.json exists, but no `ursus` server entry was detected"
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
                presentInSetup: false,
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

    private static func codexIsDetected(
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) -> Bool {
        if fileManager.fileExists(
            atPath: homeDirectoryURL
                .appendingPathComponent(".codex", isDirectory: true)
                .path
        ) {
            return true
        }

        return applicationExists(
            named: ["Codex.app"],
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        )
    }

    private static func claudeDesktopIsDetected(
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) -> Bool {
        let supportDirectories = claudeDesktopConfigCandidateURLs(homeDirectoryURL: homeDirectoryURL)
            .map { $0.deletingLastPathComponent() }

        if supportDirectories.contains(where: { fileManager.fileExists(atPath: $0.path) }) {
            return true
        }

        return applicationExists(
            named: ["Claude.app", "Claude Desktop.app"],
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        )
    }

    private static func claudeCLIIsDetected(
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) -> Bool {
        let configURL = claudeCLIConfigURL(homeDirectoryURL: homeDirectoryURL)
        let cliDirectoryURL = homeDirectoryURL.appendingPathComponent(".claude", isDirectory: true)

        if fileManager.fileExists(atPath: configURL.path) || fileManager.fileExists(atPath: cliDirectoryURL.path) {
            return true
        }

        return claudeCLIExecutableURL(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        ) != nil
    }

    private static func applicationExists(
        named appNames: [String],
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) -> Bool {
        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectoryURL.appendingPathComponent("Applications", isDirectory: true),
        ]

        for root in applicationRoots {
            for appName in appNames {
                let candidatePath = root.appendingPathComponent(appName, isDirectory: true).path
                if fileManager.fileExists(atPath: candidatePath) {
                    return true
                }
            }
        }

        return false
    }

    private static func installCodexIntegration(
        fileManager: FileManager,
        launcherURL: URL,
        homeDirectoryURL: URL
    ) throws {
        let configURL = homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let existingContents = fileManager.fileExists(atPath: configURL.path)
            ? try String(contentsOf: configURL, encoding: .utf8)
            : ""
        let strippedContents = removingCodexSection(from: existingContents)
        let snippet = codexSnippet(forLauncherPath: launcherURL.path)
        let trimmed = strippedContents.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedContents = trimmed.isEmpty ? "\(snippet)\n" : "\(trimmed)\n\n\(snippet)\n"

        if fileManager.fileExists(atPath: configURL.path), existingContents != updatedContents {
            try backupConfigFile(at: configURL, fileManager: fileManager)
        }

        try updatedContents.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func removeCodexIntegration(
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) throws {
        let configURL = homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)

        guard fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        let existingContents = try String(contentsOf: configURL, encoding: .utf8)
        let strippedContents = removingCodexSection(from: existingContents)
        let trimmed = strippedContents.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContents = trimmed.isEmpty ? "" : "\(trimmed)\n"

        if existingContents != finalContents {
            try backupConfigFile(at: configURL, fileManager: fileManager)
        }

        try finalContents.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func installClaudeDesktopIntegration(
        fileManager: FileManager,
        launcherURL: URL,
        homeDirectoryURL: URL
    ) throws {
        let configURL = claudeDesktopConfigURL(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        )
        try upsertJSONIntegration(
            at: configURL,
            fileManager: fileManager,
            launcherPath: launcherURL.path
        )
    }

    private static func removeClaudeDesktopIntegration(
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) throws {
        try removeJSONIntegration(
            at: claudeDesktopConfigURL(
                fileManager: fileManager,
                homeDirectoryURL: homeDirectoryURL
            ),
            fileManager: fileManager
        )
    }

    private static func installClaudeCLIIntegration(
        fileManager: FileManager,
        launcherURL: URL,
        homeDirectoryURL: URL
    ) throws {
        try upsertJSONIntegration(
            at: claudeCLIConfigURL(homeDirectoryURL: homeDirectoryURL),
            fileManager: fileManager,
            launcherPath: launcherURL.path
        )
    }

    private static func removeClaudeCLIIntegration(
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) throws {
        try removeJSONIntegration(
            at: claudeCLIConfigURL(homeDirectoryURL: homeDirectoryURL),
            fileManager: fileManager
        )
    }

    private static func codexSnippet(forLauncherPath launcherPath: String) -> String {
        """
        [mcp_servers.ursus]
        enabled = true
        command = "\(launcherPath)"
        args = ["mcp"]
        """
    }

    private static func claudeJSONSnippet(forLauncherPath launcherPath: String) -> String {
        """
        {
          "mcpServers": {
            "ursus": {
              "type": "stdio",
              "command": "\(launcherPath)",
              "args": ["mcp"],
              "env": {}
            }
          }
        }
        """
    }

    private static func launcherReady(
        fileManager: FileManager,
        launcherURL: URL
    ) -> Bool {
        fileManager.fileExists(atPath: launcherURL.path) && fileManager.isExecutableFile(atPath: launcherURL.path)
    }

    private static func claudeDesktopConfigCandidateURLs(homeDirectoryURL: URL) -> [URL] {
        [
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
    }

    private static func claudeDesktopConfigURL(
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) -> URL {
        let candidateURLs = claudeDesktopConfigCandidateURLs(homeDirectoryURL: homeDirectoryURL)
        return candidateURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) ?? candidateURLs[0]
    }

    private static func claudeCLIConfigURL(homeDirectoryURL: URL) -> URL {
        homeDirectoryURL
            .appendingPathComponent(".claude.json", isDirectory: false)
    }

    private static func claudeCLIExecutableURL(
        fileManager: FileManager,
        homeDirectoryURL: URL
    ) -> URL? {
        let environmentPaths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let commonPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            homeDirectoryURL
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .path,
            homeDirectoryURL
                .appendingPathComponent(".npm-global", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .path,
        ]

        for directory in Array(Set(commonPaths + environmentPaths)) {
            let candidateURL = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("claude", isDirectory: false)
            if fileManager.fileExists(atPath: candidateURL.path), fileManager.isExecutableFile(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    private static func removingCodexSection(from contents: String) -> String {
        let targetHeaders: Set<String> = [
            "[mcp_servers.ursus]",
            "[mcp_servers.\"ursus\"]",
        ]

        let lines = contents.components(separatedBy: .newlines)
        var keptLines: [String] = []
        var skippingTargetSection = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let isTableHeader = trimmedLine.hasPrefix("[") && trimmedLine.hasSuffix("]")

            if targetHeaders.contains(trimmedLine) {
                skippingTargetSection = true
                continue
            }

            if skippingTargetSection && isTableHeader {
                skippingTargetSection = false
            }

            if !skippingTargetSection {
                keptLines.append(line)
            }
        }

        return keptLines.joined(separator: "\n")
    }

    private static func upsertJSONIntegration(
        at configURL: URL,
        fileManager: FileManager,
        launcherPath: String
    ) throws {
        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var rootObject = try loadJSONObjectResettingInvalidConfigIfNeeded(
            at: configURL,
            fileManager: fileManager
        )
        var mcpServers = rootObject["mcpServers"] as? [String: Any] ?? [:]
        mcpServers["ursus"] = [
            "type": "stdio",
            "command": launcherPath,
            "args": ["mcp"],
            "env": [String: String](),
        ]
        rootObject["mcpServers"] = mcpServers

        try writeJSONObject(rootObject, to: configURL)
    }

    private static func removeJSONIntegration(
        at configURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        var rootObject = try loadJSONObjectResettingInvalidConfigIfNeeded(
            at: configURL,
            fileManager: fileManager
        )
        var mcpServers = rootObject["mcpServers"] as? [String: Any] ?? [:]
        mcpServers.removeValue(forKey: "ursus")

        if mcpServers.isEmpty {
            rootObject.removeValue(forKey: "mcpServers")
        } else {
            rootObject["mcpServers"] = mcpServers
        }

        try writeJSONObject(rootObject, to: configURL)
    }

    private static func loadJSONObjectResettingInvalidConfigIfNeeded(
        at configURL: URL,
        fileManager: FileManager
    ) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: configURL)
        guard !data.isEmpty else {
            return [:]
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }

        try backupConfigFile(at: configURL, fileManager: fileManager)
        return [:]
    }

    private static func writeJSONObject(
        _ object: [String: Any],
        to url: URL
    ) throws {
        let normalizedObject: Any = object.isEmpty ? [:] : object
        let data = try JSONSerialization.data(
            withJSONObject: normalizedObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        var rendered = String(decoding: data, as: UTF8.self)
        rendered.append("\n")
        try rendered.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func backupConfigFile(
        at configURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        let backupURL = URL(fileURLWithPath: "\(configURL.path).backup-\(UUID().uuidString)")
        try? fileManager.removeItem(at: backupURL)
        try fileManager.copyItem(at: configURL, to: backupURL)
    }

}

private struct HostAppResult {
    let setup: BearHostAppSetupSnapshot
    let doctorCheck: BearDoctorCheck?
}
