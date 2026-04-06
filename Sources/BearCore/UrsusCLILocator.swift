import Darwin
import Foundation

public struct BearPublicCLILauncherInstallReceipt: Codable, Hashable, Sendable {
    public let sourcePath: String
    public let destinationPath: String

    public init(sourcePath: String, destinationPath: String) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
    }
}

public enum UrsusCLILocator {
    public static let executableName = "ursus"
    public static let bundledExecutableName = "Ursus"
    public static let bundledRelativePath = "Contents/MacOS/\(bundledExecutableName)"

    public static var publicLauncherURL: URL {
        BearPaths.publicCLIExecutableURL
    }

    public static var publicLauncherGuidance: String {
        "Use `\(UrsusAppLocator.appName)` to install or repair the public launcher at `\(publicLauncherURL.path)`. Local MCP hosts and Terminal should use that same path."
    }

    public static var bundledExecutableGuidance: String {
        "Build or reinstall `\(UrsusAppLocator.appName)` so it contains `\(bundledRelativePath)`."
    }

    public static func bridgeImplementationMarker(
        forAppBundleURL bundleURL: URL,
        fileManager: FileManager = .default
    ) throws -> String {
        let executableURL = try bundledExecutableURL(forAppBundleURL: bundleURL, fileManager: fileManager)
        return try bridgeImplementationMarker(
            executableURL: executableURL,
            bundle: Bundle(url: bundleURL),
            fileManager: fileManager
        )
    }

    public static func currentBridgeImplementationMarker(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        processArguments: [String] = CommandLine.arguments
    ) -> String? {
        if bundle.bundleURL.pathExtension == "app",
           fileManager.fileExists(atPath: bundle.bundleURL.path)
        {
            return try? bridgeImplementationMarker(
                forAppBundleURL: bundle.bundleURL,
                fileManager: fileManager
            )
        }

        if let executableURL = bundle.executableURL,
           fileManager.fileExists(atPath: executableURL.path)
        {
            return try? bridgeImplementationMarker(
                executableURL: executableURL,
                bundle: bundle,
                fileManager: fileManager
            )
        }

        guard let executablePath = processArguments.first,
              !executablePath.isEmpty
        else {
            return nil
        }

        return try? bridgeImplementationMarker(
            executableURL: URL(fileURLWithPath: executablePath, isDirectory: false),
            bundle: nil,
            fileManager: fileManager
        )
    }

    public static func bundledExecutableURL(
        forAppBundleURL bundleURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard fileManager.fileExists(atPath: bundleURL.path) else {
            throw BearError.configuration("Ursus app was not found at `\(bundleURL.path)`.")
        }

        let executableURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(bundledExecutableName, isDirectory: false)

        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw BearError.configuration("Bundled CLI executable was not found inside `\(bundleURL.path)`.")
        }

        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw BearError.configuration("Bundled CLI executable inside `\(bundleURL.path)` is not executable.")
        }

        return executableURL
    }

    public static func installedLauncherURL(
        fileManager: FileManager = .default,
        destinationURL: URL = publicLauncherURL
    ) throws -> URL {
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw BearError.configuration("Public launcher was not found at `\(destinationURL.path)`. \(publicLauncherGuidance)")
        }

        guard fileManager.isExecutableFile(atPath: destinationURL.path) else {
            throw BearError.configuration("Public launcher at `\(destinationURL.path)` is not executable.")
        }

        return destinationURL
    }

    public static func launcherScript(
        forAppBundleURL bundleURL: URL,
        fileManager: FileManager = .default
    ) throws -> String {
        let bundledCLIURL = try bundledExecutableURL(forAppBundleURL: bundleURL, fileManager: fileManager)
        let candidatePaths = launcherCandidatePaths(
            primaryAppBundleURL: bundleURL,
            primaryBundledCLIURL: bundledCLIURL
        )

        let loopEntries = candidatePaths
            .map { "  \($0)" }
            .joined(separator: " \\\n")
        let installGuidance = "Open Ursus.app once from its current location to repair the launcher, or reinstall the app in /Applications/Ursus.app or ~/Applications/Ursus.app."

        return """
        #!/bin/sh
        set -eu

        for cli_path in \\
        \(loopEntries)
        do
          if [ -x "$cli_path" ]; then
            exec "$cli_path" --ursus-cli "$@"
          fi
        done

        printf '%s\\n' 'Ursus launcher could not find the bundled CLI. \(installGuidance)' >&2
        exit 1
        """
    }

    @discardableResult
    public static func installPublicLauncher(
        fromAppBundleURL bundleURL: URL,
        fileManager: FileManager = .default,
        destinationURL: URL = publicLauncherURL
    ) throws -> BearPublicCLILauncherInstallReceipt {
        let bundledCLIURL = try bundledExecutableURL(forAppBundleURL: bundleURL, fileManager: fileManager)
        let launcherScript = try launcherScript(forAppBundleURL: bundleURL, fileManager: fileManager)

        try installLauncherScript(
            launcherScript,
            fileManager: fileManager,
            destinationURL: destinationURL
        )

        return BearPublicCLILauncherInstallReceipt(
            sourcePath: bundledCLIURL.path,
            destinationPath: destinationURL.path
        )
    }

    public static func launcherMatches(
        expectedScript: String,
        destinationURL: URL
    ) throws -> Bool {
        let destinationData = try Data(contentsOf: destinationURL)
        return destinationData == Data(expectedScript.utf8)
    }

    public static func hasIndirectFilesystemEntry(at url: URL) -> Bool {
        var status = stat()
        guard lstat(url.path, &status) == 0 else {
            return false
        }

        return (status.st_mode & S_IFMT) == S_IFLNK
    }

    @discardableResult
    private static func installLauncherScript(
        _ launcherScript: String,
        fileManager: FileManager,
        destinationURL: URL
    ) throws -> URL {
        let destinationDirectoryURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)

        let stagingURL = destinationDirectoryURL
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString)", isDirectory: false)

        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }

        try Data(launcherScript.utf8).write(to: stagingURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagingURL.path)

        if fileManager.fileExists(atPath: destinationURL.path) || hasIndirectFilesystemEntry(at: destinationURL) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        return destinationURL
    }

    private static func launcherCandidatePaths(
        primaryAppBundleURL: URL,
        primaryBundledCLIURL: URL
    ) -> [String] {
        var paths = [shellSingleQuoted(primaryBundledCLIURL.path)]
        let fallbackBundleURLs = UrsusAppLocator.installedAppBundleCandidates()

        for bundleURL in fallbackBundleURLs where bundleURL.standardizedFileURL.path != primaryAppBundleURL.standardizedFileURL.path {
            let bundledCLIPath = bundleURL
                .appendingPathComponent(bundledRelativePath, isDirectory: false)
                .path
            paths.append(shellSingleQuoted(bundledCLIPath))
        }

        let homeRelativePath = "Applications/\(UrsusAppLocator.appName)/\(bundledRelativePath)"
        let homeCandidate = "\"$HOME/\(homeRelativePath)\""
        if !paths.contains(homeCandidate) {
            paths.append(homeCandidate)
        }

        return paths
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func bridgeImplementationMarker(
        executableURL: URL,
        bundle: Bundle?,
        fileManager: FileManager
    ) throws -> String {
        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw BearError.configuration("Bridge implementation marker could not be computed because `\(executableURL.path)` does not exist.")
        }

        let attributes = try fileManager.attributesOfItem(atPath: executableURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let bundleVersion = bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let shortVersion = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

        return [
            "size=\(fileSize)",
            "modified=\(modifiedAt)",
            "bundleVersion=\(bundleVersion)",
            "shortVersion=\(shortVersion)",
        ].joined(separator: "|")
    }
}
