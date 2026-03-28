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
        tokenStore: TestSelectedNoteTokenStore(),
        callbackAppBundleURLProvider: { _ in nil },
        helperBundleURLProvider: { _ in nil }
    )

    #expect(dashboard.settings != nil)
    #expect(dashboard.settingsError == nil)
    #expect(dashboard.settings?.databasePath == "/tmp/bear.sqlite")
    #expect(dashboard.settings?.activeTags == ["0-inbox", "next"])
    #expect(dashboard.settings?.createAddsActiveTagsByDefault == false)
    #expect(dashboard.settings?.selectedNoteTokenConfigured == true)
    #expect(dashboard.settings?.selectedNoteTokenStoredInKeychain == false)
    #expect(dashboard.settings?.selectedNoteLegacyConfigTokenDetected == true)
    #expect(dashboard.settings?.selectedNoteTokenStorageDescription == "Legacy config.json fallback")
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
        tokenStore: TestSelectedNoteTokenStore(storedToken: "keychain-token"),
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
            && check.detail == "detected install location; preferred host -> \(appBundleURL.path)/Contents/MacOS/Bear MCP"
    }
    let hasHelperFallbackDiagnostic = dashboard.diagnostics.contains { check in
        check.key == "selected-note-helper-fallback"
            && check.status == .ok
            && check.value == helperBundleURL.path
            && check.detail == "helper fallback; detected install location -> \(helperBundleURL.path)/Contents/MacOS/bear-mcp-helper"
    }

    #expect(hasPreferredAppDiagnostic)
    #expect(hasHelperFallbackDiagnostic)
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
        tokenStore: TestSelectedNoteTokenStore(storedToken: "keychain-token")
    )

    #expect(settings.selectedNoteTokenStoredInKeychain == true)
    #expect(try BearConfiguration.load(from: configFileURL).selectedNoteTokenStoredInKeychain == true)
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
