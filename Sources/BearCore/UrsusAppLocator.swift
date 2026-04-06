import Foundation

public enum UrsusAppLocator {
    private struct PersistedAppBundleState: Codable, Hashable, Sendable {
        let appBundlePath: String
        let recordedAt: Date
    }

    public static let appName = "Ursus.app"
    public static let preferredInstallDirectoryPath = "/Applications"

    public static func installedAppBundleURL(
        fileManager: FileManager = .default
    ) -> URL? {
        installedAppBundleURL(
            fileManager: fileManager,
            stateURL: BearPaths.currentAppBundleStateURL
        )
    }

    public static func installedAppBundleURL(
        fileManager: FileManager = .default,
        stateURL: URL = BearPaths.currentAppBundleStateURL
    ) -> URL? {
        installedAppBundleCandidates(fileManager: fileManager, stateURL: stateURL).first
    }

    public static func recordCurrentAppBundleURL(
        _ bundleURL: URL,
        fileManager: FileManager = .default,
        stateURL: URL = BearPaths.currentAppBundleStateURL
    ) throws {
        let standardizedURL = bundleURL.standardizedFileURL
        guard standardizedURL.lastPathComponent == appName else {
            throw BearError.configuration("Ursus app path `\(standardizedURL.path)` is not `\(appName)`.")
        }

        try fileManager.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let state = PersistedAppBundleState(
            appBundlePath: standardizedURL.path,
            recordedAt: Date()
        )
        let data = try BearJSON.makeEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    public static func recordedAppBundleURL(
        fileManager: FileManager = .default,
        stateURL: URL = BearPaths.currentAppBundleStateURL
    ) -> URL? {
        guard fileManager.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL),
              let state = try? BearJSON.makeDecoder().decode(PersistedAppBundleState.self, from: data)
        else {
            return nil
        }

        let bundleURL = URL(fileURLWithPath: state.appBundlePath, isDirectory: true).standardizedFileURL
        guard bundleURL.lastPathComponent == appName,
              fileManager.fileExists(atPath: bundleURL.path)
        else {
            return nil
        }

        return bundleURL
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
            throw BearError.configuration("Ursus app was not found at `\(bundleURL.path)`.")
        }

        guard let bundle = Bundle(url: bundleURL) else {
            throw BearError.configuration("Ursus app path `\(bundleURL.path)` is not a valid app bundle.")
        }

        guard let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
              !executableName.isEmpty
        else {
            throw BearError.configuration("Ursus app at `\(bundleURL.path)` is missing `CFBundleExecutable`.")
        }

        let executableURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName, isDirectory: false)

        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw BearError.configuration("Ursus executable was not found inside `\(bundleURL.path)`.")
        }

        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw BearError.configuration("Ursus executable inside `\(bundleURL.path)` is not executable.")
        }

        return executableURL
    }

    static func installedAppBundleCandidates(
        fileManager: FileManager = .default,
        stateURL: URL = BearPaths.currentAppBundleStateURL
    ) -> [URL] {
        var seen: Set<String> = []
        var candidates: [URL] = []

        for bundleURL in candidateAppBundleURLs(stateURL: stateURL) {
            let standardizedPath = bundleURL.standardizedFileURL.path
            guard seen.insert(standardizedPath).inserted else {
                continue
            }

            guard fileManager.fileExists(atPath: standardizedPath) else {
                continue
            }

            candidates.append(bundleURL.standardizedFileURL)
        }

        return candidates
    }

    private static var standardAppBundleURLs: [URL] {
        [preferredAppBundleURL, userSpecificAppBundleURL]
    }

    private static func candidateAppBundleURLs(stateURL: URL) -> [URL] {
        let recordedURL = recordedAppBundleURL(stateURL: stateURL)
        return [recordedURL, preferredAppBundleURL, userSpecificAppBundleURL].compactMap { $0 }
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
