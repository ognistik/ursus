@testable import BearApplication
import BearCore
import BearXCallback
import Darwin
import Foundation
import Testing

@Test
func dashboardSnapshotIncludesSettingsWhenConfigurationLoads() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let homeDirectoryURL = tempRoot.appendingPathComponent("home", isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let bridgePlistURL = homeDirectoryURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let bridgeStandardOutputURL = homeDirectoryURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: true)
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let bridgeStandardErrorURL = homeDirectoryURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: true)
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("bridge.stderr.log", isDirectory: false)
    let tokenStore = InMemoryBearTokenStore(token: "phase-two-token")

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try """
    {
      "inboxTags" : [
        "0-inbox",
        "next"
      ],
      "createAddsInboxTagsByDefault" : false
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        tokenStore: tokenStore,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        launcherURL: launcherURL,
        bridgeLaunchAgentPlistURL: bridgePlistURL,
        bridgeStandardOutputURL: bridgeStandardOutputURL,
        bridgeStandardErrorURL: bridgeStandardErrorURL,
        homeDirectoryURL: homeDirectoryURL,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings != nil)
    #expect(dashboard.settingsError == nil)
    #expect(dashboard.settings?.inboxTags == ["0-inbox", "next"])
    #expect(dashboard.settings?.createAddsInboxTagsByDefault == false)
    #expect(dashboard.settings?.runtimeConfigurationGeneration == 0)
    #expect(dashboard.settings?.launcherPath == launcherURL.path)
    #expect(dashboard.settings?.launcherStatus == BearDoctorCheckStatus.missing)
    #expect(dashboard.settings?.launcherStatusTitle == "Not installed")
    #expect(dashboard.settings?.launcherStatusDetail == "Install the public launcher once so local MCP hosts and Terminal can run Ursus from one shared path.")
    #expect(dashboard.settings?.cliMaintenancePrompt?.actions == [BearAppCLIMaintenanceAction.installLauncher])
    #expect(dashboard.settings?.selectedNoteTokenConfigured == true)
    #expect(dashboard.settings?.selectedNoteTokenStorageDescription == "Stored in macOS Keychain")
    #expect(dashboard.settings?.bridge.status == BearDoctorCheckStatus.missing)
    #expect(dashboard.settings?.bridge.statusTitle == "Not installed")
    #expect(dashboard.settings?.bridge.endpointURL == "http://127.0.0.1:6190/mcp")
    #expect(dashboard.settings?.bridge.requiresOAuth == false)

    let bundledCLIDiagnostic = try #require(diagnostic(named: "bundled-cli", in: dashboard.diagnostics))
    #expect(bundledCLIDiagnostic.status == BearDoctorCheckStatus.missing)
    #expect(bundledCLIDiagnostic.detail == UrsusCLILocator.bundledExecutableGuidance)

    let launcherDiagnostic = try #require(diagnostic(named: "public-cli-launcher", in: dashboard.diagnostics))
    #expect(launcherDiagnostic.status == BearDoctorCheckStatus.missing)
    #expect(launcherDiagnostic.value == launcherURL.path)
    #expect(launcherDiagnostic.detail == "Install the public launcher once so local MCP hosts and Terminal can run Ursus from one shared path.")

    let callbackDiagnostic = try #require(diagnostic(named: "selected-note-app", in: dashboard.diagnostics))
    #expect(callbackDiagnostic.status == BearDoctorCheckStatus.missing)
    #expect(callbackDiagnostic.detail?.contains("install `Ursus.app` in `/Applications/Ursus.app` (preferred).") == true)
    #expect(callbackDiagnostic.detail?.contains("fully supported for user-specific installs") == true)

    let bridgeDiagnostic = try #require(diagnostic(named: "remote-mcp-bridge", in: dashboard.diagnostics))
    #expect(bridgeDiagnostic.status == BearDoctorCheckStatus.missing)
    #expect(bridgeDiagnostic.value == "http://127.0.0.1:6190/mcp")
    #expect(!dashboard.diagnostics.contains(where: { $0.key == "selected-note-helper" }))
}

@Test
func bridgeHealthCheckRequestAcceptsJSONResponses() throws {
    let url = try BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6190).endpointURL()
    let request = BearAppSupport.bridgeHealthCheckRequest(url: url, timeout: 0.25)

    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(request.httpBody != nil)
}

@Test
func bridgeAdvertisedSelectedNoteSupportParsesToolsListSchemas() throws {
    let supportsSelected = Data(
        """
        {
          "jsonrpc": "2.0",
          "result": {
            "tools": [
              {
                "name": "bear_get_notes",
                "inputSchema": {
                  "properties": {
                    "selected": { "type": "boolean" }
                  }
                }
              }
            ]
          }
        }
        """.utf8
    )
    let doesNotSupportSelected = Data(
        """
        {
          "jsonrpc": "2.0",
          "result": {
            "tools": [
              {
                "name": "bear_get_notes",
                "inputSchema": {
                  "properties": {
                    "notes": { "type": "array" }
                  }
                }
              }
            ]
          }
        }
        """.utf8
    )
    let unrelatedCatalog = Data(
        """
        {
          "jsonrpc": "2.0",
          "result": {
            "tools": [
              {
                "name": "other_tool",
                "inputSchema": {
                  "properties": {}
                }
              }
            ]
          }
        }
        """.utf8
    )

    #expect(BearAppSupport.testBridgeAdvertisedSelectedNoteSupport(from: supportsSelected) == true)
    #expect(BearAppSupport.testBridgeAdvertisedSelectedNoteSupport(from: doesNotSupportSelected) == false)
    #expect(BearAppSupport.testBridgeAdvertisedSelectedNoteSupport(from: unrelatedCatalog) == nil)
}

@Test
func dashboardSnapshotIncludesPreferredAppAndHelperDiagnosticsWithHealthyLauncher() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appBundleURL = tempRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let helperBundleURL = tempRoot.appendingPathComponent("Ursus Helper.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: helperBundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    _ = try UrsusCLILocator.installPublicLauncher(
        fromAppBundleURL: appBundleURL,
        fileManager: fileManager,
        destinationURL: launcherURL
    )
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        tokenStore: InMemoryBearTokenStore(),
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        currentAppBundleURL: appBundleURL,
        launcherURL: launcherURL,
        bundledCLIExecutableURLResolver: { bundleURL, _ in
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("Ursus", isDirectory: false)
        },
        callbackAppBundleURLProvider: { _ in appBundleURL },
        callbackAppExecutableURLResolver: { bundleURL, _ in
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("Ursus", isDirectory: false)
        },
        helperBundleURLProvider: { _ in helperBundleURL },
        helperExecutableURLResolver: { bundleURL, _ in
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("ursus-helper", isDirectory: false)
        }
    )

    let preferredAppDiagnostic = try #require(diagnostic(named: "selected-note-app", in: dashboard.diagnostics))
    #expect(preferredAppDiagnostic.status == BearDoctorCheckStatus.ok)
    #expect(preferredAppDiagnostic.value == appBundleURL.path)

    let bundledCLIDiagnostic = try #require(diagnostic(named: "bundled-cli", in: dashboard.diagnostics))
    #expect(bundledCLIDiagnostic.status == BearDoctorCheckStatus.ok)
    #expect(bundledCLIDiagnostic.value == bundledCLIURL.path)
    #expect(bundledCLIDiagnostic.detail == "embedded in \(appBundleURL.path)")

    let launcherDiagnostic = try #require(diagnostic(named: "public-cli-launcher", in: dashboard.diagnostics))
    #expect(launcherDiagnostic.status == BearDoctorCheckStatus.ok)
    #expect(launcherDiagnostic.value == launcherURL.path)
    #expect(launcherDiagnostic.detail == "Local MCP hosts and Terminal should use this one launcher path.")
    #expect(dashboard.settings?.launcherStatus == BearDoctorCheckStatus.ok)
    #expect(dashboard.settings?.launcherStatusTitle == "Installed")
    #expect(dashboard.settings?.launcherStatusDetail == "Local MCP hosts and Terminal should use this one launcher path.")
    #expect(dashboard.settings?.cliMaintenancePrompt == nil)

    let helperDiagnostic = try #require(diagnostic(named: "selected-note-helper", in: dashboard.diagnostics))
    #expect(helperDiagnostic.status == BearDoctorCheckStatus.ok)
    #expect(helperDiagnostic.value == helperBundleURL.path)
}

@Test
func dashboardSnapshotIncludesHostAppSetupGuidanceForCodexClaudeAndChatGPT() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let homeDirectoryURL = tempRoot.appendingPathComponent("home", isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
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
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)
    try """
    [mcp_servers.ursus]
    enabled = true
    command = "\(launcherURL.path)"
    args = ["mcp"]
    """.write(to: codexConfigURL, atomically: true, encoding: .utf8)
    try """
    {
      "mcpServers": {
        "ursus": {
          "type": "stdio",
          "command": "\(launcherURL.path)",
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
        tokenStore: InMemoryBearTokenStore(),
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        launcherURL: launcherURL,
        homeDirectoryURL: homeDirectoryURL,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    let genericSetup = try #require(hostSetup(named: "generic-local-stdio", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(genericSetup.status == BearDoctorCheckStatus.ok)
    #expect(genericSetup.snippet?.contains(launcherURL.path) == true)

    let codexSetup = try #require(hostSetup(named: "codex", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(codexSetup.status == BearDoctorCheckStatus.ok)
    #expect(codexSetup.configPath == codexConfigURL.path)
    #expect(codexSetup.snippet?.contains(launcherURL.path) == true)
    #expect(codexSetup.snippet?.contains("[mcp_servers.ursus]") == true)

    let claudeSetup = try #require(hostSetup(named: "claude-desktop", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(claudeSetup.status == BearDoctorCheckStatus.ok)
    #expect(claudeSetup.configPath == claudeConfigURL.path)
    #expect(claudeSetup.snippet?.contains(#""ursus": {"#) == true)

    let chatGPTSetup = try #require(hostSetup(named: "chatgpt", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(chatGPTSetup.status == BearDoctorCheckStatus.notConfigured)
    #expect(chatGPTSetup.statusTitle == "Remote MCP only")

    let genericDiagnostic = try #require(diagnostic(named: "host-local-stdio", in: dashboard.diagnostics))
    #expect(genericDiagnostic.status == BearDoctorCheckStatus.ok)
    #expect(genericDiagnostic.value == launcherURL.path)
}

@Test
func dashboardSnapshotFlagsStaleLauncherForRepair() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appBundleURL = tempRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    try "#!/bin/sh\necho stale\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        tokenStore: InMemoryBearTokenStore(),
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        currentAppBundleURL: appBundleURL,
        launcherURL: launcherURL,
        bundledCLIExecutableURLResolver: { bundleURL, _ in
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("Ursus", isDirectory: false)
        },
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    let launcherDiagnostic = try #require(diagnostic(named: "public-cli-launcher", in: dashboard.diagnostics))
    #expect(launcherDiagnostic.status == BearDoctorCheckStatus.invalid)
    #expect(launcherDiagnostic.detail == "This public launcher does not match the current app build. Repair it from this app.")
    #expect(dashboard.settings?.launcherStatus == BearDoctorCheckStatus.invalid)
    #expect(dashboard.settings?.launcherStatusTitle == "Needs refresh")
    #expect(dashboard.settings?.launcherStatusDetail == "This public launcher does not match the current app build. Repair it from this app.")
    #expect(dashboard.settings?.cliMaintenancePrompt?.title == "Repair the public launcher")
    #expect(dashboard.settings?.cliMaintenancePrompt?.actions == [BearAppCLIMaintenanceAction.refreshLauncher])
}

@Test
func reconcilePublicLauncherInstallsMissingLauncher() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = tempRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)

    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let result = try BearAppSupport.reconcilePublicLauncherIfNeeded(
        fromAppBundleURL: appBundleURL,
        fileManager: fileManager,
        destinationURL: launcherURL
    )

    #expect(result.status == BearAppPublicLauncherReconciliationStatus.installed)
    #expect(result.sourcePath == bundledCLIURL.path)
    #expect(result.destinationPath == launcherURL.path)
    #expect(fileManager.fileExists(atPath: launcherURL.path))
    #expect(fileManager.isExecutableFile(atPath: launcherURL.path))
    #expect(try String(contentsOf: launcherURL, encoding: .utf8).contains("Ursus launcher"))
}

@Test
func reconcilePublicLauncherRepairsStaleLauncher() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = tempRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)

    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    try "#!/bin/sh\necho stale\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let result = try BearAppSupport.reconcilePublicLauncherIfNeeded(
        fromAppBundleURL: appBundleURL,
        fileManager: fileManager,
        destinationURL: launcherURL
    )

    #expect(result.status == BearAppPublicLauncherReconciliationStatus.refreshed)
    #expect(result.sourcePath == bundledCLIURL.path)
    #expect(result.destinationPath == launcherURL.path)
    #expect(try String(contentsOf: launcherURL, encoding: .utf8).contains("Ursus launcher"))
}

@Test
func reconcilePublicLauncherReturnsUnchangedWhenLauncherMatchesBundle() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = tempRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)

    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    _ = try UrsusCLILocator.installPublicLauncher(
        fromAppBundleURL: appBundleURL,
        fileManager: fileManager,
        destinationURL: launcherURL
    )
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let result = try BearAppSupport.reconcilePublicLauncherIfNeeded(
        fromAppBundleURL: appBundleURL,
        fileManager: fileManager,
        destinationURL: launcherURL
    )

    #expect(result.status == BearAppPublicLauncherReconciliationStatus.unchanged)
    #expect(result.sourcePath == nil)
    #expect(result.destinationPath == nil)
}

@Test
func installBridgeLaunchAgentWritesExpectedPlistAndEnablesBridge() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appBundleURL = tempRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launchAgentPlistURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let stdoutURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: true)
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: true)
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("bridge.stderr.log", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    let bridgePort = try availableLoopbackPort()

    let initialConfiguration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30,
        bridge: BearBridgeConfiguration(enabled: false, host: "127.0.0.1", port: bridgePort, authMode: .oauth)
    )
    try BearJSON.makeEncoder().encode(initialConfiguration).write(to: configFileURL, options: .atomic)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let recorder = LaunchctlRecorder()

    let receipt = try BearAppSupport.installBridgeLaunchAgent(
        fromAppBundleURL: appBundleURL,
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        launchctlRunner: recorder.installRunner,
        endpointProbe: { _, _ in BearBridgeEndpointProbeResult(reachable: true) }
    )

    let savedConfiguration = try BearRuntimeBootstrap.loadConfiguration(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )
    let writtenPlist = try BearBridgeLaunchAgentPlist.load(from: launchAgentPlistURL)

    #expect(receipt.status == .installed)
    #expect(savedConfiguration.bridge == BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: bridgePort, authMode: .oauth))
    #expect(writtenPlist == BearBridgeLaunchAgent.expectedPlist(
        launcherURL: launcherURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL
    ))
    #expect(fileManager.fileExists(atPath: launcherURL.path))
    #expect(fileManager.fileExists(atPath: stdoutURL.path))
    #expect(fileManager.fileExists(atPath: stderrURL.path))
    #expect(recorder.commands == [
        ["print", "gui/\(getuid())/com.aft.ursus"],
        ["bootstrap", "gui/\(getuid())", launchAgentPlistURL.path],
    ])
}

@Test
func bridgeSnapshotReportsPausedWhenLaunchAgentIsInstalledButUnloaded() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launchAgentPlistURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let stdoutURL = tempRoot.appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = tempRoot.appendingPathComponent("bridge.stderr.log", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launchAgentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)

    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30,
        bridge: BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6205, authMode: .oauth)
    )
    try BearJSON.makeEncoder().encode(configuration).write(to: configFileURL, options: .atomic)
    try BearBridgeLaunchAgent.expectedPlist(
        launcherURL: launcherURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL
    ).xmlData().write(to: launchAgentPlistURL, options: .atomic)
    try "stdout".write(to: stdoutURL, atomically: true, encoding: .utf8)
    try "stderr".write(to: stderrURL, atomically: true, encoding: .utf8)
    try "stdout-archive".write(
        to: tempRoot.appendingPathComponent("bridge.stdout.log.1", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
    try "stderr-archive".write(
        to: tempRoot.appendingPathComponent("bridge.stderr.log.1", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let snapshot = BearAppSupport.bridgeSnapshot(
        configuration: configuration,
        fileManager: fileManager,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        launchctlRunner: { arguments in
            #expect(arguments == ["print", "gui/\(getuid())/com.aft.ursus"])
            return BearProcessExecutionResult(exitCode: 3, stdout: "", stderr: "Could not find service")
        },
        endpointProbe: { _, _ in
            Issue.record("The endpoint probe should not run when the LaunchAgent is unloaded.")
            return BearBridgeEndpointProbeResult(reachable: false)
        }
    )

    #expect(snapshot.status == BearDoctorCheckStatus.notConfigured)
    #expect(snapshot.statusTitle == "Paused")
    #expect(snapshot.installed == true)
    #expect(snapshot.loaded == false)
    #expect(snapshot.plistMatchesExpected == true)
}

@Test
func bridgeSnapshotIncludesLoadedRuntimeGenerationWhenBridgeStateExists() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = tempRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launchAgentPlistURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let stdoutURL = tempRoot.appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = tempRoot.appendingPathComponent("bridge.stderr.log", isDirectory: false)
    let bridgeRuntimeStateURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: true)
        .appendingPathComponent("Runtime", isDirectory: true)
        .appendingPathComponent("bridge-runtime-state.json", isDirectory: false)

    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launchAgentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)

    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30,
        runtimeConfigurationGeneration: 4,
        bridge: BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6205, authMode: .oauth)
    )
    try BearBridgeLaunchAgent.expectedPlist(
        launcherURL: launcherURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL
    ).xmlData().write(to: launchAgentPlistURL, options: .atomic)
    try BearAppSupport.recordBridgeLoadedRuntimeState(
        selectedNoteTokenConfigured: true,
        runtimeConfigurationGeneration: 2,
        runtimeConfigurationFingerprint: "loaded-fingerprint",
        bridgeSurfaceMarker: "loaded-bridge-surface",
        fileManager: fileManager,
        runtimeStateURL: bridgeRuntimeStateURL
    )
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let snapshot = BearAppSupport.bridgeSnapshot(
        configuration: configuration,
        selectedNoteTokenConfigured: true,
        currentBridgeSurfaceMarker: "current-bridge-surface",
        fileManager: fileManager,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        bridgeRuntimeStateURL: bridgeRuntimeStateURL,
        launchctlRunner: { _ in
            BearProcessExecutionResult(exitCode: 0, stdout: "service = {}", stderr: "")
        },
        endpointProbe: { _, _ in
            BearBridgeEndpointProbeResult(reachable: true)
        }
    )

    #expect(snapshot.loaded == true)
    #expect(snapshot.currentSelectedNoteTokenConfigured == true)
    #expect(snapshot.loadedSelectedNoteTokenConfigured == true)
    #expect(snapshot.currentRuntimeConfigurationGeneration == 4)
    #expect(snapshot.loadedRuntimeConfigurationGeneration == 2)
    #expect(snapshot.currentRuntimeConfigurationFingerprint == configuration.runtimeConfigurationFingerprint)
    #expect(snapshot.loadedRuntimeConfigurationFingerprint == "loaded-fingerprint")
    #expect(snapshot.currentBridgeSurfaceMarker == "current-bridge-surface")
    #expect(snapshot.loadedBridgeSurfaceMarker == "loaded-bridge-surface")
    #expect(snapshot.status == .ok)
}

@Test
func bridgeSnapshotMarksRestartRequiredWhenSurfaceMarkerChanges() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = tempRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launchAgentPlistURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let stdoutURL = tempRoot.appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = tempRoot.appendingPathComponent("bridge.stderr.log", isDirectory: false)
    let bridgeRuntimeStateURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: true)
        .appendingPathComponent("Runtime", isDirectory: true)
        .appendingPathComponent("bridge-runtime-state.json", isDirectory: false)

    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launchAgentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)

    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30,
        runtimeConfigurationGeneration: 4,
        bridge: BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6205, authMode: .oauth)
    )
    try BearBridgeLaunchAgent.expectedPlist(
        launcherURL: launcherURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL
    ).xmlData().write(to: launchAgentPlistURL, options: .atomic)
    try BearAppSupport.recordBridgeLoadedRuntimeState(
        selectedNoteTokenConfigured: true,
        runtimeConfigurationGeneration: 4,
        runtimeConfigurationFingerprint: configuration.runtimeConfigurationFingerprint,
        bridgeSurfaceMarker: "stale-bridge-surface",
        fileManager: fileManager,
        runtimeStateURL: bridgeRuntimeStateURL
    )
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let snapshot = BearAppSupport.bridgeSnapshot(
        configuration: configuration,
        selectedNoteTokenConfigured: true,
        currentBridgeSurfaceMarker: "current-bridge-surface",
        fileManager: fileManager,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        bridgeRuntimeStateURL: bridgeRuntimeStateURL,
        launchctlRunner: { _ in
            BearProcessExecutionResult(exitCode: 0, stdout: "service = {}", stderr: "")
        },
        endpointProbe: { _, _ in
            BearBridgeEndpointProbeResult(reachable: true)
        }
    )

    #expect(snapshot.runtimeConfigurationRestartRequired == false)
    #expect(snapshot.surfaceRestartRequired == true)
    #expect(snapshot.selectedNoteTokenRestartRequired == false)
    #expect(snapshot.restartRequired == true)
}

@Test
func bridgeSnapshotTracksSelectedNoteTokenAvailabilityForRestartDetection() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = tempRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launchAgentPlistURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let stdoutURL = tempRoot.appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = tempRoot.appendingPathComponent("bridge.stderr.log", isDirectory: false)
    let bridgeRuntimeStateURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: true)
        .appendingPathComponent("Runtime", isDirectory: true)
        .appendingPathComponent("bridge-runtime-state.json", isDirectory: false)

    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launchAgentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)

    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30,
        runtimeConfigurationGeneration: 4,
        bridge: BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6205)
    )
    try BearBridgeLaunchAgent.expectedPlist(
        launcherURL: launcherURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL
    ).xmlData().write(to: launchAgentPlistURL, options: .atomic)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    try BearAppSupport.recordBridgeLoadedRuntimeState(
        selectedNoteTokenConfigured: false,
        runtimeConfigurationGeneration: 4,
        runtimeConfigurationFingerprint: configuration.runtimeConfigurationFingerprint,
        bridgeSurfaceMarker: "stable-bridge-surface",
        fileManager: fileManager,
        runtimeStateURL: bridgeRuntimeStateURL
    )

    let snapshotAfterTokenAdded = BearAppSupport.bridgeSnapshot(
        configuration: configuration,
        selectedNoteTokenConfigured: true,
        currentBridgeSurfaceMarker: "stable-bridge-surface",
        fileManager: fileManager,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        bridgeRuntimeStateURL: bridgeRuntimeStateURL,
        launchctlRunner: { _ in
            BearProcessExecutionResult(exitCode: 0, stdout: "service = {}", stderr: "")
        },
        endpointProbe: { _, _ in
            BearBridgeEndpointProbeResult(reachable: true)
        }
    )

    #expect(snapshotAfterTokenAdded.selectedNoteTokenRestartRequired == true)
    #expect(snapshotAfterTokenAdded.restartRequired == true)

    try BearAppSupport.recordBridgeLoadedRuntimeState(
        selectedNoteTokenConfigured: true,
        runtimeConfigurationGeneration: 4,
        runtimeConfigurationFingerprint: configuration.runtimeConfigurationFingerprint,
        bridgeSurfaceMarker: "stable-bridge-surface",
        fileManager: fileManager,
        runtimeStateURL: bridgeRuntimeStateURL
    )

    let snapshotAfterTokenRemovedAndReadded = BearAppSupport.bridgeSnapshot(
        configuration: configuration,
        selectedNoteTokenConfigured: true,
        currentBridgeSurfaceMarker: "stable-bridge-surface",
        fileManager: fileManager,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        bridgeRuntimeStateURL: bridgeRuntimeStateURL,
        launchctlRunner: { _ in
            BearProcessExecutionResult(exitCode: 0, stdout: "service = {}", stderr: "")
        },
        endpointProbe: { _, _ in
            BearBridgeEndpointProbeResult(reachable: true)
        }
    )

    #expect(snapshotAfterTokenRemovedAndReadded.selectedNoteTokenRestartRequired == false)
    #expect(snapshotAfterTokenRemovedAndReadded.restartRequired == false)

    let snapshotAfterTokenRemoved = BearAppSupport.bridgeSnapshot(
        configuration: configuration,
        selectedNoteTokenConfigured: false,
        currentBridgeSurfaceMarker: "stable-bridge-surface",
        fileManager: fileManager,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        bridgeRuntimeStateURL: bridgeRuntimeStateURL,
        launchctlRunner: { _ in
            BearProcessExecutionResult(exitCode: 0, stdout: "service = {}", stderr: "")
        },
        endpointProbe: { _, _ in
            BearBridgeEndpointProbeResult(reachable: true)
        }
    )

    #expect(snapshotAfterTokenRemoved.selectedNoteTokenRestartRequired == true)
    #expect(snapshotAfterTokenRemoved.restartRequired == true)
}

@Test
func bridgeSnapshotFallsBackToLiveProbeWhenRuntimeStateLacksTokenMarker() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = tempRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launchAgentPlistURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let stdoutURL = tempRoot.appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = tempRoot.appendingPathComponent("bridge.stderr.log", isDirectory: false)
    let bridgeRuntimeStateURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: true)
        .appendingPathComponent("Runtime", isDirectory: true)
        .appendingPathComponent("bridge-runtime-state.json", isDirectory: false)

    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launchAgentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)

    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30,
        runtimeConfigurationGeneration: 4,
        bridge: BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6205)
    )
    try BearBridgeLaunchAgent.expectedPlist(
        launcherURL: launcherURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL
    ).xmlData().write(to: launchAgentPlistURL, options: .atomic)
    try fileManager.createDirectory(at: bridgeRuntimeStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try """
    {
      "loadedRuntimeConfigurationGeneration" : 4,
      "loadedRuntimeConfigurationFingerprint" : "\(configuration.runtimeConfigurationFingerprint)",
      "loadedBridgeSurfaceMarker" : "stable-bridge-surface",
      "recordedAt" : "2026-04-06T15:00:00Z"
    }
    """.write(to: bridgeRuntimeStateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let snapshot = BearAppSupport.bridgeSnapshot(
        configuration: configuration,
        selectedNoteTokenConfigured: false,
        currentBridgeSurfaceMarker: "stable-bridge-surface",
        fileManager: fileManager,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        bridgeRuntimeStateURL: bridgeRuntimeStateURL,
        launchctlRunner: { _ in
            BearProcessExecutionResult(exitCode: 0, stdout: "service = {}", stderr: "")
        },
        endpointProbe: { _, _ in
            BearBridgeEndpointProbeResult(
                reachable: true,
                selectedNoteTokenConfigured: true
            )
        }
    )

    #expect(snapshot.loadedSelectedNoteTokenConfigured == true)
    #expect(snapshot.selectedNoteTokenRestartRequired == true)
    #expect(snapshot.restartRequired == true)
}

@Test
func bridgeSnapshotRequiresRestartWhenLoadedBridgeHasNoRuntimeState() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launchAgentPlistURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let stdoutURL = tempRoot.appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = tempRoot.appendingPathComponent("bridge.stderr.log", isDirectory: false)
    let bridgeRuntimeStateURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: true)
        .appendingPathComponent("Runtime", isDirectory: true)
        .appendingPathComponent("bridge-runtime-state.json", isDirectory: false)

    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launchAgentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)

    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30,
        runtimeConfigurationGeneration: 4,
        bridge: BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6205)
    )
    try BearBridgeLaunchAgent.expectedPlist(
        launcherURL: launcherURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL
    ).xmlData().write(to: launchAgentPlistURL, options: .atomic)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let snapshot = BearAppSupport.bridgeSnapshot(
        configuration: configuration,
        selectedNoteTokenConfigured: false,
        currentBridgeSurfaceMarker: "stable-bridge-surface",
        fileManager: fileManager,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        bridgeRuntimeStateURL: bridgeRuntimeStateURL,
        launchctlRunner: { _ in
            BearProcessExecutionResult(exitCode: 0, stdout: "service = {}", stderr: "")
        },
        endpointProbe: { _, _ in
            BearBridgeEndpointProbeResult(reachable: true)
        }
    )

    #expect(snapshot.status == .ok)
    #expect(snapshot.runtimeConfigurationRestartRequired == true)
    #expect(snapshot.surfaceRestartRequired == true)
    #expect(snapshot.restartRequired == true)
}

@Test
func pauseResumeAndRemoveBridgeLaunchAgentManageLoadedStateAndPlist() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launchAgentPlistURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let stdoutURL = tempRoot.appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = tempRoot.appendingPathComponent("bridge.stderr.log", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launchAgentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)

    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30,
        bridge: BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6205, authMode: .oauth)
    )
    try BearJSON.makeEncoder().encode(configuration).write(to: configFileURL, options: .atomic)
    try BearBridgeLaunchAgent.expectedPlist(
        launcherURL: launcherURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL
    ).xmlData().write(to: launchAgentPlistURL, options: .atomic)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let recorder = LaunchctlRecorder(loaded: true)

    let pauseReceipt = try BearAppSupport.pauseBridgeLaunchAgent(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        launchAgentPlistURL: launchAgentPlistURL,
        launchctlRunner: recorder.statefulRunner
    )
    #expect(pauseReceipt.status == .paused)
    #expect(fileManager.fileExists(atPath: launchAgentPlistURL.path))

    let resumeReceipt = try BearAppSupport.resumeBridgeLaunchAgent(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        launchctlRunner: recorder.statefulRunner,
        endpointProbe: { _, _ in BearBridgeEndpointProbeResult(reachable: true) }
    )
    #expect(resumeReceipt.status == .resumed)
    #expect(fileManager.fileExists(atPath: launchAgentPlistURL.path))

    let removeReceipt = try BearAppSupport.removeBridgeLaunchAgent(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        launchctlRunner: recorder.statefulRunner
    )
    #expect(removeReceipt.status == .removed)
    #expect(fileManager.fileExists(atPath: launchAgentPlistURL.path) == false)
    #expect(fileManager.fileExists(atPath: stdoutURL.path) == false)
    #expect(fileManager.fileExists(atPath: stderrURL.path) == false)
    #expect(fileManager.fileExists(atPath: tempRoot.appendingPathComponent("bridge.stdout.log.1", isDirectory: false).path) == false)
    #expect(fileManager.fileExists(atPath: tempRoot.appendingPathComponent("bridge.stderr.log.1", isDirectory: false).path) == false)

    let savedConfiguration = try BearRuntimeBootstrap.loadConfiguration(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )

    #expect(savedConfiguration.bridge == BearBridgeConfiguration(enabled: false, host: "127.0.0.1", port: 6205, authMode: .oauth))
    #expect(recorder.commands == [
        ["print", "gui/\(getuid())/com.aft.ursus"],
        ["print", "gui/\(getuid())/com.aft.ursus"],
        ["bootout", "gui/\(getuid())", launchAgentPlistURL.path],
        ["print", "gui/\(getuid())/com.aft.ursus"],
        ["bootstrap", "gui/\(getuid())", launchAgentPlistURL.path],
        ["print", "gui/\(getuid())/com.aft.ursus"],
        ["bootout", "gui/\(getuid())", launchAgentPlistURL.path],
    ])
}

@Test
func installBridgeLaunchAgentTreatsBootoutIOErrorAsBenignWhenServiceIsAlreadyGone() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appBundleURL = tempRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launchAgentPlistURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let stdoutURL = tempRoot.appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = tempRoot.appendingPathComponent("bridge.stderr.log", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    final class BootoutRaceRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var commands: [[String]] = []
        private var printCount = 0

        var runner: BearLaunchctlCommandRunner {
            { [weak self] arguments in
                guard let self else {
                    return BearProcessExecutionResult(exitCode: 1, stdout: "", stderr: "Recorder unavailable")
                }
                self.lock.lock()
                self.commands.append(arguments)
                self.lock.unlock()

                switch arguments.first {
                case "print":
                    self.lock.lock()
                    self.printCount += 1
                    let currentCount = self.printCount
                    self.lock.unlock()
                    return currentCount == 1
                        ? BearProcessExecutionResult(exitCode: 0, stdout: "service = {}", stderr: "")
                        : BearProcessExecutionResult(exitCode: 3, stdout: "", stderr: "Could not find service")
                case "bootout":
                    return BearProcessExecutionResult(
                        exitCode: 5,
                        stdout: "",
                        stderr: "Boot-out failed: 5: Input/output error\nTry re-running the command as root for richer errors."
                    )
                case "bootstrap":
                    return BearProcessExecutionResult(exitCode: 0, stdout: "", stderr: "")
                default:
                    return BearProcessExecutionResult(exitCode: 1, stdout: "", stderr: "Unexpected launchctl command")
                }
            }
        }
    }

    let recorder = BootoutRaceRecorder()

    let receipt = try BearAppSupport.installBridgeLaunchAgent(
        fromAppBundleURL: appBundleURL,
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        launchctlRunner: recorder.runner,
        endpointProbe: { _, _ in BearBridgeEndpointProbeResult(reachable: true) }
    )

    #expect(receipt.status == .installed)
    #expect(recorder.commands == [
        ["print", "gui/\(getuid())/com.aft.ursus"],
        ["bootout", "gui/\(getuid())", launchAgentPlistURL.path],
        ["print", "gui/\(getuid())/com.aft.ursus"],
        ["bootstrap", "gui/\(getuid())", launchAgentPlistURL.path],
    ])
}

@Test
func bridgeSnapshotReportsLoadedButUnreachableBridgeAsFailed() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launchAgentPlistURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let stdoutURL = tempRoot.appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = tempRoot.appendingPathComponent("bridge.stderr.log", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launchAgentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)

    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30,
        bridge: BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6205)
    )
    try BearJSON.makeEncoder().encode(configuration).write(to: configFileURL, options: .atomic)
    try BearBridgeLaunchAgent.expectedPlist(
        launcherURL: launcherURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL
    ).xmlData().write(to: launchAgentPlistURL, options: .atomic)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let snapshot = BearAppSupport.bridgeSnapshot(
        configuration: configuration,
        fileManager: fileManager,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        launchctlRunner: { arguments in
            #expect(arguments == ["print", "gui/\(getuid())/com.aft.ursus"])
            return BearProcessExecutionResult(exitCode: 0, stdout: "service = {}", stderr: "")
        },
        endpointProbe: { _, _ in
            BearBridgeEndpointProbeResult(reachable: false, detail: "Connection refused")
        }
    )

    #expect(snapshot.status == .failed)
    #expect(snapshot.statusTitle == "Not reachable")
    #expect(snapshot.statusDetail.contains("Connection refused"))
    #expect(snapshot.loaded == true)
    #expect(snapshot.endpointTransportReachable == false)
    #expect(snapshot.endpointProtocolCompatible == false)
}

@Test
func bridgeSnapshotReportsProtocolFailureAndSurfacesRecentLogHint() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launchAgentPlistURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.aft.ursus.plist", isDirectory: false)
    let stdoutURL = tempRoot.appendingPathComponent("bridge.stdout.log", isDirectory: false)
    let stderrURL = tempRoot.appendingPathComponent("bridge.stderr.log", isDirectory: false)

    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launchAgentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)
    try "initialize probe returned HTTP 404\n".write(to: stderrURL, atomically: true, encoding: .utf8)

    let configuration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30,
        bridge: BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6205)
    )
    try BearBridgeLaunchAgent.expectedPlist(
        launcherURL: launcherURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL
    ).xmlData().write(to: launchAgentPlistURL, options: .atomic)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let snapshot = BearAppSupport.bridgeSnapshot(
        configuration: configuration,
        fileManager: fileManager,
        launcherURL: launcherURL,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: stdoutURL,
        standardErrorURL: stderrURL,
        launchctlRunner: { _ in
            BearProcessExecutionResult(exitCode: 0, stdout: "service = {}", stderr: "")
        },
        endpointProbe: { _, _ in
            BearBridgeEndpointProbeResult(
                reachable: false,
                transportReachable: true,
                protocolCompatible: false,
                detail: "A TCP connection succeeded, but the MCP initialize probe returned HTTP 404."
            )
        }
    )

    #expect(snapshot.status == .failed)
    #expect(snapshot.statusTitle == "Protocol check failed")
    #expect(snapshot.statusDetail.contains("HTTP 404"))
    #expect(snapshot.statusDetail.contains("Recent stderr: initialize probe returned HTTP 404"))
    #expect(snapshot.endpointTransportReachable == true)
    #expect(snapshot.endpointProtocolCompatible == false)
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
            inboxTags: ["0-inbox", "next", "0-inbox"],
            bridgeHost: "127.0.0.1",
            bridgePort: 6190,
            defaultInsertPosition: .top,
            templateManagementEnabled: false,
            createOpensNoteByDefault: false,
            openUsesNewWindowByDefault: false,
            createAddsInboxTagsByDefault: false,
            tagsMergeMode: .replace,
            defaultDiscoveryLimit: 5,
            defaultSnippetLength: 50,
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

    #expect(configuration.inboxTags == ["0-inbox", "next"])
    #expect(configuration.defaultInsertPosition == .top)
    #expect(configuration.templateManagementEnabled == false)
    #expect(configuration.createOpensNoteByDefault == false)
    #expect(configuration.openUsesNewWindowByDefault == false)
    #expect(configuration.createAddsInboxTagsByDefault == false)
    #expect(configuration.tagsMergeMode == .replace)
    #expect(configuration.defaultDiscoveryLimit == 5)
    #expect(configuration.defaultSnippetLength == 50)
    #expect(configuration.backupRetentionDays == 7)
    #expect(configuration.disabledTools == [.addTags, .findNotes])
    #expect(configuration.runtimeConfigurationGeneration == 1)
    #expect(configuration.bridge == .default)
}

@Test
func saveConfigurationDraftPreservesExistingBridgeConfiguration() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)

    let initialConfiguration = BearConfiguration(
        inboxTags: ["0-inbox"],
        defaultInsertPosition: .bottom,
        templateManagementEnabled: true,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30,
        bridge: BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6205)
    )

    let encodedConfiguration = try BearJSON.makeEncoder().encode(initialConfiguration)
    try encodedConfiguration.write(to: configFileURL, options: .atomic)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    try BearAppSupport.saveConfigurationDraft(
        BearAppConfigurationDraft(
            inboxTags: ["0-inbox", "next"],
            bridgeHost: "127.0.0.1",
            bridgePort: 6205,
            defaultInsertPosition: .top,
            templateManagementEnabled: false,
            createOpensNoteByDefault: false,
            openUsesNewWindowByDefault: false,
            createAddsInboxTagsByDefault: false,
            tagsMergeMode: .replace,
            defaultDiscoveryLimit: 5,
            defaultSnippetLength: 50,
            backupRetentionDays: 7,
            disabledTools: []
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

    #expect(configuration.bridge == BearBridgeConfiguration(enabled: true, host: "127.0.0.1", port: 6205))
    #expect(configuration.runtimeConfigurationGeneration == 1)
}

@Test
func saveConfigurationDraftUpdatesBridgeHostAndPort() throws {
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
            inboxTags: ["0-inbox"],
            bridgeHost: "localhost",
            bridgePort: 6202,
            defaultInsertPosition: .bottom,
            templateManagementEnabled: true,
            createOpensNoteByDefault: true,
            openUsesNewWindowByDefault: true,
            createAddsInboxTagsByDefault: true,
            tagsMergeMode: .append,
            defaultDiscoveryLimit: 20,
            defaultSnippetLength: 280,
            backupRetentionDays: 30,
            disabledTools: []
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

    #expect(configuration.bridge == BearBridgeConfiguration(enabled: false, host: "localhost", port: 6202))
    #expect(configuration.runtimeConfigurationGeneration == 1)
}

@Test
func saveConfigurationDraftUpdatesBridgeAuthMode() throws {
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
            inboxTags: ["0-inbox"],
            bridgeHost: "127.0.0.1",
            bridgePort: 6190,
            bridgeRequiresOAuth: true,
            defaultInsertPosition: .bottom,
            templateManagementEnabled: true,
            createOpensNoteByDefault: true,
            openUsesNewWindowByDefault: true,
            createAddsInboxTagsByDefault: true,
            tagsMergeMode: .append,
            defaultDiscoveryLimit: 20,
            defaultSnippetLength: 280,
            backupRetentionDays: 30,
            disabledTools: []
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

    #expect(configuration.bridge == BearBridgeConfiguration(enabled: false, host: "127.0.0.1", port: 6190, authMode: .oauth))
    #expect(configuration.runtimeConfigurationGeneration == 1)
}

@Test
func bridgeResponseRequiresOAuthRecognizesBearerChallenges() throws {
    let response = try #require(
        HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:6190/mcp")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: ["WWW-Authenticate": #"Bearer realm="ursus-bridge""#]
        )
    )

    #expect(BearAppSupport.bridgeResponseRequiresOAuth(response) == true)
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
                inboxTags: [],
                bridgeHost: "",
                bridgePort: 90,
                defaultInsertPosition: .bottom,
                templateManagementEnabled: true,
                createOpensNoteByDefault: true,
                openUsesNewWindowByDefault: true,
                createAddsInboxTagsByDefault: true,
                tagsMergeMode: .append,
                defaultDiscoveryLimit: 20,
                defaultSnippetLength: 280,
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
            inboxTags: [],
            bridgeHost: "localhost",
            bridgePort: 90,
            defaultInsertPosition: .bottom,
            templateManagementEnabled: true,
            createOpensNoteByDefault: true,
            openUsesNewWindowByDefault: true,
            createAddsInboxTagsByDefault: true,
            tagsMergeMode: .append,
            defaultDiscoveryLimit: 20,
            defaultSnippetLength: 280,
            backupRetentionDays: -1,
            disabledTools: []
        )
    )

    #expect(report.issues(for: .inboxTags).count == 1)
    #expect(report.issues(for: .bridgePort).count == 1)
    #expect(report.issues(for: .backupRetentionDays).count == 1)
    #expect(report.hasErrors)
    #expect(report.warnings.count == 1)
}

@Test
func loadTemplateDraftReturnsCurrentTemplateContents() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{title}}\n\n{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let draft = try BearAppSupport.loadTemplateDraft(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )

    #expect(draft == "{{title}}\n\n{{content}}\n\n{{tags}}\n")
}

@Test
func saveTemplateDraftPersistsValidTemplate() throws {
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

    try BearAppSupport.saveTemplateDraft(
        "{{title}}\n\n{{content}}\n\n{{tags}}\n",
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )

    #expect(try String(contentsOf: templateURL, encoding: .utf8) == "{{title}}\n\n{{content}}\n\n{{tags}}\n")
}

@Test
func saveTemplateDraftRejectsMissingRequiredSlots() throws {
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
        try BearAppSupport.saveTemplateDraft(
            "{{content}}\n",
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
    }

    #expect(try String(contentsOf: templateURL, encoding: .utf8) == "{{content}}\n\n{{tags}}\n")
}

@Test
func dashboardSnapshotFlagsHostAppsThatNeedConfigUpdates() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let homeDirectoryURL = tempRoot.appendingPathComponent("home", isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
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
    [mcp_servers.ursus]
    enabled = true
    command = "/tmp/not-ursus-launcher"
    args = ["mcp"]
    """.write(to: codexConfigURL, atomically: true, encoding: .utf8)
    try "{ invalid json".write(to: claudeConfigURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        tokenStore: InMemoryBearTokenStore(),
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        launcherURL: launcherURL,
        homeDirectoryURL: homeDirectoryURL,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    let codexSetup = try #require(hostSetup(named: "codex", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(codexSetup.status == BearDoctorCheckStatus.invalid)
    #expect(codexSetup.detail.contains("public launcher path"))

    let claudeSetup = try #require(hostSetup(named: "claude-desktop", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(claudeSetup.status == BearDoctorCheckStatus.invalid)
    #expect(claudeSetup.detail.contains("could not be parsed as JSON"))

    let codexDiagnostic = try #require(diagnostic(named: "host-codex", in: dashboard.diagnostics))
    #expect(codexDiagnostic.status == BearDoctorCheckStatus.invalid)

    let claudeDiagnostic = try #require(diagnostic(named: "host-claude-desktop", in: dashboard.diagnostics))
    #expect(claudeDiagnostic.status == BearDoctorCheckStatus.invalid)
}


@Test
func dashboardSnapshotReportsKeychainBackedTokenStatus() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let tokenStore = InMemoryBearTokenStore(token: "keychain-token")

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        tokenStore: tokenStore,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings?.selectedNoteTokenConfigured == true)
    #expect(dashboard.settings?.selectedNoteTokenStorageDescription == "Stored in macOS Keychain")
    #expect(dashboard.diagnostics.contains(where: {
        $0.key == "selected-note-token"
            && $0.value == "Stored in macOS Keychain"
            && ($0.detail?.contains("macOS Keychain") ?? false)
    }))
}

@Test
func tokenManagementActionsSaveLoadAndRemoveSelectedNoteTokenInMemoryStore() throws {
    let tokenStore = InMemoryBearTokenStore(token: "legacy-token")
    try BearAppSupport.saveSelectedNoteToken(
        "new-config-token",
        tokenStore: tokenStore
    )
    #expect(try tokenStore.readToken() == "new-config-token")

    let resolved = try BearAppSupport.loadResolvedSelectedNoteToken(
        tokenStore: tokenStore
    )
    #expect(resolved?.value == "new-config-token")
    #expect(resolved?.source == .keychain)

    try BearAppSupport.removeSelectedNoteToken(
        tokenStore: tokenStore
    )
    #expect(try tokenStore.readToken() == nil)
}

@Test
func loadResolvedSelectedNoteTokenReadsTokenStoreValue() throws {
    let tokenStore = InMemoryBearTokenStore(token: "keychain-token")
    let resolved = try BearAppSupport.loadResolvedSelectedNoteToken(
        tokenStore: tokenStore
    )

    #expect(resolved?.value == "keychain-token")
    #expect(resolved?.source == .keychain)
}

@Test
func appSupportRoundTripsSelectedNoteTokenThroughKeychainWhenExplicitlyEnabled() throws {
    guard ProcessInfo.processInfo.environment["URSUS_RUN_KEYCHAIN_TESTS"] == "1" else {
        return
    }

    let tokenStore = BearKeychainTokenStore(
        service: "com.aft.ursus.tests.\(UUID().uuidString)",
        account: "selected-note-api-token"
    )
    defer {
        try? tokenStore.deleteToken()
    }

    try BearAppSupport.saveSelectedNoteToken(
        "app-support-keychain-token",
        tokenStore: tokenStore
    )

    let resolved = try BearAppSupport.loadResolvedSelectedNoteToken(
        tokenStore: tokenStore
    )
    #expect(resolved?.value == "app-support-keychain-token")
    #expect(resolved?.source == .keychain)

    try BearAppSupport.removeSelectedNoteToken(tokenStore: tokenStore)
    #expect(try BearAppSupport.loadResolvedSelectedNoteToken(tokenStore: tokenStore) == nil)
}

@Test
func prepareManagedSelectedNoteRequestURLRequiresConfiguredTokenForTokenlessSelectedNoteRequest() throws {
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

    do {
        _ = try BearAppSupport.prepareManagedSelectedNoteRequestURL(
            URL(string: "bear://x-callback-url/open-note?selected=yes&open_note=no&show_window=no")!,
            tokenStore: InMemoryBearTokenStore()
        )
        Issue.record("Expected missing-token error.")
    } catch let error as BearError {
        guard case .invalidInput(let message) = error else {
            Issue.record("Expected invalid-input error, got \(error).")
            return
        }
        #expect(message.contains("configured Bear API token"))
    }
}

@Test
func prepareManagedSelectedNoteRequestURLInjectsKeychainToken() throws {
    let requestURL = URL(string: "bear://x-callback-url/open-note?selected=yes&open_note=no&show_window=no")!
    let preparedURL = try BearAppSupport.prepareManagedSelectedNoteRequestURL(
        requestURL,
        tokenStore: InMemoryBearTokenStore(token: "keychain-token")
    )

    let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: preparedURL, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
    #expect(items["selected"] == "yes")
    #expect(items["token"] == "keychain-token")
}

@Test
func loadSettingsSnapshotReportsMissingTokenAsNotConfigured() throws {
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

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        tokenStore: InMemoryBearTokenStore(),
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings?.selectedNoteTokenConfigured == false)
    #expect(dashboard.settings?.selectedNoteTokenStorageDescription == "Not configured")
    #expect(dashboard.diagnostics.contains(where: {
        $0.key == "selected-note-token"
            && $0.value == "Not configured"
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
        tokenStore: InMemoryBearTokenStore(),
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

private final class LaunchctlRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var isLoaded: Bool
    private(set) var commands: [[String]] = []

    init(loaded: Bool = false) {
        isLoaded = loaded
    }

    var installRunner: BearLaunchctlCommandRunner {
        { [weak self] arguments in
            guard let self else {
                return BearProcessExecutionResult(exitCode: 1, stdout: "", stderr: "Recorder unavailable")
            }
            self.record(arguments)

            switch arguments.first {
            case "print":
                return BearProcessExecutionResult(exitCode: 3, stdout: "", stderr: "Could not find service")
            case "bootout":
                return BearProcessExecutionResult(exitCode: 3, stdout: "", stderr: "Could not find service")
            case "bootstrap":
                return BearProcessExecutionResult(exitCode: 0, stdout: "", stderr: "")
            default:
                return BearProcessExecutionResult(exitCode: 1, stdout: "", stderr: "Unexpected launchctl command")
            }
        }
    }

    var statefulRunner: BearLaunchctlCommandRunner {
        { [weak self] arguments in
            guard let self else {
                return BearProcessExecutionResult(exitCode: 1, stdout: "", stderr: "Recorder unavailable")
            }
            self.record(arguments)

            guard let command = arguments.first else {
                return BearProcessExecutionResult(exitCode: 1, stdout: "", stderr: "Missing launchctl command")
            }

            switch command {
            case "print":
                return self.isLoaded
                    ? BearProcessExecutionResult(exitCode: 0, stdout: "service = {}", stderr: "")
                    : BearProcessExecutionResult(exitCode: 3, stdout: "", stderr: "Could not find service")
            case "bootout":
                self.setLoaded(false)
                return BearProcessExecutionResult(exitCode: 0, stdout: "", stderr: "")
            case "bootstrap":
                self.setLoaded(true)
                return BearProcessExecutionResult(exitCode: 0, stdout: "", stderr: "")
            default:
                return BearProcessExecutionResult(exitCode: 1, stdout: "", stderr: "Unexpected launchctl command")
            }
        }
    }

    private func record(_ arguments: [String]) {
        lock.lock()
        commands.append(arguments)
        lock.unlock()
    }

    private func setLoaded(_ loaded: Bool) {
        lock.lock()
        isLoaded = loaded
        lock.unlock()
    }
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

private func availableLoopbackPort() throws -> Int {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
        }
    }
    guard bindResult == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    var boundAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(descriptor, $0, &length)
        }
    }
    guard nameResult == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    return Int(UInt16(bigEndian: boundAddress.sin_port))
}
