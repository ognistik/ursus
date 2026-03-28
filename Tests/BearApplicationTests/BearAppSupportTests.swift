import BearApplication
import Foundation
import Testing

@Test
func dashboardSnapshotIncludesSettingsWhenConfigurationLoads() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try """
    {
      "databasePath" : "/tmp/bear.sqlite",
      "activeTags" : [
        "0-inbox",
        "next"
      ],
      "createAddsActiveTagsByDefault" : false,
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
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings != nil)
    #expect(dashboard.settingsError == nil)
    #expect(dashboard.settings?.databasePath == "/tmp/bear.sqlite")
    #expect(dashboard.settings?.activeTags == ["0-inbox", "next"])
    #expect(dashboard.settings?.createAddsActiveTagsByDefault == false)
    #expect(dashboard.settings?.selectedNoteTokenConfigured == true)
    #expect(dashboard.diagnostics.contains(where: { $0.key == "selected-note-token" && $0.value == "configured" }))
    #expect(dashboard.diagnostics.contains(where: { $0.key == "selected-note-callback-app" && $0.status == .missing }))
    #expect(!dashboard.diagnostics.contains(where: { $0.key == "selected-note-helper-fallback" }))
}

@Test
func dashboardSnapshotIncludesPreferredAppAndLegacyHelperDiagnostics() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let appBundleURL = tempRoot.appendingPathComponent("Bear MCP.app", isDirectory: true)
    let helperBundleURL = tempRoot.appendingPathComponent("Bear MCP Helper.app", isDirectory: true)

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

    let hasPreferredAppDiagnostic = dashboard.diagnostics.contains { check in
        check.key == "selected-note-callback-app"
            && check.status == .ok
            && check.value == appBundleURL.path
    }
    let hasHelperFallbackDiagnostic = dashboard.diagnostics.contains { check in
        check.key == "selected-note-helper-fallback"
            && check.status == .ok
            && check.value == helperBundleURL.path
    }

    #expect(hasPreferredAppDiagnostic)
    #expect(hasHelperFallbackDiagnostic)
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
