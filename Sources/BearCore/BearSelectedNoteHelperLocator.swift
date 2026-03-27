import Foundation

public enum BearSelectedNoteHelperLocator {
    public static func executableURL(
        forConfiguredPath configuredPath: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let configuredURL = URL(fileURLWithPath: NSString(string: configuredPath).expandingTildeInPath, isDirectory: false)

        if configuredURL.pathExtension.lowercased() == "app" {
            return try bundleExecutableURL(bundleURL: configuredURL, fileManager: fileManager)
        }

        guard fileManager.fileExists(atPath: configuredURL.path) else {
            throw BearError.configuration("Selected-note helper was not found at `\(configuredURL.path)`.")
        }

        guard fileManager.isExecutableFile(atPath: configuredURL.path) else {
            throw BearError.configuration("Selected-note helper at `\(configuredURL.path)` is not executable.")
        }

        return configuredURL
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
}
