import BearApplication
import BearCore
import Foundation
import Testing

@Test
func loadAndSaveConfigurationFillMissingKeysAndPreserveExistingValues() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try """
    {
      "databasePath" : "/tmp/custom.sqlite",
      "inboxTags" : [
        "inbox",
        "next"
      ],
      "token" : "secret-token"
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let configuration = try BearRuntimeBootstrap.loadConfiguration(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )
    try BearRuntimeBootstrap.saveConfiguration(
        configuration,
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )
    let updatedOnDisk = try BearConfiguration.load(from: configFileURL)
    let updatedText = try String(contentsOf: configFileURL)

    #expect(configuration.databasePath == "/tmp/custom.sqlite")
    #expect(configuration.inboxTags == ["inbox", "next"])
    #expect(updatedOnDisk.databasePath == "/tmp/custom.sqlite")
    #expect(updatedOnDisk.inboxTags == ["inbox", "next"])
    #expect(updatedOnDisk.defaultDiscoveryLimit == BearConfiguration.default.defaultDiscoveryLimit)
    #expect(updatedOnDisk.maxDiscoveryLimit == BearConfiguration.default.maxDiscoveryLimit)
    #expect(updatedOnDisk.defaultSnippetLength == BearConfiguration.default.defaultSnippetLength)
    #expect(updatedOnDisk.maxSnippetLength == BearConfiguration.default.maxSnippetLength)
    #expect(updatedOnDisk.backupRetentionDays == BearConfiguration.default.backupRetentionDays)
    #expect(updatedOnDisk.token == "secret-token")
    #expect(updatedText.contains("\"defaultDiscoveryLimit\""))
    #expect(updatedText.contains("\"maxSnippetLength\""))
    #expect(updatedText.contains("\"backupRetentionDays\""))
    #expect(updatedText.contains("\"token\" : \"secret-token\""))
    #expect(updatedText.contains("\"databasePath\" : \"/tmp/custom.sqlite\""))
    #expect(!updatedText.contains("\\/"))
    #expect(fileManager.fileExists(atPath: templateURL.path))
}

@Test
func saveConfigurationOmitsMissingTokenField() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try "{}".write(to: configFileURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let configuration = try BearRuntimeBootstrap.loadConfiguration(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )
    try BearRuntimeBootstrap.saveConfiguration(
        configuration,
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )

    let updatedText = try String(contentsOf: configFileURL)
    #expect(!updatedText.contains("\"token\""))
}

@Test
func prepareSupportFilesMigratesLegacyApplicationSupportRoot() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let legacyApplicationSupportDirectoryURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
    let applicationSupportDirectoryURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Bear MCP", isDirectory: true)

    let legacyRuntimeDirectoryURL = legacyApplicationSupportDirectoryURL.appendingPathComponent("Runtime", isDirectory: true)
    let legacyBackupsDirectoryURL = legacyApplicationSupportDirectoryURL.appendingPathComponent("Backups", isDirectory: true)
    let legacyBackupFileURL = legacyBackupsDirectoryURL.appendingPathComponent("snapshot.json", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    try fileManager.createDirectory(at: legacyRuntimeDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: legacyBackupsDirectoryURL, withIntermediateDirectories: true)
    try "123\n".write(
        to: legacyRuntimeDirectoryURL.appendingPathComponent(".server.lock", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
    try "{}".write(to: legacyBackupFileURL, atomically: true, encoding: .utf8)

    try BearRuntimeBootstrap.prepareSupportFiles(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        applicationSupportDirectoryURL: applicationSupportDirectoryURL,
        legacyApplicationSupportDirectoryURL: legacyApplicationSupportDirectoryURL
    )

    #expect(fileManager.fileExists(atPath: configFileURL.path))
    #expect(fileManager.fileExists(atPath: templateURL.path))
    #expect(
        fileManager.fileExists(
            atPath: applicationSupportDirectoryURL
                .appendingPathComponent("Runtime", isDirectory: true)
                .appendingPathComponent(".server.lock", isDirectory: false)
                .path
        )
    )
    #expect(
        fileManager.fileExists(
            atPath: applicationSupportDirectoryURL
                .appendingPathComponent("Backups", isDirectory: true)
                .appendingPathComponent("snapshot.json", isDirectory: false)
                .path
        )
    )
    #expect(fileManager.fileExists(atPath: legacyApplicationSupportDirectoryURL.path) == false)
}

@Test
func prepareSupportFilesMovesLegacyBackupsIntoExistingNewSupportRoot() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    let legacyApplicationSupportDirectoryURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
    let applicationSupportDirectoryURL = tempRoot
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Bear MCP", isDirectory: true)

    let legacyBackupsDirectoryURL = legacyApplicationSupportDirectoryURL.appendingPathComponent("Backups", isDirectory: true)
    let existingLogsDirectoryURL = applicationSupportDirectoryURL.appendingPathComponent("Logs", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    try fileManager.createDirectory(at: existingLogsDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: legacyBackupsDirectoryURL, withIntermediateDirectories: true)
    try """
    {
      "entries" : [
        {
          "capturedAt" : "2026-03-29T12:00:00Z",
          "fileName" : "legacy-snapshot.json",
          "modifiedAt" : "2026-03-29T11:00:00Z",
          "noteID" : "note-1",
          "operationGroupID" : "op-1",
          "reason" : "replaceContent",
          "snapshotID" : "snapshot-1",
          "snippet" : "Legacy body",
          "title" : "Legacy Note",
          "version" : 7
        }
      ]
    }
    """.write(
        to: legacyBackupsDirectoryURL.appendingPathComponent("index.json", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
    try "{}".write(
        to: legacyBackupsDirectoryURL.appendingPathComponent("legacy-snapshot.json", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )

    try BearRuntimeBootstrap.prepareSupportFiles(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL,
        applicationSupportDirectoryURL: applicationSupportDirectoryURL,
        legacyApplicationSupportDirectoryURL: legacyApplicationSupportDirectoryURL
    )

    let migratedIndexURL = applicationSupportDirectoryURL.appendingPathComponent("Backups/index.json", isDirectory: false)
    let migratedIndexText = try String(contentsOf: migratedIndexURL, encoding: .utf8)

    #expect(
        fileManager.fileExists(
            atPath: applicationSupportDirectoryURL
                .appendingPathComponent("Backups", isDirectory: true)
                .appendingPathComponent("legacy-snapshot.json", isDirectory: false)
                .path
        )
    )
    #expect(migratedIndexText.contains("\"snapshotID\" : \"snapshot-1\""))
    #expect(fileManager.fileExists(atPath: legacyBackupsDirectoryURL.path) == false)
}
