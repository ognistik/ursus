import BearCore
import Foundation
import Testing

@Test
func runtimeArtifactsUseLibraryLocations() {
    #expect(BearPaths.configDirectoryURL == BearPaths.applicationSupportDirectoryURL)
    #expect(BearPaths.configFileURL.path.hasSuffix("/Library/Application Support/Ursus/config.json"))
    #expect(BearPaths.noteTemplateURL.path.hasSuffix("/Library/Application Support/Ursus/template.md"))
    #expect(BearPaths.applicationSupportDirectoryURL.path.hasSuffix("/Library/Application Support/Ursus"))
    #expect(BearPaths.debugLogURL.path.hasSuffix("/Library/Application Support/Ursus/Logs/debug.log"))
    #expect(BearPaths.backupsDirectoryURL.path.hasSuffix("/Library/Application Support/Ursus/Backups"))
    #expect(BearPaths.backupsIndexURL.path.hasSuffix("/Library/Application Support/Ursus/Backups/index.json"))
    #expect(BearPaths.publicCLIDirectoryURL.path.hasSuffix("/.local/bin"))
    #expect(BearPaths.publicCLIExecutableURL.path.hasSuffix("/.local/bin/bear-mcp"))
    #expect(BearPaths.processLockURL.path.hasSuffix("/Library/Application Support/Ursus/Runtime/.server.lock"))
    #expect(BearPaths.fallbackProcessLockURL.path.hasSuffix("/ursus/Runtime/.server.lock"))
    #expect(BearPaths.processSpecificFallbackLockURL(processID: 123).path.hasSuffix("/ursus/Runtime/locks/123.server.lock"))
    #expect(BearBridgeLaunchAgent.plistURL.path.hasSuffix("/Library/LaunchAgents/com.aft.ursus.plist"))
    #expect(BearBridgeLaunchAgent.standardOutputURL.path.hasSuffix("/Library/Application Support/Ursus/Logs/bridge.stdout.log"))
    #expect(BearBridgeLaunchAgent.standardErrorURL.path.hasSuffix("/Library/Application Support/Ursus/Logs/bridge.stderr.log"))
}

@Test
func debugLogRotatesAfterSizeThreshold() throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let logDirectoryURL = temporaryDirectory.appendingPathComponent("Logs", isDirectory: true)
    let logURL = logDirectoryURL.appendingPathComponent("debug.log", isDirectory: false)
    try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    let oversizedData = Data(repeating: 0x61, count: 1_048_576)
    try oversizedData.write(to: logURL, options: .atomic)

    BearDebugLog.append(
        "rotation-check",
        fileManager: fileManager,
        logURL: logURL,
        logsDirectoryURL: logDirectoryURL
    )

    let firstArchive = logDirectoryURL.appendingPathComponent("debug.log.1", isDirectory: false)
    #expect(fileManager.fileExists(atPath: firstArchive.path))
    #expect(fileManager.fileExists(atPath: logURL.path))

    let rotatedContents = try String(contentsOf: logURL, encoding: .utf8)
    #expect(rotatedContents.contains("rotation-check"))
}

@Test
func debugLogIgnoresLegacyPreReleaseLogs() throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let legacyLogsDirectoryURL = temporaryDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
    let logsDirectoryURL = temporaryDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Ursus", isDirectory: true)
        .appendingPathComponent("Logs", isDirectory: true)
    let logURL = logsDirectoryURL.appendingPathComponent("debug.log", isDirectory: false)

    try fileManager.createDirectory(at: legacyLogsDirectoryURL, withIntermediateDirectories: true)
    try "legacy log line\n".write(
        to: legacyLogsDirectoryURL.appendingPathComponent("debug.log", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
    defer {
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    BearDebugLog.append(
        "migration-check",
        fileManager: fileManager,
        logURL: logURL,
        logsDirectoryURL: logsDirectoryURL
    )

    #expect(fileManager.fileExists(atPath: logURL.path))
    #expect(fileManager.fileExists(atPath: legacyLogsDirectoryURL.path))

    let logContents = try String(contentsOf: logURL, encoding: .utf8)
    let legacyContents = try String(contentsOf: legacyLogsDirectoryURL.appendingPathComponent("debug.log"), encoding: .utf8)
    #expect(logContents.contains("migration-check"))
    #expect(logContents.contains("legacy log line") == false)
    #expect(legacyContents.contains("legacy log line"))
}
