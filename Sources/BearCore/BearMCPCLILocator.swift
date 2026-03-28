import Foundation

public struct BearBundledCLIInstallReceipt: Codable, Hashable, Sendable {
    public let sourcePath: String
    public let destinationPath: String

    public init(sourcePath: String, destinationPath: String) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
    }
}

public struct BearCLICommandLinkReceipt: Codable, Hashable, Sendable {
    public let sourcePath: String
    public let destinationPath: String

    public init(sourcePath: String, destinationPath: String) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
    }
}

public enum BearMCPCLILocator {
    public static let executableName = "bear-mcp"
    public static let bundledRelativePath = "Contents/Resources/bin/\(executableName)"

    public static var appManagedInstallURL: URL {
        BearPaths.bundledCLIExecutableURL
    }

    public static var userCommandInstallURL: URL {
        BearPaths.userCLIExecutableURL
    }

    public static var appManagedInstallGuidance: String {
        "Use `\(BearMCPAppLocator.appName)` to install the bundled CLI to `\(appManagedInstallURL.path)`. MCP hosts should point to that stable path, not to transient SwiftPM build outputs."
    }

    public static var bundledExecutableGuidance: String {
        "Build or reinstall `\(BearMCPAppLocator.appName)` so it contains `\(bundledRelativePath)`."
    }

    public static var userCommandInstallGuidance: String {
        "Install the app-managed CLI first, then create a shell command link at `\(userCommandInstallURL.path)` so `bear-mcp` is easy to run from Terminal."
    }

    public static func bundledExecutableURL(
        forAppBundleURL bundleURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard fileManager.fileExists(atPath: bundleURL.path) else {
            throw BearError.configuration("Bear MCP app was not found at `\(bundleURL.path)`.")
        }

        let executableURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(executableName, isDirectory: false)

        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw BearError.configuration("Bundled CLI executable was not found inside `\(bundleURL.path)`.")
        }

        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw BearError.configuration("Bundled CLI executable inside `\(bundleURL.path)` is not executable.")
        }

        return executableURL
    }

    public static func installedExecutableURL(
        fileManager: FileManager = .default,
        destinationURL: URL = appManagedInstallURL
    ) throws -> URL {
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw BearError.configuration("App-managed CLI was not found at `\(destinationURL.path)`. \(appManagedInstallGuidance)")
        }

        guard fileManager.isExecutableFile(atPath: destinationURL.path) else {
            throw BearError.configuration("App-managed CLI at `\(destinationURL.path)` is not executable.")
        }

        return destinationURL
    }

    @discardableResult
    public static func installUserCommandLink(
        fileManager: FileManager = .default,
        sourceURL: URL = appManagedInstallURL,
        destinationURL: URL = userCommandInstallURL
    ) throws -> BearCLICommandLinkReceipt {
        let sourceExecutableURL = try installedExecutableURL(
            fileManager: fileManager,
            destinationURL: sourceURL
        )
        let destinationDirectoryURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destinationURL.path)
            || (try? fileManager.destinationOfSymbolicLink(atPath: destinationURL.path)) != nil {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.createSymbolicLink(
            at: destinationURL,
            withDestinationURL: sourceExecutableURL
        )

        return BearCLICommandLinkReceipt(
            sourcePath: sourceExecutableURL.path,
            destinationPath: destinationURL.path
        )
    }

    @discardableResult
    public static func installBundledExecutable(
        fromAppBundleURL bundleURL: URL,
        fileManager: FileManager = .default,
        destinationURL: URL = appManagedInstallURL
    ) throws -> BearBundledCLIInstallReceipt {
        let sourceURL = try bundledExecutableURL(forAppBundleURL: bundleURL, fileManager: fileManager)
        let destinationDirectoryURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)

        let stagingURL = destinationDirectoryURL
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString)", isDirectory: false)

        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }

        try fileManager.copyItem(at: sourceURL, to: stagingURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagingURL.path)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: stagingURL, to: destinationURL)

        return BearBundledCLIInstallReceipt(
            sourcePath: sourceURL.path,
            destinationPath: destinationURL.path
        )
    }
}
