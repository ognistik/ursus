import BearCore
import Foundation
import Logging

public enum BearRuntimeBootstrap {
    public static func prepareSupportFiles(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL
    ) throws {
        try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: configFileURL.path) {
            try writeConfiguration(BearConfiguration.default, to: configFileURL)
        }

        if !fileManager.fileExists(atPath: templateURL.path) {
            guard let data = defaultNoteTemplate.data(using: .utf8) else {
                throw BearError.configuration("Failed to encode the default Bear note template.")
            }
            try data.write(to: templateURL, options: .atomic)
        }
    }

    public static func loadConfiguration(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL
    ) throws -> BearConfiguration {
        try prepareSupportFiles(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
        let configuration = try BearConfiguration.load(from: configFileURL)
        BearDebugLog.append(
            "config.loaded path=\(configFileURL.path) activeTags=\(configuration.activeTags) createAddsActiveTagsByDefault=\(configuration.createAddsActiveTagsByDefault) tagsMergeMode=\(configuration.tagsMergeMode.rawValue) createOpensNoteByDefault=\(configuration.createOpensNoteByDefault) openUsesNewWindowByDefault=\(configuration.openUsesNewWindowByDefault) openNoteInEditModeByDefault=\(configuration.openNoteInEditModeByDefault) defaultDiscoveryLimit=\(configuration.defaultDiscoveryLimit) maxDiscoveryLimit=\(configuration.maxDiscoveryLimit) defaultSnippetLength=\(configuration.defaultSnippetLength) maxSnippetLength=\(configuration.maxSnippetLength) backupRetentionDays=\(configuration.backupRetentionDays) hasToken=\(configuration.token != nil) hasSelectedNoteHelper=\(configuration.selectedNoteHelperPath != nil) selectedNoteTargetingEnabled=\(configuration.selectedNoteTargetingEnabled)"
        )
        return configuration
    }

    @discardableResult
    public static func updateConfigurationFile(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL
    ) throws -> BearConfiguration {
        let configuration = try loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
        try writeConfiguration(configuration, to: configFileURL)
        BearDebugLog.append("config.updated path=\(configFileURL.path)")
        return configuration
    }

    public static func doctorReport(logger: Logger) -> String {
        let fileManager = FileManager.default

        var lines = [
            "config: \(BearPaths.configFileURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.configFileURL.path)))]",
            "note-template: \(BearPaths.noteTemplateURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.noteTemplateURL.path)))]",
            "backups-index: \(BearPaths.backupsIndexURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.backupsIndexURL.path)))]",
            "process-lock-primary: \(BearPaths.processLockURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.processLockURL.path)))]",
            "process-lock-fallback: \(BearPaths.fallbackProcessLockURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.fallbackProcessLockURL.path)))]",
            "debug-log: \(BearPaths.debugLogURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.debugLogURL.path)))]",
            "bear-db: \(BearPaths.defaultBearDatabaseURL.path) [\(status(fileManager.fileExists(atPath: BearPaths.defaultBearDatabaseURL.path)))]",
        ]

        do {
            let configuration = try loadConfiguration(fileManager: fileManager)
            lines.append("selected-note-token: \(configuration.token == nil ? "not configured" : "configured")")
            if let helperPath = configuration.selectedNoteHelperPath {
                do {
                    let executableURL = try BearSelectedNoteHelperLocator.executableURL(
                        forConfiguredPath: helperPath,
                        fileManager: fileManager
                    )
                    lines.append("selected-note-helper: \(helperPath) [ok -> \(executableURL.path)]")
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    lines.append("selected-note-helper: \(helperPath) [invalid: \(message)]")
                }
            } else {
                lines.append("selected-note-helper: not configured [optional]")
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            lines.append("config-load: failed [\(message)]")
        }

        logger.info("Generated bear-mcp doctor report.")
        return lines.joined(separator: "\n")
    }

    private static func status(_ exists: Bool) -> String {
        exists ? "ok" : "missing"
    }

    private static func writeConfiguration(_ configuration: BearConfiguration, to url: URL) throws {
        let encoder = BearJSON.makeEncoder()
        let data = try encoder.encode(configuration)
        try data.write(to: url, options: .atomic)
    }

    private static let defaultNoteTemplate = """
    {{content}}

    {{tags}}
    """
}
