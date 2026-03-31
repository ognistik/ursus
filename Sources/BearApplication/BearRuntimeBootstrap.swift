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
            "config.loaded path=\(configFileURL.path) inboxTags=\(configuration.inboxTags) createAddsInboxTagsByDefault=\(configuration.createAddsInboxTagsByDefault) tagsMergeMode=\(configuration.tagsMergeMode.rawValue) createOpensNoteByDefault=\(configuration.createOpensNoteByDefault) openUsesNewWindowByDefault=\(configuration.openUsesNewWindowByDefault) openNoteInEditModeByDefault=\(configuration.openNoteInEditModeByDefault) defaultDiscoveryLimit=\(configuration.defaultDiscoveryLimit) maxDiscoveryLimit=\(configuration.maxDiscoveryLimit) defaultSnippetLength=\(configuration.defaultSnippetLength) maxSnippetLength=\(configuration.maxSnippetLength) backupRetentionDays=\(configuration.backupRetentionDays) disabledTools=\(configuration.disabledTools.map(\.rawValue)) tokenConfigured=\(BearSelectedNoteTokenResolver.configured(configuration: configuration)) bridgeEnabled=\(configuration.bridge.enabled) bridgeHost=\(configuration.bridge.host) bridgePort=\(configuration.bridge.port)"
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
        try writeConfiguration(configuration, to: configFileURL)
        BearDebugLog.append("config.saved path=\(configFileURL.path) tokenConfigured=\(configuration.token != nil)")
        return configuration
    }

    public static func doctorReport(logger: Logger) -> String {
        let snapshot = BearAppSupport.loadDashboardSnapshot()
        let lines = snapshot.diagnostics.map(\.renderedLine)

        logger.info("Generated bear-mcp doctor report.")
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
