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
            "config.loaded path=\(configFileURL.path) runtimeGeneration=\(configuration.runtimeConfigurationGeneration) inboxTags=\(configuration.inboxTags) createAddsInboxTagsByDefault=\(configuration.createAddsInboxTagsByDefault) tagsMergeMode=\(configuration.tagsMergeMode.rawValue) createOpensNoteByDefault=\(configuration.createOpensNoteByDefault) openUsesNewWindowByDefault=\(configuration.openUsesNewWindowByDefault) defaultDiscoveryLimit=\(configuration.defaultDiscoveryLimit) defaultSnippetLength=\(configuration.defaultSnippetLength) backupRetentionDays=\(configuration.backupRetentionDays) disabledTools=\(configuration.disabledTools.map(\.rawValue)) bridgeEnabled=\(configuration.bridge.enabled) bridgeHost=\(configuration.bridge.host) bridgePort=\(configuration.bridge.port)"
        )
        return configuration
    }

    @discardableResult
    public static func saveConfiguration(
        _ configuration: BearConfiguration,
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
        let existingConfiguration = try? BearConfiguration.load(from: configFileURL)
        let nextGeneration: Int

        if let existingConfiguration {
            nextGeneration = existingConfiguration.runtimeConfigurationMatches(configuration)
                ? existingConfiguration.runtimeConfigurationGeneration
                : existingConfiguration.runtimeConfigurationGeneration + 1
        } else {
            nextGeneration = configuration.runtimeConfigurationGeneration
        }

        let persistedConfiguration = configuration.updatingRuntimeConfigurationGeneration(nextGeneration)
        try writeConfiguration(persistedConfiguration, to: configFileURL)
        BearDebugLog.append(
            "config.saved path=\(configFileURL.path) runtimeGeneration=\(persistedConfiguration.runtimeConfigurationGeneration)"
        )
        return persistedConfiguration
    }

    public static func doctorReport(logger: Logger) -> String {
        let snapshot = BearAppSupport.loadDashboardSnapshot()
        let lines = snapshot.diagnostics.map(\.renderedLine)

        logger.info("Generated ursus doctor report.")
        return lines.joined(separator: "\n")
    }

    private static func writeConfiguration(_ configuration: BearConfiguration, to url: URL) throws {
        let encoder = BearJSON.makeEncoder()
        let data = try encoder.encode(configuration)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static let defaultNoteTemplate = """
    {{content}}

    {{tags}}
    """
}
