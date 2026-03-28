import BearApplication
import BearCore
import BearXCallback
import Foundation
import Testing

private final class TestSelectedNoteTokenStore: BearSelectedNoteTokenStore, @unchecked Sendable {
    var storedToken: String?
    var readError: Error?

    init(storedToken: String? = nil, readError: Error? = nil) {
        self.storedToken = storedToken
        self.readError = readError
    }

    func readToken() throws -> String? {
        if let readError {
            throw readError
        }
        return storedToken
    }

    func saveToken(_ token: String) throws {
        storedToken = token
    }

    func removeToken() throws {
        storedToken = nil
    }
}

@Test
func dashboardSnapshotIncludesSettingsWhenConfigurationLoads() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let homeDirectoryURL = tempRoot.appendingPathComponent("home", isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appManagedCLIURL = tempRoot
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try """
    {
      "databasePath" : "/tmp/bear.sqlite",
      "inboxTags" : [
        "0-inbox",
        "next"
      ],
      "createAddsInboxTagsByDefault" : false,
      "token" : "phase-two-token"
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(),
        appManagedCLIURL: appManagedCLIURL,
        homeDirectoryURL: homeDirectoryURL,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings != nil)
    #expect(dashboard.settingsError == nil)
    #expect(dashboard.settings?.databasePath == "/tmp/bear.sqlite")
    #expect(dashboard.settings?.inboxTags == ["0-inbox", "next"])
    #expect(dashboard.settings?.createAddsInboxTagsByDefault == false)
    #expect(dashboard.settings?.appManagedCLIPath == appManagedCLIURL.path)
    #expect(dashboard.settings?.appManagedCLIStatus == .missing)
    #expect(dashboard.settings?.appManagedCLIStatusTitle == "Not installed")
    #expect(dashboard.settings?.cliMaintenancePrompt?.actions == [.installAppManagedCLI])
    #expect(dashboard.settings?.selectedNoteTokenConfigured == true)
    #expect(dashboard.settings?.selectedNoteTokenStoredInKeychain == false)
    #expect(dashboard.settings?.selectedNoteLegacyConfigTokenDetected == true)
    #expect(dashboard.settings?.selectedNoteTokenStorageDescription == "Legacy config.json fallback")
    let bundledCLIDiagnostic = try #require(diagnostic(named: "bundled-cli", in: dashboard.diagnostics))
    #expect(bundledCLIDiagnostic.status == .missing)
    #expect(bundledCLIDiagnostic.detail == BearMCPCLILocator.bundledExecutableGuidance)
    let appManagedCLIDiagnostic = try #require(diagnostic(named: "app-managed-cli", in: dashboard.diagnostics))
    #expect(appManagedCLIDiagnostic.status == .missing)
    #expect(appManagedCLIDiagnostic.value == appManagedCLIURL.path)
    #expect(appManagedCLIDiagnostic.detail == "Install the host CLI once so local MCP apps can launch Bear MCP from a stable path.")
    #expect(dashboard.settings?.appManagedCLIStatusDetail == "Install the host CLI once so local MCP apps can launch Bear MCP from a stable path.")
    #expect(dashboard.diagnostics.contains(where: {
        $0.key == "selected-note-token"
            && $0.value == "Legacy config.json fallback"
            && ($0.detail?.contains("Import it into Keychain") ?? false)
    }))
    #expect(dashboard.diagnostics.contains(where: {
        $0.key == "selected-note-callback-app"
            && $0.status == .missing
            && ($0.detail?.contains("install `Bear MCP.app` in `/Applications/Bear MCP.app` (preferred).") ?? false)
            && ($0.detail?.contains("fully supported for user-specific installs") ?? false)
    }))
    #expect(!dashboard.diagnostics.contains(where: { $0.key == "selected-note-helper-fallback" }))
}

@Test
func dashboardSnapshotIncludesPreferredAppAndStandaloneHelperDiagnostics() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appBundleURL = tempRoot.appendingPathComponent("Bear MCP.app", isDirectory: true)
    let helperBundleURL = tempRoot.appendingPathComponent("Bear MCP Helper.app", isDirectory: true)
    let appManagedCLIURL = tempRoot.appendingPathComponent("installed", isDirectory: true).appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: appBundleURL.appendingPathComponent("Contents/Resources/bin", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: helperBundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: appManagedCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(
        to: appBundleURL.appendingPathComponent("Contents/Resources/bin/bear-mcp", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
    try fileManager.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: appBundleURL.appendingPathComponent("Contents/Resources/bin/bear-mcp", isDirectory: false).path
    )
    try "#!/bin/sh\nexit 0\n".write(to: appManagedCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appManagedCLIURL.path)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(storedToken: "keychain-token"),
        allowSecureTokenStatusRead: true,
        currentAppBundleURL: appBundleURL,
        appManagedCLIURL: appManagedCLIURL,
        bundledCLIExecutableURLResolver: { bundleURL, _ in
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("bear-mcp", isDirectory: false)
        },
        callbackAppBundleURLProvider: { _ in appBundleURL },
        callbackAppExecutableURLResolver: { bundleURL, _ in
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("Bear MCP", isDirectory: false)
        },
        helperBundleURLProvider: { _ in helperBundleURL },
        helperExecutableURLResolver: { bundleURL, _ in
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("bear-mcp-helper", isDirectory: false)
        }
    )

    let preferredAppDiagnostic = try #require(diagnostic(named: "selected-note-callback-app", in: dashboard.diagnostics))
    #expect(preferredAppDiagnostic.status == .ok)
    #expect(preferredAppDiagnostic.value == appBundleURL.path)
    #expect(preferredAppDiagnostic.detail == "detected install location; preferred host -> \(appBundleURL.path)/Contents/MacOS/Bear MCP")

    let bundledCLIDiagnostic = try #require(diagnostic(named: "bundled-cli", in: dashboard.diagnostics))
    #expect(bundledCLIDiagnostic.status == .ok)
    #expect(bundledCLIDiagnostic.value == "\(appBundleURL.path)/Contents/Resources/bin/bear-mcp")
    #expect(bundledCLIDiagnostic.detail == "embedded in \(appBundleURL.path)")

    let appManagedCLIDiagnostic = try #require(diagnostic(named: "app-managed-cli", in: dashboard.diagnostics))
    #expect(appManagedCLIDiagnostic.status == .ok)
    #expect(appManagedCLIDiagnostic.value == appManagedCLIURL.path)
    #expect(appManagedCLIDiagnostic.detail == "Local MCP apps should use this stable path.")
    #expect(dashboard.settings?.appManagedCLIStatus == .ok)
    #expect(dashboard.settings?.appManagedCLIStatusTitle == "Installed")
    #expect(dashboard.settings?.appManagedCLIStatusDetail == "Local MCP apps should use this stable path.")
    #expect(dashboard.settings?.cliMaintenancePrompt == nil)

    let helperFallbackDiagnostic = try #require(diagnostic(named: "selected-note-helper-fallback", in: dashboard.diagnostics))
    #expect(helperFallbackDiagnostic.status == .ok)
    #expect(helperFallbackDiagnostic.value == helperBundleURL.path)
    #expect(helperFallbackDiagnostic.detail == "helper fallback; detected install location -> \(helperBundleURL.path)/Contents/MacOS/bear-mcp-helper")
}

@Test
func dashboardSnapshotIncludesHostAppSetupGuidanceForCodexClaudeAndChatGPT() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let homeDirectoryURL = tempRoot.appendingPathComponent("home", isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appManagedCLIURL = tempRoot
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let codexConfigURL = homeDirectoryURL
        .appendingPathComponent(".codex", isDirectory: true)
        .appendingPathComponent("config.toml", isDirectory: false)
    let claudeConfigURL = homeDirectoryURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Claude", isDirectory: true)
        .appendingPathComponent("claude_desktop_config.json", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: codexConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: claudeConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: appManagedCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(to: appManagedCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appManagedCLIURL.path)
    try """
    [mcp_servers.bear]
    enabled = true
    command = "\(appManagedCLIURL.path)"
    args = ["mcp"]
    """.write(to: codexConfigURL, atomically: true, encoding: .utf8)
    try """
    {
      "mcpServers": {
        "bear": {
          "type": "stdio",
          "command": "\(appManagedCLIURL.path)",
          "args": ["mcp"],
          "env": {}
        }
      }
    }
    """.write(to: claudeConfigURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(),
        appManagedCLIURL: appManagedCLIURL,
        terminalCLIURL: tempRoot.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("bear-mcp", isDirectory: false),
        homeDirectoryURL: homeDirectoryURL,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    let genericSetup = try #require(hostSetup(named: "generic-local-stdio", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(genericSetup.status == .ok)
    #expect(genericSetup.statusTitle == "Ready")
    #expect(genericSetup.snippet?.contains(appManagedCLIURL.path) == true)

    let codexSetup = try #require(hostSetup(named: "codex", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(codexSetup.status == .ok)
    #expect(codexSetup.statusTitle == "Configured")
    #expect(codexSetup.configPath == codexConfigURL.path)
    #expect(codexSetup.snippet?.contains(appManagedCLIURL.path) == true)

    let claudeSetup = try #require(hostSetup(named: "claude-desktop", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(claudeSetup.status == .ok)
    #expect(claudeSetup.statusTitle == "Configured")
    #expect(claudeSetup.configPath == claudeConfigURL.path)
    #expect(claudeSetup.snippet?.contains("\"type\": \"stdio\"") == true)

    let chatGPTSetup = try #require(hostSetup(named: "chatgpt", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(chatGPTSetup.status == .notConfigured)
    #expect(chatGPTSetup.statusTitle == "Remote MCP only")
    #expect(chatGPTSetup.snippet == nil)
    #expect(chatGPTSetup.detail.contains("remote MCP servers"))

    let codexDiagnostic = try #require(diagnostic(named: "host-codex", in: dashboard.diagnostics))
    #expect(codexDiagnostic.status == .ok)
    #expect(codexDiagnostic.value == codexConfigURL.path)

    let claudeDiagnostic = try #require(diagnostic(named: "host-claude-desktop", in: dashboard.diagnostics))
    #expect(claudeDiagnostic.status == .ok)
    #expect(claudeDiagnostic.value == claudeConfigURL.path)

    let chatGPTDiagnostic = try #require(diagnostic(named: "host-chatgpt", in: dashboard.diagnostics))
    #expect(chatGPTDiagnostic.status == .notConfigured)
    #expect(chatGPTDiagnostic.value == "remote MCP only")

    let genericDiagnostic = try #require(diagnostic(named: "host-local-stdio", in: dashboard.diagnostics))
    #expect(genericDiagnostic.status == .ok)
    #expect(genericDiagnostic.value == appManagedCLIURL.path)
}

@Test
func dashboardSnapshotReportsCopiedTerminalCLIStatus() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appManagedCLIURL = tempRoot
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let terminalCLIURL = tempRoot
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: appManagedCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: terminalCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\necho current\n".write(to: appManagedCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appManagedCLIURL.path)
    try "#!/bin/sh\necho current\n".write(to: terminalCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: terminalCLIURL.path)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(),
        appManagedCLIURL: appManagedCLIURL,
        terminalCLIURL: terminalCLIURL,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings?.terminalCLIPath == terminalCLIURL.path)
    #expect(dashboard.settings?.terminalCLIStatus == .ok)
    #expect(dashboard.settings?.terminalCLIStatusTitle == "Installed")
    #expect(dashboard.settings?.terminalCLIStatusDetail == "Optional copy for running `bear-mcp` directly from Terminal.")
    #expect(dashboard.settings?.cliMaintenancePrompt == nil)
    let terminalDiagnostic = try #require(diagnostic(named: "terminal-cli", in: dashboard.diagnostics))
    #expect(terminalDiagnostic.status == .ok)
    #expect(terminalDiagnostic.value == terminalCLIURL.path)
}

@Test
func dashboardSnapshotFlagsOlderTerminalInstallForRefresh() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appManagedCLIURL = tempRoot
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let terminalCLIURL = tempRoot
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: appManagedCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: terminalCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\necho current\n".write(to: appManagedCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appManagedCLIURL.path)
    try fileManager.createSymbolicLink(at: terminalCLIURL, withDestinationURL: appManagedCLIURL)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(),
        appManagedCLIURL: appManagedCLIURL,
        terminalCLIURL: terminalCLIURL,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings?.terminalCLIStatus == .invalid)
    #expect(dashboard.settings?.terminalCLIStatusTitle == "Needs refresh")
    #expect(dashboard.settings?.terminalCLIStatusDetail == "This Terminal command came from an older Bear MCP setup. Refresh it only if you use Bear MCP from Terminal.")
    #expect(dashboard.settings?.cliMaintenancePrompt?.title == "Refresh the Terminal command")
    #expect(dashboard.settings?.cliMaintenancePrompt?.actions == [.refreshTerminalCLI])
}

@Test
func dashboardSnapshotFlagsStaleAppManagedCLIForRefresh() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appBundleURL = tempRoot.appendingPathComponent("Bear MCP.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let appManagedCLIURL = tempRoot
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: appManagedCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    try "#!/bin/sh\necho stale\n".write(to: appManagedCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appManagedCLIURL.path)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(),
        currentAppBundleURL: appBundleURL,
        appManagedCLIURL: appManagedCLIURL,
        bundledCLIExecutableURLResolver: { bundleURL, _ in
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("bear-mcp", isDirectory: false)
        },
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    let appManagedCLIDiagnostic = try #require(diagnostic(named: "app-managed-cli", in: dashboard.diagnostics))
    #expect(appManagedCLIDiagnostic.status == .invalid)
    #expect(appManagedCLIDiagnostic.detail == "This host CLI is older than the one bundled in the current app build. Refresh it from this app.")
    #expect(dashboard.settings?.appManagedCLIStatus == .invalid)
    #expect(dashboard.settings?.appManagedCLIStatusTitle == "Needs refresh")
    #expect(dashboard.settings?.appManagedCLIStatusDetail == "This host CLI is older than the one bundled in the current app build. Refresh it from this app.")
    #expect(dashboard.settings?.cliMaintenancePrompt?.title == "Refresh the host-facing CLI")
    #expect(dashboard.settings?.cliMaintenancePrompt?.actions == [.refreshAppManagedCLI])
}

@Test
func dashboardSnapshotPromotesBothRefreshActionsWhenHostAndTerminalCLIAreStale() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appBundleURL = tempRoot.appendingPathComponent("Bear MCP.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let appManagedCLIURL = tempRoot
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let terminalCLIURL = tempRoot
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: appManagedCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: terminalCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    try "#!/bin/sh\necho stale-app-managed\n".write(to: appManagedCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appManagedCLIURL.path)
    try "#!/bin/sh\necho stale-terminal\n".write(to: terminalCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: terminalCLIURL.path)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(),
        currentAppBundleURL: appBundleURL,
        appManagedCLIURL: appManagedCLIURL,
        terminalCLIURL: terminalCLIURL,
        bundledCLIExecutableURLResolver: { bundleURL, _ in
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("bear-mcp", isDirectory: false)
        },
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings?.cliMaintenancePrompt?.title == "Refresh the host-facing CLI")
    #expect(dashboard.settings?.cliMaintenancePrompt?.actions == [.refreshAppManagedCLI, .refreshTerminalCLI])
}

@Test
func saveConfigurationDraftPersistsEditableSettingsAndDisabledTools() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    try BearAppSupport.saveConfigurationDraft(
        BearAppConfigurationDraft(
            databasePath: "/tmp/updated.sqlite",
            inboxTags: ["0-inbox", "next", "0-inbox"],
            defaultInsertPosition: .top,
            templateManagementEnabled: false,
            openNoteInEditModeByDefault: false,
            createOpensNoteByDefault: false,
            openUsesNewWindowByDefault: false,
            createAddsInboxTagsByDefault: false,
            tagsMergeMode: .replace,
            defaultDiscoveryLimit: 5,
            maxDiscoveryLimit: 25,
            defaultSnippetLength: 50,
            maxSnippetLength: 200,
            backupRetentionDays: 7,
            disabledTools: [.addTags, .findNotes, .addTags]
        ),
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )

    let configuration = try BearRuntimeBootstrap.loadConfiguration(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )

    #expect(configuration.databasePath == "/tmp/updated.sqlite")
    #expect(configuration.inboxTags == ["0-inbox", "next"])
    #expect(configuration.defaultInsertPosition == .top)
    #expect(configuration.templateManagementEnabled == false)
    #expect(configuration.openNoteInEditModeByDefault == false)
    #expect(configuration.createOpensNoteByDefault == false)
    #expect(configuration.openUsesNewWindowByDefault == false)
    #expect(configuration.createAddsInboxTagsByDefault == false)
    #expect(configuration.tagsMergeMode == .replace)
    #expect(configuration.defaultDiscoveryLimit == 5)
    #expect(configuration.maxDiscoveryLimit == 25)
    #expect(configuration.defaultSnippetLength == 50)
    #expect(configuration.maxSnippetLength == 200)
    #expect(configuration.backupRetentionDays == 7)
    #expect(configuration.disabledTools == [.addTags, .findNotes])
}

@Test
func saveConfigurationDraftRejectsInvalidValues() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    #expect(throws: BearError.self) {
        try BearAppSupport.saveConfigurationDraft(
            BearAppConfigurationDraft(
                databasePath: "   ",
                inboxTags: [],
                defaultInsertPosition: .bottom,
                templateManagementEnabled: true,
                openNoteInEditModeByDefault: true,
                createOpensNoteByDefault: true,
                openUsesNewWindowByDefault: true,
                createAddsInboxTagsByDefault: true,
                tagsMergeMode: .append,
                defaultDiscoveryLimit: 20,
                maxDiscoveryLimit: 10,
                defaultSnippetLength: 280,
                maxSnippetLength: 100,
                backupRetentionDays: 30,
                disabledTools: []
            ),
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
    }
}

@Test
func validateConfigurationDraftReportsWarningsAndErrors() {
    let report = BearAppSupport.validateConfigurationDraft(
        BearAppConfigurationDraft(
            databasePath: "relative/path.sqlite",
            inboxTags: [],
            defaultInsertPosition: .bottom,
            templateManagementEnabled: true,
            openNoteInEditModeByDefault: true,
            createOpensNoteByDefault: true,
            openUsesNewWindowByDefault: true,
            createAddsInboxTagsByDefault: true,
            tagsMergeMode: .append,
            defaultDiscoveryLimit: 20,
            maxDiscoveryLimit: 10,
            defaultSnippetLength: 280,
            maxSnippetLength: 100,
            backupRetentionDays: -1,
            disabledTools: []
        )
    )

    #expect(report.issues(for: .databasePath).count == 2)
    #expect(report.issues(for: .inboxTags).count == 1)
    #expect(report.issues(for: .maxDiscoveryLimit).count == 1)
    #expect(report.issues(for: .maxSnippetLength).count == 1)
    #expect(report.issues(for: .backupRetentionDays).count == 1)
    #expect(report.hasErrors)
    #expect(report.warnings.count == 3)
}

@Test
func dashboardSnapshotFlagsHostAppsThatNeedConfigUpdates() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let homeDirectoryURL = tempRoot.appendingPathComponent("home", isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appManagedCLIURL = tempRoot
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let codexConfigURL = homeDirectoryURL
        .appendingPathComponent(".codex", isDirectory: true)
        .appendingPathComponent("config.toml", isDirectory: false)
    let claudeConfigURL = homeDirectoryURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Claude", isDirectory: true)
        .appendingPathComponent("claude_desktop_config.json", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: codexConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: claudeConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try """
    [mcp_servers.bear]
    enabled = true
    command = "/tmp/old-bear-mcp"
    args = ["mcp"]
    """.write(to: codexConfigURL, atomically: true, encoding: .utf8)
    try "{ invalid json".write(to: claudeConfigURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(),
        appManagedCLIURL: appManagedCLIURL,
        homeDirectoryURL: homeDirectoryURL,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    let codexSetup = try #require(hostSetup(named: "codex", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(codexSetup.status == .invalid)
    #expect(codexSetup.detail.contains("stable app-managed CLI path"))

    let claudeSetup = try #require(hostSetup(named: "claude-desktop", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(claudeSetup.status == .invalid)
    #expect(claudeSetup.detail.contains("could not be parsed as JSON"))

    let codexDiagnostic = try #require(diagnostic(named: "host-codex", in: dashboard.diagnostics))
    #expect(codexDiagnostic.status == .invalid)

    let claudeDiagnostic = try #require(diagnostic(named: "host-claude-desktop", in: dashboard.diagnostics))
    #expect(claudeDiagnostic.status == .invalid)
}

@Test
func dashboardSnapshotPrefersKeychainStatusWhenAvailable() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try """
    {
      "token" : "legacy-token"
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(storedToken: "keychain-token"),
        allowSecureTokenStatusRead: true,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings?.selectedNoteTokenConfigured == true)
    #expect(dashboard.settings?.selectedNoteTokenStoredInKeychain == true)
    #expect(dashboard.settings?.selectedNoteLegacyConfigTokenDetected == true)
    #expect(dashboard.settings?.selectedNoteTokenStorageDescription == "Stored in Keychain")
    #expect(dashboard.diagnostics.contains(where: {
        $0.key == "selected-note-token"
            && $0.value == "Stored in Keychain"
            && ($0.detail?.contains("legacy plaintext token") ?? false)
    }))
}

@Test
func tokenManagementActionsSaveImportAndRemoveWithoutTouchingKeychainAccessApp() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let tokenStore = TestSelectedNoteTokenStore()

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try """
    {
      "token" : "legacy-token"
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    try BearAppSupport.saveSelectedNoteToken(
        "new-keychain-token",
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: tokenStore
    )
    #expect(tokenStore.storedToken == "new-keychain-token")
    let savedConfiguration = try BearConfiguration.load(from: configFileURL)
    #expect(savedConfiguration.token == nil)
    #expect(savedConfiguration.selectedNoteTokenStoredInKeychain == true)

    try """
    {
      "token" : "import-me"
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
    let imported = try BearAppSupport.importSelectedNoteTokenFromConfig(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: tokenStore
    )
    #expect(imported)
    #expect(tokenStore.storedToken == "import-me")
    let importedConfiguration = try BearConfiguration.load(from: configFileURL)
    #expect(importedConfiguration.token == nil)
    #expect(importedConfiguration.selectedNoteTokenStoredInKeychain == true)

    try """
    {
      "token" : "remove-me-too"
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
    try BearAppSupport.removeSelectedNoteToken(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: tokenStore
    )
    #expect(tokenStore.storedToken == nil)
    let removedConfiguration = try BearConfiguration.load(from: configFileURL)
    #expect(removedConfiguration.token == nil)
    #expect(removedConfiguration.selectedNoteTokenStoredInKeychain == false)
}

@Test
func loadResolvedSelectedNoteTokenMatchesEffectiveLookupOrder() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let tokenStore = TestSelectedNoteTokenStore(storedToken: "keychain-token")

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try """
    {
      "token" : "legacy-token"
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let resolved = try BearAppSupport.loadResolvedSelectedNoteToken(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: tokenStore
    )

    #expect(resolved?.value == "keychain-token")
    #expect(resolved?.source == .keychain)
}

@Test
func selectedNoteAppHostDetectsHeadlessLaunchModeFromArguments() {
    let detectsCallbackInvocation = BearSelectedNoteAppHost.shouldRunHeadless(
        arguments: [
            "Bear MCP",
            "-url", "bear://x-callback-url/open-note?selected=yes&token=top-secret-token",
            "-responseFile", "/tmp/selected-note.json",
        ]
    )
    let detectsNormalLaunch = BearSelectedNoteAppHost.shouldRunHeadless(
        arguments: [
            "Bear MCP",
        ]
    )

    #expect(detectsCallbackInvocation)
    #expect(!detectsNormalLaunch)
}

@Test
@MainActor
func selectedNoteAppHostStartsAndCompletesCallbackSessionInsideDashboardInstance() throws {
    let recorder = AppHostCallbackRecorder()
    let responseFileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: false)
        .appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: responseFileURL) }

    let appHost = BearSelectedNoteAppHost(
        arguments: ["Bear MCP"],
        callbackHostFactory: { completion in
            BearSelectedNoteCallbackHost(
                callbackScheme: BearSelectedNoteCallbackHost.appCallbackScheme,
                outputWriter: { data, channel in
                    recorder.recordOutput(data, channel: channel)
                },
                urlOpener: { url, activateApp, openCompletion in
                    recorder.recordOpen(url: url, activateApp: activateApp)
                    openCompletion(nil)
                },
                terminator: {
                    recorder.recordTermination()
                    completion()
                }
            )
        }
    )

    let request = BearSelectedNoteAppRequest(
        requestURL: URL(string: "bear://x-callback-url/open-note?selected=yes&token=top-secret-token")!,
        activateApp: false,
        responseFileURL: responseFileURL
    )

    #expect(appHost.launchMode == .dashboard)
    #expect(appHost.handleIncomingURL(request.url))

    let started = recorder.snapshot()
    guard let openedURL = started.openedURL else {
        Issue.record("Expected dashboard app host to start a selected-note callback session.")
        return
    }

    #expect(started.activateApp == false)

    guard var callbackComponents = URLComponents(
        string: try #require(
            URLComponents(url: openedURL, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "x-success" })?
                .value
        )
    ) else {
        Issue.record("Expected rewritten success callback URL.")
        return
    }

    callbackComponents.queryItems = (callbackComponents.queryItems ?? []) + [
        URLQueryItem(name: "identifier", value: "selected-note"),
    ]
    guard let callbackURL = callbackComponents.url else {
        Issue.record("Expected valid success callback URL.")
        return
    }

    #expect(appHost.handleIncomingURL(callbackURL))

    let finished = recorder.snapshot()
    #expect(finished.terminatedCount == 1)
    #expect(finished.stdout.contains("selected-note"))
    #expect(finished.stderr.isEmpty)

    let payload = try parseAppHostPayload(Data(contentsOf: responseFileURL))
    #expect(payload["identifier"] == "selected-note")
}

@Test
func prepareManagedSelectedNoteRequestURLInjectsTokenForTokenlessSelectedNoteRequest() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let requestURL = URL(string: "bear://x-callback-url/open-note?selected=yes&open_note=no&show_window=no")!
    let preparedURL = try BearAppSupport.prepareManagedSelectedNoteRequestURL(
        requestURL,
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(storedToken: "keychain-token")
    )

    let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: preparedURL, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
    #expect(items["selected"] == "yes")
    #expect(items["token"] == "keychain-token")
    #expect(items["open_note"] == "no")
    #expect(items["show_window"] == "no")
}

@Test
func loadSettingsSnapshotRepairsMissingKeychainHintWhenTheAppCanReadTheToken() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let settings = try BearAppSupport.loadSettingsSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(storedToken: "keychain-token"),
        allowSecureTokenStatusRead: true
    )

    #expect(settings.selectedNoteTokenStoredInKeychain == true)
    #expect(try BearConfiguration.load(from: configFileURL).selectedNoteTokenStoredInKeychain == true)
}

@Test
func dashboardSnapshotUsesKeychainHintWithoutReadingSecureStorageByDefault() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try """
    {
      "selectedNoteTokenStoredInKeychain" : true
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        tokenStore: TestSelectedNoteTokenStore(
            readError: BearError.configuration("Keychain should not be read during dashboard load")
        ),
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings?.selectedNoteTokenConfigured == true)
    #expect(dashboard.settings?.selectedNoteTokenStoredInKeychain == true)
    #expect(dashboard.settings?.selectedNoteTokenStorageDescription == "Managed in Keychain")
    #expect(dashboard.diagnostics.contains(where: {
        $0.key == "selected-note-token"
            && $0.value == "Managed in Keychain"
            && ($0.detail?.contains("avoid re-reading it") ?? false)
    }))
}

@Test
func dashboardSnapshotReportsConfigurationLoadFailure() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try "{".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )

    #expect(dashboard.settings == nil)
    #expect(dashboard.settingsError != nil)
    #expect(dashboard.diagnostics.contains(where: { $0.key == "config-load" && $0.status == .failed }))
    #expect(!dashboard.diagnostics.contains(where: { $0.key == "selected-note-token" }))
}

private func parseAppHostPayload(_ data: Data) throws -> [String: String] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
        Issue.record("Expected selected-note app host payload to be a JSON object of strings.")
        return [:]
    }
    return object
}

private func diagnostic(named key: String, in diagnostics: [BearDoctorCheck]) -> BearDoctorCheck? {
    diagnostics.first(where: { $0.key == key })
}

private func hostSetup(named id: String, in setups: [BearHostAppSetupSnapshot]) -> BearHostAppSetupSnapshot? {
    setups.first(where: { $0.id == id })
}

private struct AppHostCallbackSnapshot {
    let openedURL: URL?
    let activateApp: Bool?
    let stdout: String
    let stderr: String
    let terminatedCount: Int
}

private final class AppHostCallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var openedURL: URL?
    private var activateApp: Bool?
    private var stdout = ""
    private var stderr = ""
    private var terminatedCount = 0

    func recordOpen(url: URL, activateApp: Bool) {
        lock.lock()
        self.openedURL = url
        self.activateApp = activateApp
        lock.unlock()
    }

    func recordOutput(_ data: Data, channel: BearSelectedNoteCallbackOutputChannel) {
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        switch channel {
        case .stdout:
            stdout.append(text)
        case .stderr:
            stderr.append(text)
        }
        lock.unlock()
    }

    func recordTermination() {
        lock.lock()
        terminatedCount += 1
        lock.unlock()
    }

    func snapshot() -> AppHostCallbackSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return AppHostCallbackSnapshot(
            openedURL: openedURL,
            activateApp: activateApp,
            stdout: stdout,
            stderr: stderr,
            terminatedCount: terminatedCount
        )
    }
}
