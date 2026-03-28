import BearApplication
import BearCore
import Foundation
import Testing

@Test
func updateConfigurationFileFillsMissingKeysAndPreservesExistingValues() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configDirectoryURL = tempRoot.appendingPathComponent("config", isDirectory: true)
    let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    let templateURL = configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)

    try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try """
    {
      "databasePath" : "/tmp/custom.sqlite",
      "activeTags" : [
        "inbox",
        "next"
      ],
      "token" : "secret-token"
    }
    """.write(to: configFileURL, atomically: true, encoding: .utf8)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let configuration = try BearRuntimeBootstrap.updateConfigurationFile(
        fileManager: fileManager,
        configDirectoryURL: configDirectoryURL,
        configFileURL: configFileURL,
        templateURL: templateURL
    )
    let updatedOnDisk = try BearConfiguration.load(from: configFileURL)
    let updatedText = try String(contentsOf: configFileURL)

    #expect(configuration.databasePath == "/tmp/custom.sqlite")
    #expect(configuration.activeTags == ["inbox", "next"])
    #expect(updatedOnDisk.databasePath == "/tmp/custom.sqlite")
    #expect(updatedOnDisk.activeTags == ["inbox", "next"])
    #expect(updatedOnDisk.defaultDiscoveryLimit == BearConfiguration.default.defaultDiscoveryLimit)
    #expect(updatedOnDisk.maxDiscoveryLimit == BearConfiguration.default.maxDiscoveryLimit)
    #expect(updatedOnDisk.defaultSnippetLength == BearConfiguration.default.defaultSnippetLength)
    #expect(updatedOnDisk.maxSnippetLength == BearConfiguration.default.maxSnippetLength)
    #expect(updatedOnDisk.backupRetentionDays == BearConfiguration.default.backupRetentionDays)
    #expect(updatedOnDisk.selectedNoteTokenStoredInKeychain == false)
    #expect(updatedOnDisk.token == "secret-token")
    #expect(updatedText.contains("\"defaultDiscoveryLimit\""))
    #expect(updatedText.contains("\"maxSnippetLength\""))
    #expect(updatedText.contains("\"backupRetentionDays\""))
    #expect(updatedText.contains("\"selectedNoteTokenStoredInKeychain\" : false"))
    #expect(updatedText.contains("\"token\" : \"secret-token\""))
    #expect(updatedText.contains("\"databasePath\" : \"/tmp/custom.sqlite\""))
    #expect(!updatedText.contains("\\/"))
    #expect(fileManager.fileExists(atPath: templateURL.path))
}
