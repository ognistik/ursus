import BearApplication
import BearCore
import BearXCallback
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
        launcherURL: launcherURL,
        homeDirectoryURL: homeDirectoryURL,
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings != nil)
    #expect(dashboard.settingsError == nil)
    #expect(dashboard.settings?.databasePath == "/tmp/bear.sqlite")
    #expect(dashboard.settings?.inboxTags == ["0-inbox", "next"])
    #expect(dashboard.settings?.createAddsInboxTagsByDefault == false)
    #expect(dashboard.settings?.launcherPath == launcherURL.path)
    #expect(dashboard.settings?.launcherStatus == BearDoctorCheckStatus.missing)
    #expect(dashboard.settings?.launcherStatusTitle == "Not installed")
    #expect(dashboard.settings?.launcherStatusDetail == "Install the public launcher once so local MCP hosts and Terminal can run Bear MCP from one shared path.")
    #expect(dashboard.settings?.cliMaintenancePrompt?.actions == [BearAppCLIMaintenanceAction.installLauncher])
    #expect(dashboard.settings?.selectedNoteTokenConfigured == true)
    #expect(dashboard.settings?.selectedNoteTokenStorageDescription == "Stored in config.json")

    let bundledCLIDiagnostic = try #require(diagnostic(named: "bundled-cli", in: dashboard.diagnostics))
    #expect(bundledCLIDiagnostic.status == BearDoctorCheckStatus.missing)
    #expect(bundledCLIDiagnostic.detail == BearMCPCLILocator.bundledExecutableGuidance)

    let launcherDiagnostic = try #require(diagnostic(named: "public-cli-launcher", in: dashboard.diagnostics))
    #expect(launcherDiagnostic.status == BearDoctorCheckStatus.missing)
    #expect(launcherDiagnostic.value == launcherURL.path)
    #expect(launcherDiagnostic.detail == "Install the public launcher once so local MCP hosts and Terminal can run Bear MCP from one shared path.")

    let callbackDiagnostic = try #require(diagnostic(named: "selected-note-callback-app", in: dashboard.diagnostics))
    #expect(callbackDiagnostic.status == BearDoctorCheckStatus.missing)
    #expect(callbackDiagnostic.detail?.contains("install `Bear MCP.app` in `/Applications/Bear MCP.app` (preferred).") == true)
    #expect(callbackDiagnostic.detail?.contains("fully supported for user-specific installs") == true)
    #expect(!dashboard.diagnostics.contains(where: { $0.key == "selected-note-helper-fallback" }))
}

@Test
func dashboardSnapshotIncludesPreferredAppAndHelperDiagnosticsWithHealthyLauncher() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appBundleURL = tempRoot.appendingPathComponent("Bear MCP.app", isDirectory: true)
    let helperBundleURL = tempRoot.appendingPathComponent("Bear MCP Helper.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: helperBundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    _ = try BearMCPCLILocator.installPublicLauncher(
        fromAppBundleURL: appBundleURL,
        fileManager: fileManager,
        destinationURL: launcherURL
    )
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let dashboard = BearAppSupport.loadDashboardSnapshot(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        currentAppBundleURL: appBundleURL,
        launcherURL: launcherURL,
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

    let helperFallbackDiagnostic = try #require(diagnostic(named: "selected-note-helper-fallback", in: dashboard.diagnostics))
    #expect(helperFallbackDiagnostic.status == BearDoctorCheckStatus.ok)
    #expect(helperFallbackDiagnostic.value == helperBundleURL.path)
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
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    try "{{content}}\n\n{{tags}}\n".write(to: templateURL, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(to: launcherURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)
    try """
    [mcp_servers.bear]
    enabled = true
    command = "\(launcherURL.path)"
    args = ["mcp"]
    """.write(to: codexConfigURL, atomically: true, encoding: .utf8)
    try """
    {
      "mcpServers": {
        "bear": {
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

    let claudeSetup = try #require(hostSetup(named: "claude-desktop", in: dashboard.settings?.hostAppSetups ?? []))
    #expect(claudeSetup.status == BearDoctorCheckStatus.ok)
    #expect(claudeSetup.configPath == claudeConfigURL.path)

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
    let appBundleURL = tempRoot.appendingPathComponent("Bear MCP.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

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
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        currentAppBundleURL: appBundleURL,
        launcherURL: launcherURL,
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
    let appBundleURL = tempRoot.appendingPathComponent("Bear MCP.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

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
    #expect(try String(contentsOf: launcherURL, encoding: .utf8).contains("Bear MCP launcher"))
}

@Test
func reconcilePublicLauncherRepairsStaleLauncher() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = tempRoot.appendingPathComponent("Bear MCP.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

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
    #expect(try String(contentsOf: launcherURL, encoding: .utf8).contains("Bear MCP launcher"))
}

@Test
func reconcilePublicLauncherReturnsUnchangedWhenLauncherMatchesBundle() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = tempRoot.appendingPathComponent("Bear MCP.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let launcherURL = tempRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    _ = try BearMCPCLILocator.installPublicLauncher(
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
func dashboardSnapshotReportsConfigBackedTokenStatus() throws {
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
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings?.selectedNoteTokenConfigured == true)
    #expect(dashboard.settings?.selectedNoteTokenStorageDescription == "Stored in config.json")
    #expect(dashboard.diagnostics.contains(where: {
        $0.key == "selected-note-token"
            && $0.value == "Stored in config.json"
            && ($0.detail?.contains("config.json") ?? false)
    }))
}

@Test
func tokenManagementActionsSaveLoadAndRemoveSelectedNoteTokenInConfig() throws {
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

    try BearAppSupport.saveSelectedNoteToken(
        "new-config-token",
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )
    let savedConfiguration = try BearConfiguration.load(from: configFileURL)
    #expect(savedConfiguration.token == "new-config-token")

    let resolved = try BearAppSupport.loadResolvedSelectedNoteToken(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )
    #expect(resolved?.value == "new-config-token")
    #expect(resolved?.source == .config)

    try """
    {
      "token" : "remove-me-too"
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
    try BearAppSupport.removeSelectedNoteToken(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )
    let removedConfiguration = try BearConfiguration.load(from: configFileURL)
    #expect(removedConfiguration.token == nil)
}

@Test
func loadResolvedSelectedNoteTokenReadsConfigValue() throws {
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

    let resolved = try BearAppSupport.loadResolvedSelectedNoteToken(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )

    #expect(resolved?.value == "legacy-token")
    #expect(resolved?.source == .config)
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
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
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
func prepareManagedSelectedNoteRequestURLInjectsConfigToken() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try """
    {
      "token" : "config-token"
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
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
        templateURL: templateURL
    )

    let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: preparedURL, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
    #expect(items["selected"] == "yes")
    #expect(items["token"] == "config-token")
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
