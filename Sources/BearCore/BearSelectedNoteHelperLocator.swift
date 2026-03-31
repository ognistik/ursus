import Foundation

public enum BearSelectedNoteHelperLocator {
    public static let appName = "Ursus Helper.app"
    public static let embeddedRelativePath = "Contents/Library/Helpers/\(appName)"

    public static func installedAppBundleURL(fileManager: FileManager = .default) -> URL? {
        installedAppBundleURL(
            fileManager: fileManager,
            preferredAppBundleURL: BearMCPAppLocator.preferredAppBundleURL,
            userSpecificAppBundleURL: BearMCPAppLocator.userSpecificAppBundleURL
        )
    }

    public static func installedAppBundleURL(
        fileManager: FileManager = .default,
        preferredAppBundleURL: URL,
        userSpecificAppBundleURL: URL
    ) -> URL? {
        let candidateMainAppBundleURLs = [preferredAppBundleURL, userSpecificAppBundleURL]

        guard let mainAppBundleURL = candidateMainAppBundleURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return nil
        }

        return embeddedAppBundleURL(
            inAppBundleURL: mainAppBundleURL,
            fileManager: fileManager
        )
    }

    public static var installGuidance: String {
        "install or reinstall `\(BearMCPAppLocator.appName)` so it contains the embedded selected-note helper. `\(BearMCPAppLocator.preferredAppBundleURL.path)` is preferred, and `\(BearMCPAppLocator.userSpecificAppBundleURL.path)` is also fully supported for user-specific installs."
    }

    public static func installationLocationDescription(forAppBundleURL bundleURL: URL) -> String {
        if let embeddedContainerURL = containingAppBundleURL(
            forEmbeddedHelperBundleURL: bundleURL,
            fileManager: .default
        ) {
            return "embedded in \(embeddedContainerURL.path)"
        }

        return "detected install location"
    }

    public static func installedExecutableURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let bundleURL = installedAppBundleURL(fileManager: fileManager) else {
            throw BearError.configuration(
                "Selected-note targeting requires the embedded selected-note helper inside `\(BearMCPAppLocator.appName)`. \(installGuidance)"
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

    public static func embeddedAppBundleURL(
        inAppBundleURL appBundleURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let helperBundleURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)

        guard fileManager.fileExists(atPath: helperBundleURL.path) else {
            return nil
        }

        return helperBundleURL
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

    private static func containingAppBundleURL(
        forEmbeddedHelperBundleURL helperBundleURL: URL,
        fileManager: FileManager
    ) -> URL? {
        let pathComponents = helperBundleURL.standardizedFileURL.pathComponents
        guard let contentsIndex = pathComponents.lastIndex(of: "Contents"), contentsIndex >= 1 else {
            return nil
        }

        let candidatePath = NSString.path(withComponents: Array(pathComponents.prefix(contentsIndex - 1 + 1)))
        let candidateURL = URL(fileURLWithPath: candidatePath, isDirectory: true)
        guard fileManager.fileExists(atPath: candidateURL.path) else {
            return nil
        }

        guard embeddedAppBundleURL(inAppBundleURL: candidateURL, fileManager: fileManager)?.standardizedFileURL == helperBundleURL.standardizedFileURL else {
            return nil
        }

        return candidateURL
    }
}
