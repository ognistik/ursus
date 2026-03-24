import BearCore
import Foundation
import Logging

public enum BearRuntimeBootstrap {
    public static func prepareSupportFiles(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: BearPaths.configDirectoryURL, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: BearPaths.configFileURL.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(BearConfiguration.default)
            try data.write(to: BearPaths.configFileURL, options: .atomic)
        }

        if !fileManager.fileExists(atPath: BearPaths.noteTemplateURL.path) {
            guard let data = defaultNoteTemplate.data(using: .utf8) else {
                throw BearError.configuration("Failed to encode the default Bear note template.")
            }
            try data.write(to: BearPaths.noteTemplateURL, options: .atomic)
        }
    }

    public static func loadConfiguration() throws -> BearConfiguration {
        try prepareSupportFiles()
        let configuration = try BearConfiguration.load()
        BearDebugLog.append(
            "config.loaded path=\(BearPaths.configFileURL.path) activeTags=\(configuration.activeTags) createAddsActiveTagsByDefault=\(configuration.createAddsActiveTagsByDefault) createRequestTagsMode=\(configuration.createRequestTagsMode.rawValue) createOpensNoteByDefault=\(configuration.createOpensNoteByDefault) openUsesNewWindowByDefault=\(configuration.openUsesNewWindowByDefault) openNoteInEditModeByDefault=\(configuration.openNoteInEditModeByDefault)"
        )
        return configuration
    }

    public static func doctorReport(logger: Logger) -> String {
        let fileManager = FileManager.default

        let lines = [
            "config: \(BearPaths.configFileURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.configFileURL.path)))]",
            "note-template: \(BearPaths.noteTemplateURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.noteTemplateURL.path)))]",
            "process-lock-primary: \(BearPaths.processLockURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.processLockURL.path)))]",
            "process-lock-fallback: \(BearPaths.fallbackProcessLockURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.fallbackProcessLockURL.path)))]",
            "debug-log: \(BearPaths.debugLogURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.debugLogURL.path)))]",
            "bear-db: \(BearPaths.defaultBearDatabaseURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.defaultBearDatabaseURL.path)))]",
        ]

        logger.info("Generated bear-mcp doctor report.")
        return lines.joined(separator: "\n")
    }

    private static func status(_ exists: Bool) -> String {
        exists ? "ok" : "missing"
    }

    private static let defaultNoteTemplate = """
    {{content}}

    {{tags}}
    """
}
