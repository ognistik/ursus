import Foundation

public enum BearMCPAppLocator {
    public static let appName = "Bear MCP.app"
    public static let preferredInstallDirectoryPath = "/Applications"

    public static func installedAppBundleURL(fileManager: FileManager = .default) -> URL? {
        standardAppBundleURLs.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    public static var preferredAppBundleURL: URL {
        appBundleURL(inApplicationsDirectoryAtPath: preferredInstallDirectoryPath)
    }

    public static var userSpecificAppBundleURL: URL {
        appBundleURL(inApplicationsDirectoryAtPath: userApplicationsDirectoryPath)
    }

    public static var installGuidance: String {
        "install `\(appName)` in `\(preferredAppBundleURL.path)` (preferred). `\(userSpecificAppBundleURL.path)` is also fully supported for user-specific installs."
    }

    public static func installationLocationDescription(forAppBundleURL bundleURL: URL) -> String {
        let standardizedPath = bundleURL.standardizedFileURL.path

        if standardizedPath == preferredAppBundleURL.standardizedFileURL.path {
            return "preferred install location"
        }

        if standardizedPath == userSpecificAppBundleURL.standardizedFileURL.path {
            return "supported user-specific install location"
        }

        return "detected install location"
    }

    public static func executableURL(
        forAppBundleURL bundleURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try bundleExecutableURL(bundleURL: bundleURL, fileManager: fileManager)
    }

    private static func bundleExecutableURL(
        bundleURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        guard fileManager.fileExists(atPath: bundleURL.path) else {
            throw BearError.configuration("Bear MCP app was not found at `\(bundleURL.path)`.")
        }

        guard let bundle = Bundle(url: bundleURL) else {
            throw BearError.configuration("Bear MCP app path `\(bundleURL.path)` is not a valid app bundle.")
        }

        guard let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
              !executableName.isEmpty
        else {
            throw BearError.configuration("Bear MCP app at `\(bundleURL.path)` is missing `CFBundleExecutable`.")
        }

        let executableURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName, isDirectory: false)

        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw BearError.configuration("Bear MCP executable was not found inside `\(bundleURL.path)`.")
        }

        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw BearError.configuration("Bear MCP executable inside `\(bundleURL.path)` is not executable.")
        }

        return executableURL
    }

    private static var standardAppBundleURLs: [URL] {
        [preferredAppBundleURL, userSpecificAppBundleURL]
    }

    private static var userApplicationsDirectoryPath: String {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
            .path
    }

    private static func appBundleURL(inApplicationsDirectoryAtPath applicationsDirectoryPath: String) -> URL {
        URL(fileURLWithPath: applicationsDirectoryPath, isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }
}
