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
func cliLocatorGuidancePointsHostsAtAppManagedPath() {
    #expect(BearMCPCLILocator.bundledRelativePath == "Contents/Resources/bin/bear-mcp")
    #expect(
        BearMCPCLILocator.appManagedInstallURL.path.hasSuffix("/Library/Application Support/bear-mcp/bin/bear-mcp")
    )
    #expect(BearMCPCLILocator.appManagedInstallGuidance.contains("MCP hosts should point to that stable path"))
}

@Test
func cliLocatorInstallsBundledExecutableIntoStablePath() throws {
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
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: bundledCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\necho bundled\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let receipt = try BearMCPCLILocator.installBundledExecutable(
        fromAppBundleURL: appBundleURL,
        fileManager: fileManager,
        destinationURL: installedCLIURL
    )

    #expect(receipt.sourcePath == bundledCLIURL.path)
    #expect(receipt.destinationPath == installedCLIURL.path)
    #expect(fileManager.fileExists(atPath: installedCLIURL.path))
    #expect(fileManager.isExecutableFile(atPath: installedCLIURL.path))
    #expect(try String(contentsOf: installedCLIURL, encoding: .utf8).contains("bundled"))
}

@Test
func cliLocatorInstallsCopiedTerminalExecutableInsteadOfSymlink() throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appManagedCLIURL = temporaryRoot
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)
    let terminalCLIURL = temporaryRoot
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("bear-mcp", isDirectory: false)

    try fileManager.createDirectory(at: appManagedCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\necho app-managed\n".write(to: appManagedCLIURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appManagedCLIURL.path)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let receipt = try BearMCPCLILocator.installUserCommandExecutable(
        fileManager: fileManager,
        sourceURL: appManagedCLIURL,
        destinationURL: terminalCLIURL
    )

    #expect(receipt.sourcePath == appManagedCLIURL.path)
    #expect(receipt.destinationPath == terminalCLIURL.path)
    #expect(fileManager.fileExists(atPath: terminalCLIURL.path))
    #expect(fileManager.isExecutableFile(atPath: terminalCLIURL.path))
    #expect(try String(contentsOf: terminalCLIURL, encoding: .utf8).contains("app-managed"))
    #expect(!BearMCPCLILocator.hasIndirectFilesystemEntry(at: terminalCLIURL))
}
