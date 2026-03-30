import BearCore
import Foundation
import Logging

public enum BearRuntimeBootstrap {
    public static func prepareSupportFiles(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL,
        applicationSupportDirectoryURL: URL = BearPaths.applicationSupportDirectoryURL,
        legacyApplicationSupportDirectoryURL: URL = BearPaths.legacyApplicationSupportDirectoryURL
    ) throws {
        try migrateLegacyRuntimeSupportIfNeeded(
            fileManager: fileManager,
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            legacyApplicationSupportDirectoryURL: legacyApplicationSupportDirectoryURL
        )
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
            "config.loaded path=\(configFileURL.path) inboxTags=\(configuration.inboxTags) createAddsInboxTagsByDefault=\(configuration.createAddsInboxTagsByDefault) tagsMergeMode=\(configuration.tagsMergeMode.rawValue) createOpensNoteByDefault=\(configuration.createOpensNoteByDefault) openUsesNewWindowByDefault=\(configuration.openUsesNewWindowByDefault) openNoteInEditModeByDefault=\(configuration.openNoteInEditModeByDefault) defaultDiscoveryLimit=\(configuration.defaultDiscoveryLimit) maxDiscoveryLimit=\(configuration.maxDiscoveryLimit) defaultSnippetLength=\(configuration.defaultSnippetLength) maxSnippetLength=\(configuration.maxSnippetLength) backupRetentionDays=\(configuration.backupRetentionDays) disabledTools=\(configuration.disabledTools.map(\.rawValue)) tokenConfigured=\(BearSelectedNoteTokenResolver.configured(configuration: configuration))"
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

    private static func migrateLegacyRuntimeSupportIfNeeded(
        fileManager: FileManager,
        applicationSupportDirectoryURL: URL,
        legacyApplicationSupportDirectoryURL: URL
    ) throws {
        guard applicationSupportDirectoryURL.standardizedFileURL != legacyApplicationSupportDirectoryURL.standardizedFileURL else {
            return
        }

        guard fileManager.fileExists(atPath: legacyApplicationSupportDirectoryURL.path) else {
            return
        }

        try fileManager.createDirectory(
            at: applicationSupportDirectoryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard fileManager.fileExists(atPath: applicationSupportDirectoryURL.path) else {
            try fileManager.moveItem(at: legacyApplicationSupportDirectoryURL, to: applicationSupportDirectoryURL)
            return
        }

        let legacyEntries = try fileManager.contentsOfDirectory(
            at: legacyApplicationSupportDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for legacyEntry in legacyEntries {
            let resourceValues = try legacyEntry.resourceValues(forKeys: [.isDirectoryKey])
            let destinationURL = applicationSupportDirectoryURL
                .appendingPathComponent(legacyEntry.lastPathComponent, isDirectory: resourceValues.isDirectory == true)

            if !fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.moveItem(at: legacyEntry, to: destinationURL)
                continue
            }

            if legacyEntry.lastPathComponent == "Backups", resourceValues.isDirectory == true {
                try mergeBackups(
                    fileManager: fileManager,
                    legacyBackupsDirectoryURL: legacyEntry,
                    backupsDirectoryURL: destinationURL
                )
            }
        }

        try removeDirectoryIfEmpty(legacyApplicationSupportDirectoryURL, fileManager: fileManager)
    }

    private static func mergeBackups(
        fileManager: FileManager,
        legacyBackupsDirectoryURL: URL,
        backupsDirectoryURL: URL
    ) throws {
        try fileManager.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true)

        let legacyIndexURL = legacyBackupsDirectoryURL.appendingPathComponent("index.json", isDirectory: false)
        let backupsIndexURL = backupsDirectoryURL.appendingPathComponent("index.json", isDirectory: false)

        var backupsIndex = try loadBackupIndex(fileManager: fileManager, indexURL: backupsIndexURL)
        let legacyIndex = try loadBackupIndex(fileManager: fileManager, indexURL: legacyIndexURL)
        var knownSnapshotIDs = Set(backupsIndex.entries.map(\.snapshotID))

        for item in try fileManager.contentsOfDirectory(at: legacyBackupsDirectoryURL, includingPropertiesForKeys: nil) {
            guard item.lastPathComponent != "index.json" else {
                continue
            }

            let destinationURL = try moveFilePreservingData(
                from: item,
                into: backupsDirectoryURL,
                fileManager: fileManager
            )

            if let legacyEntry = legacyIndex.entries.first(where: { $0.fileName == item.lastPathComponent }),
               !knownSnapshotIDs.contains(legacyEntry.snapshotID)
            {
                var migratedEntry = legacyEntry
                migratedEntry.fileName = destinationURL.lastPathComponent
                backupsIndex.entries.append(migratedEntry)
                knownSnapshotIDs.insert(migratedEntry.snapshotID)
            }
        }

        if !backupsIndex.entries.isEmpty {
            let data = try BearJSON.makeEncoder().encode(backupsIndex)
            try data.write(to: backupsIndexURL, options: .atomic)
        }

        if fileManager.fileExists(atPath: legacyIndexURL.path) {
            try fileManager.removeItem(at: legacyIndexURL)
        }

        try removeDirectoryIfEmpty(legacyBackupsDirectoryURL, fileManager: fileManager)
    }

    private static func moveFilePreservingData(
        from sourceURL: URL,
        into destinationDirectoryURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        let preferredDestinationURL = destinationDirectoryURL
            .appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)

        if !fileManager.fileExists(atPath: preferredDestinationURL.path) {
            try fileManager.moveItem(at: sourceURL, to: preferredDestinationURL)
            return preferredDestinationURL
        }

        if fileManager.contentsEqual(atPath: sourceURL.path, andPath: preferredDestinationURL.path) {
            try fileManager.removeItem(at: sourceURL)
            return preferredDestinationURL
        }

        var attempt = 1
        let fileExtension = sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent

        while true {
            let candidateName: String
            if fileExtension.isEmpty {
                candidateName = "\(baseName)-migrated-\(attempt)"
            } else {
                candidateName = "\(baseName)-migrated-\(attempt).\(fileExtension)"
            }
            let candidateURL = destinationDirectoryURL.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                try fileManager.moveItem(at: sourceURL, to: candidateURL)
                return candidateURL
            }
            attempt += 1
        }
    }

    private static func loadBackupIndex(
        fileManager: FileManager,
        indexURL: URL
    ) throws -> MigratableBackupIndex {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return MigratableBackupIndex(entries: [])
        }

        let data = try Data(contentsOf: indexURL)
        return try BearJSON.makeDecoder().decode(MigratableBackupIndex.self, from: data)
    }

    private static func removeDirectoryIfEmpty(_ directoryURL: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        let contents = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
        guard contents.isEmpty else {
            return
        }

        try fileManager.removeItem(at: directoryURL)
    }

    private static let defaultNoteTemplate = """
    {{content}}

    {{tags}}
    """
}

private struct MigratableBackupIndex: Codable {
    var entries: [MigratableBackupIndexEntry]
}

private struct MigratableBackupIndexEntry: Codable {
    let snapshotID: String
    let noteID: String
    let title: String
    let version: Int
    let modifiedAt: Date
    let capturedAt: Date
    let reason: BackupReason
    let operationGroupID: String?
    let snippet: String?
    var fileName: String
}
