import BearCore
import Foundation
import Testing

@Test
func appLocatorGuidanceMarksSystemApplicationsAsPreferred() {
    #expect(BearMCPAppLocator.preferredAppBundleURL.path == "/Applications/Bear MCP.app")
    #expect(BearMCPAppLocator.installGuidance.contains("`/Applications/Bear MCP.app` (preferred)"))
    #expect(
        BearMCPAppLocator.installationLocationDescription(
            forAppBundleURL: BearMCPAppLocator.preferredAppBundleURL
        ) == "preferred install location"
    )
}

@Test
func appLocatorGuidanceMarksUserApplicationsAsSupportedUserSpecificLocation() {
    #expect(
        BearMCPAppLocator.installationLocationDescription(
            forAppBundleURL: BearMCPAppLocator.userSpecificAppBundleURL
        ) == "supported user-specific install location"
    )
    #expect(
        BearSelectedNoteHelperLocator.installationLocationDescription(
            forAppBundleURL: BearSelectedNoteHelperLocator.userSpecificAppBundleURL
        ) == "supported user-specific install location"
    )
}

@Test
func cliLocatorGuidancePointsHostsAtPublicLauncherPath() {
    #expect(BearMCPCLILocator.bundledRelativePath == "Contents/Resources/bin/bear-mcp")
    #expect(
        BearMCPCLILocator.publicLauncherURL.path.hasSuffix("/.local/bin/bear-mcp")
    )
    #expect(BearMCPCLILocator.publicLauncherGuidance.contains("Local MCP hosts and Terminal should use that same path"))
}

@Test
func cliLocatorInstallsPublicLauncherIntoStablePath() throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = temporaryRoot.appendingPathComponent("Bear MCP.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let installedCLIURL = temporaryRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let receipt = try BearMCPCLILocator.installPublicLauncher(
        fromAppBundleURL: appBundleURL,
        fileManager: fileManager,
        destinationURL: installedCLIURL
    )

    #expect(receipt.sourcePath == bundledCLIURL.path)
    #expect(receipt.destinationPath == installedCLIURL.path)
    #expect(fileManager.fileExists(atPath: installedCLIURL.path))
    #expect(fileManager.isExecutableFile(atPath: installedCLIURL.path))
    let launcherScript = try String(contentsOf: installedCLIURL, encoding: .utf8)
    #expect(launcherScript.contains(bundledCLIURL.path))
    #expect(launcherScript.contains("exec \"$cli_path\" \"$@\""))
}

@Test
func cliLocatorLauncherRepairsOlderSymlinkInstall() throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = temporaryRoot.appendingPathComponent("Bear MCP.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let launcherURL = temporaryRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launcherURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    try fileManager.createSymbolicLink(at: launcherURL, withDestinationURL: bundledCLIURL)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let receipt = try BearMCPCLILocator.installPublicLauncher(
        fromAppBundleURL: appBundleURL,
        fileManager: fileManager,
        destinationURL: launcherURL
    )

    #expect(receipt.sourcePath == bundledCLIURL.path)
    #expect(receipt.destinationPath == launcherURL.path)
    #expect(fileManager.fileExists(atPath: launcherURL.path))
    #expect(fileManager.isExecutableFile(atPath: launcherURL.path))
    #expect(try String(contentsOf: launcherURL, encoding: .utf8).contains("Bear MCP launcher"))
    #expect(!BearMCPCLILocator.hasIndirectFilesystemEntry(at: launcherURL))
}
