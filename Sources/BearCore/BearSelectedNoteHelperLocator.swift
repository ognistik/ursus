import Foundation

public enum BearSelectedNoteHelperLocator {
    public static let appName = "Bear MCP Helper.app"

    public static func installedAppBundleURL(fileManager: FileManager = .default) -> URL? {
        standardAppBundleURLs.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    public static func installedExecutableURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let bundleURL = installedAppBundleURL(fileManager: fileManager) else {
            throw BearError.configuration(
                "Selected-note targeting requires `\(appName)` to be installed in `/Applications` or `~/Applications`."
            )
        }

        return try executableURL(forAppBundleURL: bundleURL, fileManager: fileManager)
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
            throw BearError.configuration("Selected-note helper app was not found at `\(bundleURL.path)`.")
        }

        guard let bundle = Bundle(url: bundleURL) else {
            throw BearError.configuration("Selected-note helper path `\(bundleURL.path)` is not a valid app bundle.")
        }

        guard let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
              !executableName.isEmpty
        else {
            throw BearError.configuration("Selected-note helper app at `\(bundleURL.path)` is missing `CFBundleExecutable`.")
        }

        let executableURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName, isDirectory: false)

        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw BearError.configuration("Selected-note helper executable was not found inside `\(bundleURL.path)`.")
        }

        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw BearError.configuration("Selected-note helper executable inside `\(bundleURL.path)` is not executable.")
        }

        return executableURL
    }

    private static var standardAppBundleURLs: [URL] {
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
        let userApplications = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)

        return [systemApplications, userApplications]
    }
}
