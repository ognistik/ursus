import Foundation

public enum BearPaths {
    public static let configurationDirectoryName = "bear-mcp"
    public static let applicationSupportDirectoryName = "Bear MCP"
    public static let legacyApplicationSupportDirectoryName = "bear-mcp"
    public static let logsDirectoryName = "Logs"
    public static let legacyLogsDirectoryName = "bear-mcp"
    public static let fallbackRuntimeDirectoryName = "bear-mcp"

    public static var configDirectoryURL: URL {
        homeDirectoryURL
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent(configurationDirectoryName, isDirectory: true)
    }

    public static var configFileURL: URL {
        configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    }

    public static var noteTemplateURL: URL {
        configDirectoryURL.appendingPathComponent("template.md", isDirectory: false)
    }

    public static var logsDirectoryURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent(logsDirectoryName, isDirectory: true)
    }

    public static var debugLogURL: URL {
        logsDirectoryURL.appendingPathComponent("debug.log", isDirectory: false)
    }

    public static var legacyLogsDirectoryURL: URL {
        libraryDirectoryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(legacyLogsDirectoryName, isDirectory: true)
    }

    public static var legacyDebugLogURL: URL {
        legacyLogsDirectoryURL.appendingPathComponent("debug.log", isDirectory: false)
    }

    public static var applicationSupportDirectoryURL: URL {
        libraryDirectoryURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
    }

    public static var legacyApplicationSupportDirectoryURL: URL {
        libraryDirectoryURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(legacyApplicationSupportDirectoryName, isDirectory: true)
    }

    public static var backupsDirectoryURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent("Backups", isDirectory: true)
    }

    public static var backupsIndexURL: URL {
        backupsDirectoryURL.appendingPathComponent("index.json", isDirectory: false)
    }

    public static var publicCLIDirectoryURL: URL {
        homeDirectoryURL
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    public static var publicCLIExecutableURL: URL {
        publicCLIDirectoryURL.appendingPathComponent("bear-mcp", isDirectory: false)
    }

    public static var runtimeLockDirectoryURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent("Runtime", isDirectory: true)
    }

    public static var processLockURL: URL {
        runtimeLockDirectoryURL.appendingPathComponent(".server.lock", isDirectory: false)
    }

    public static var fallbackRuntimeLockDirectoryURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(fallbackRuntimeDirectoryName, isDirectory: true)
            .appendingPathComponent("Runtime", isDirectory: true)
    }

    public static var fallbackProcessLockURL: URL {
        fallbackRuntimeLockDirectoryURL.appendingPathComponent(".server.lock", isDirectory: false)
    }

    public static func processSpecificFallbackLockURL(processID: Int32) -> URL {
        fallbackRuntimeLockDirectoryURL
            .appendingPathComponent("locks", isDirectory: true)
            .appendingPathComponent("\(processID).server.lock", isDirectory: false)
    }

    public static var processLockCandidateURLs: [URL] {
        [processLockURL, fallbackProcessLockURL]
    }

    public static var defaultBearDatabaseURL: URL {
        homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent("9K33E3U3T4.net.shinyfrog.bear", isDirectory: true)
            .appendingPathComponent("Application Data", isDirectory: true)
            .appendingPathComponent("database.sqlite", isDirectory: false)
    }

    private static var homeDirectoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static var libraryDirectoryURL: URL {
        homeDirectoryURL.appendingPathComponent("Library", isDirectory: true)
    }
}
