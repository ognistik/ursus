import BearCore
import Foundation
import Testing

@Test
func appLocatorGuidanceMarksSystemApplicationsAsPreferred() {
    #expect(BearMCPAppLocator.preferredAppBundleURL.path == "/Applications/Ursus.app")
    #expect(BearMCPAppLocator.installGuidance.contains("`/Applications/Ursus.app` (preferred)"))
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
}

@Test
func cliLocatorGuidancePointsHostsAtPublicLauncherPath() {
    #expect(BearMCPCLILocator.bundledRelativePath == "Contents/Resources/bin/ursus")
    #expect(
        BearMCPCLILocator.publicLauncherURL.path.hasSuffix("/.local/bin/ursus")
    )
    #expect(BearMCPCLILocator.publicLauncherGuidance.contains("Local MCP hosts and Terminal should use that same path"))
}

@Test
func cliLocatorInstallsPublicLauncherIntoStablePath() throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appBundleURL = temporaryRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let installedCLIURL = temporaryRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)

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
    let appBundleURL = temporaryRoot.appendingPathComponent("Ursus.app", isDirectory: true)
    let bundledCLIURL = appBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)
    let launcherURL = temporaryRoot
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("ursus", isDirectory: false)

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
    #expect(try String(contentsOf: launcherURL, encoding: .utf8).contains("Ursus launcher"))
    #expect(!BearMCPCLILocator.hasIndirectFilesystemEntry(at: launcherURL))
}

@Test
func helperLocatorPrefersEmbeddedHelperInsideInstalledAppBundle() throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let applicationsDirectoryURL = temporaryRoot.appendingPathComponent("Applications", isDirectory: true)
    let userHomeURL = temporaryRoot.appendingPathComponent("home", isDirectory: true)
    let mainAppBundleURL = applicationsDirectoryURL.appendingPathComponent("Ursus.app", isDirectory: true)
    let embeddedHelperBundleURL = mainAppBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Helpers", isDirectory: true)
        .appendingPathComponent("Ursus Helper.app", isDirectory: true)

    try fileManager.createDirectory(at: embeddedHelperBundleURL, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    let locatedURL = BearSelectedNoteHelperLocator.installedAppBundleURL(
        fileManager: fileManager,
        preferredAppBundleURL: mainAppBundleURL,
        userSpecificAppBundleURL: userHomeURL.appendingPathComponent("Applications/Ursus.app", isDirectory: true)
    )

    #expect(locatedURL?.standardizedFileURL == embeddedHelperBundleURL.standardizedFileURL)
    #expect(
        BearSelectedNoteHelperLocator.installationLocationDescription(
            forAppBundleURL: embeddedHelperBundleURL
        ) == "embedded in \(mainAppBundleURL.path)"
    )
}

@Test
func helperLocatorIgnoresStandaloneHelperBundleWithoutContainingApp() throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let applicationsDirectoryURL = temporaryRoot.appendingPathComponent("Applications", isDirectory: true)
    let standaloneHelperBundleURL = applicationsDirectoryURL.appendingPathComponent("Ursus Helper.app", isDirectory: true)
    let userHomeURL = temporaryRoot.appendingPathComponent("home", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    try fileManager.createDirectory(at: standaloneHelperBundleURL, withIntermediateDirectories: true)

    let locatedURL = BearSelectedNoteHelperLocator.installedAppBundleURL(
        fileManager: fileManager,
        preferredAppBundleURL: applicationsDirectoryURL.appendingPathComponent("Ursus.app", isDirectory: true),
        userSpecificAppBundleURL: userHomeURL.appendingPathComponent("Applications/Ursus.app", isDirectory: true)
    )

    #expect(locatedURL == nil)
}

@Test
func helperLocatorFallsBackToUserInstallWhenPreferredAppLacksEmbeddedHelper() throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let applicationsDirectoryURL = temporaryRoot.appendingPathComponent("Applications", isDirectory: true)
    let userHomeURL = temporaryRoot.appendingPathComponent("home", isDirectory: true)
    let preferredAppBundleURL = applicationsDirectoryURL.appendingPathComponent("Ursus.app", isDirectory: true)
    let userAppBundleURL = userHomeURL.appendingPathComponent("Applications/Ursus.app", isDirectory: true)
    let embeddedHelperBundleURL = userAppBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Helpers", isDirectory: true)
        .appendingPathComponent("Ursus Helper.app", isDirectory: true)

    defer {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    try fileManager.createDirectory(at: preferredAppBundleURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: embeddedHelperBundleURL, withIntermediateDirectories: true)

    let locatedURL = BearSelectedNoteHelperLocator.installedAppBundleURL(
        fileManager: fileManager,
        preferredAppBundleURL: preferredAppBundleURL,
        userSpecificAppBundleURL: userAppBundleURL
    )

    #expect(locatedURL?.standardizedFileURL == embeddedHelperBundleURL.standardizedFileURL)
}
