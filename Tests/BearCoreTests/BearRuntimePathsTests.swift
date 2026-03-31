import BearCore
import Foundation
import Testing

@Test
func runtimeArtifactsUseLibraryLocations() {
    #expect(BearPaths.configFileURL.path.hasSuffix("/.config/bear-mcp/config.json"))
    #expect(BearPaths.noteTemplateURL.path.hasSuffix("/.config/bear-mcp/template.md"))
    #expect(BearPaths.applicationSupportDirectoryURL.path.hasSuffix("/Library/Application Support/Bear MCP"))
    #expect(BearPaths.debugLogURL.path.hasSuffix("/Library/Application Support/Bear MCP/Logs/debug.log"))
    #expect(BearPaths.backupsDirectoryURL.path.hasSuffix("/Library/Application Support/Bear MCP/Backups"))
    #expect(BearPaths.backupsIndexURL.path.hasSuffix("/Library/Application Support/Bear MCP/Backups/index.json"))
    #expect(BearPaths.publicCLIDirectoryURL.path.hasSuffix("/.local/bin"))
    #expect(BearPaths.publicCLIExecutableURL.path.hasSuffix("/.local/bin/bear-mcp"))
    #expect(BearPaths.processLockURL.path.hasSuffix("/Library/Application Support/Bear MCP/Runtime/.server.lock"))
    #expect(BearPaths.fallbackProcessLockURL.path.hasSuffix("/bear-mcp/Runtime/.server.lock"))
    #expect(BearPaths.processSpecificFallbackLockURL(processID: 123).path.hasSuffix("/bear-mcp/Runtime/locks/123.server.lock"))
    #expect(BearBridgeLaunchAgent.plistURL.path.hasSuffix("/Library/LaunchAgents/com.aft.ursus.plist"))
    #expect(BearBridgeLaunchAgent.standardOutputURL.path.hasSuffix("/Library/Application Support/Bear MCP/Logs/bridge.stdout.log"))
    #expect(BearBridgeLaunchAgent.standardErrorURL.path.hasSuffix("/Library/Application Support/Bear MCP/Logs/bridge.stderr.log"))
}

@Test
func debugLogRotatesAfterSizeThreshold() throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let logDirectoryURL = temporaryDirectory.appendingPathComponent("Logs", isDirectory: true)
    let legacyLogsDirectoryURL = temporaryDirectory.appendingPathComponent("LegacyLogs", isDirectory: true)
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
        logsDirectoryURL: logDirectoryURL,
        legacyLogsDirectoryURL: legacyLogsDirectoryURL
    )

    let firstArchive = logDirectoryURL.appendingPathComponent("debug.log.1", isDirectory: false)
    #expect(fileManager.fileExists(atPath: firstArchive.path))
    #expect(fileManager.fileExists(atPath: logURL.path))

    let rotatedContents = try String(contentsOf: logURL, encoding: .utf8)
    #expect(rotatedContents.contains("rotation-check"))
}

@Test
func debugLogMigratesLegacyLogsIntoApplicationSupport() throws {
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
        .appendingPathComponent("Bear MCP", isDirectory: true)
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
        logsDirectoryURL: logsDirectoryURL,
        legacyLogsDirectoryURL: legacyLogsDirectoryURL
    )

    #expect(fileManager.fileExists(atPath: logURL.path))
    #expect(fileManager.fileExists(atPath: legacyLogsDirectoryURL.path) == false)

    let migratedContents = try String(contentsOf: logURL, encoding: .utf8)
    #expect(migratedContents.contains("legacy log line"))
    #expect(migratedContents.contains("migration-check"))
}
