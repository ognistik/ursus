import Foundation

public enum BearPaths {
    public static let configurationDirectoryName = "bear-mcp"

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

    public static var debugLogURL: URL {
        configDirectoryURL.appendingPathComponent("debug.log", isDirectory: false)
    }

    public static var processLockURL: URL {
        configDirectoryURL.appendingPathComponent("server.lock", isDirectory: false)
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
}
