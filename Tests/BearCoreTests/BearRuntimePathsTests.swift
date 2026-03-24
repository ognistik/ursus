import BearCore
import Foundation
import Testing

@Test
func runtimeArtifactsUseLibraryLocations() {
    #expect(BearPaths.configFileURL.path.hasSuffix("/.config/bear-mcp/config.json"))
    #expect(BearPaths.noteTemplateURL.path.hasSuffix("/.config/bear-mcp/template.md"))
    #expect(BearPaths.debugLogURL.path.hasSuffix("/Library/Logs/bear-mcp/debug.log"))
    #expect(BearPaths.processLockURL.path.hasSuffix("/Library/Application Support/bear-mcp/Runtime/.server.lock"))
}

@Test
func debugLogRotatesAfterSizeThreshold() throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let logDirectoryURL = temporaryDirectory.appendingPathComponent("Logs", isDirectory: true)
    let logURL = logDirectoryURL.appendingPathComponent("debug.log", isDirectory: false)
    try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)

    let oversizedData = Data(repeating: 0x61, count: 1_048_576)
    try oversizedData.write(to: logURL, options: .atomic)

    BearDebugLog.append("rotation-check", fileManager: fileManager, logURL: logURL, logsDirectoryURL: logDirectoryURL)

    let firstArchive = logDirectoryURL.appendingPathComponent("debug.log.1", isDirectory: false)
    #expect(fileManager.fileExists(atPath: firstArchive.path))
    #expect(fileManager.fileExists(atPath: logURL.path))

    let rotatedContents = try String(contentsOf: logURL, encoding: .utf8)
    #expect(rotatedContents.contains("rotation-check"))
}
