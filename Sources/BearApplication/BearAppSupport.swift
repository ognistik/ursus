import BearCore
import Foundation

public enum BearDoctorCheckStatus: String, Codable, Hashable, Sendable {
    case ok
    case missing
    case invalid
    case configured
    case notConfigured
    case failed
}

public struct BearDoctorCheck: Codable, Hashable, Sendable, Identifiable {
    public let key: String
    public let value: String
    public let status: BearDoctorCheckStatus
    public let detail: String?

    public var id: String { key }

    public var renderedLine: String {
        guard let detail, !detail.isEmpty else {
            return "\(key): \(value)"
        }

        return "\(key): \(value) [\(detail)]"
    }

    public init(
        key: String,
        value: String,
        status: BearDoctorCheckStatus,
        detail: String? = nil
    ) {
        self.key = key
        self.value = value
        self.status = status
        self.detail = detail
    }
}

public struct BearAppSettingsSnapshot: Codable, Hashable, Sendable {
    public let configDirectoryPath: String
    public let configFilePath: String
    public let templatePath: String
    public let backupsDirectoryPath: String
    public let backupsIndexPath: String
    public let processLockPath: String
    public let fallbackProcessLockPath: String
    public let debugLogPath: String
    public let databasePath: String
    public let activeTags: [String]
    public let defaultInsertPosition: String
    public let templateManagementEnabled: Bool
    public let openNoteInEditModeByDefault: Bool
    public let createOpensNoteByDefault: Bool
    public let openUsesNewWindowByDefault: Bool
    public let createAddsActiveTagsByDefault: Bool
    public let tagsMergeMode: String
    public let defaultDiscoveryLimit: Int
    public let maxDiscoveryLimit: Int
    public let defaultSnippetLength: Int
    public let maxSnippetLength: Int
    public let backupRetentionDays: Int
    public let selectedNoteTokenConfigured: Bool
}

public struct BearAppDashboardSnapshot: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let diagnostics: [BearDoctorCheck]
    public let settings: BearAppSettingsSnapshot?
    public let settingsError: String?
}

public enum BearAppSupport {
    public static func loadDashboardSnapshot(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL,
        callbackAppBundleURLProvider: (FileManager) -> URL? = BearMCPAppLocator.installedAppBundleURL,
        callbackAppExecutableURLResolver: (URL, FileManager) throws -> URL = BearMCPAppLocator.executableURL,
        helperBundleURLProvider: (FileManager) -> URL? = BearSelectedNoteHelperLocator.installedAppBundleURL,
        helperExecutableURLResolver: (URL, FileManager) throws -> URL = BearSelectedNoteHelperLocator.executableURL
    ) -> BearAppDashboardSnapshot {
        do {
            let settings = try loadSettingsSnapshot(
                fileManager: fileManager,
                configDirectoryURL: configDirectoryURL,
                configFileURL: configFileURL,
                templateURL: templateURL
            )

            return BearAppDashboardSnapshot(
                generatedAt: Date(),
                diagnostics: doctorChecks(
                    fileManager: fileManager,
                    configuration: settings,
                    callbackAppBundleURLProvider: callbackAppBundleURLProvider,
                    callbackAppExecutableURLResolver: callbackAppExecutableURLResolver,
                    helperBundleURLProvider: helperBundleURLProvider,
                    helperExecutableURLResolver: helperExecutableURLResolver
                ),
                settings: settings,
                settingsError: nil
            )
        } catch {
            let message = localizedMessage(for: error)

            return BearAppDashboardSnapshot(
                generatedAt: Date(),
                diagnostics: doctorChecks(
                    fileManager: fileManager,
                    configLoadError: message,
                    callbackAppBundleURLProvider: callbackAppBundleURLProvider,
                    callbackAppExecutableURLResolver: callbackAppExecutableURLResolver,
                    helperBundleURLProvider: helperBundleURLProvider,
                    helperExecutableURLResolver: helperExecutableURLResolver
                ),
                settings: nil,
                settingsError: message
            )
        }
    }

    public static func loadSettingsSnapshot(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL
    ) throws -> BearAppSettingsSnapshot {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        return BearAppSettingsSnapshot(
            configDirectoryPath: configDirectoryURL.path,
            configFilePath: configFileURL.path,
            templatePath: templateURL.path,
            backupsDirectoryPath: BearPaths.backupsDirectoryURL.path,
            backupsIndexPath: BearPaths.backupsIndexURL.path,
            processLockPath: BearPaths.processLockURL.path,
            fallbackProcessLockPath: BearPaths.fallbackProcessLockURL.path,
            debugLogPath: BearPaths.debugLogURL.path,
            databasePath: configuration.databasePath,
            activeTags: configuration.activeTags,
            defaultInsertPosition: configuration.defaultInsertPosition.rawValue,
            templateManagementEnabled: configuration.templateManagementEnabled,
            openNoteInEditModeByDefault: configuration.openNoteInEditModeByDefault,
            createOpensNoteByDefault: configuration.createOpensNoteByDefault,
            openUsesNewWindowByDefault: configuration.openUsesNewWindowByDefault,
            createAddsActiveTagsByDefault: configuration.createAddsActiveTagsByDefault,
            tagsMergeMode: configuration.tagsMergeMode.rawValue,
            defaultDiscoveryLimit: configuration.defaultDiscoveryLimit,
            maxDiscoveryLimit: configuration.maxDiscoveryLimit,
            defaultSnippetLength: configuration.defaultSnippetLength,
            maxSnippetLength: configuration.maxSnippetLength,
            backupRetentionDays: configuration.backupRetentionDays,
            selectedNoteTokenConfigured: configuration.token != nil
        )
    }

    public static func doctorChecks(
        fileManager: FileManager = .default,
        configuration: BearAppSettingsSnapshot? = nil,
        configLoadError: String? = nil,
        callbackAppBundleURLProvider: (FileManager) -> URL? = BearMCPAppLocator.installedAppBundleURL,
        callbackAppExecutableURLResolver: (URL, FileManager) throws -> URL = BearMCPAppLocator.executableURL,
        helperBundleURLProvider: (FileManager) -> URL? = BearSelectedNoteHelperLocator.installedAppBundleURL,
        helperExecutableURLResolver: (URL, FileManager) throws -> URL = BearSelectedNoteHelperLocator.executableURL
    ) -> [BearDoctorCheck] {
        var checks = [
            BearDoctorCheck(
                key: "config",
                value: BearPaths.configFileURL.path,
                status: fileManager.fileExists(atPath: BearPaths.configFileURL.path) ? .ok : .missing,
                detail: statusDetail(fileManager.fileExists(atPath: BearPaths.configFileURL.path))
            ),
            BearDoctorCheck(
                key: "note-template",
                value: BearPaths.noteTemplateURL.path,
                status: fileManager.fileExists(atPath: BearPaths.noteTemplateURL.path) ? .ok : .missing,
                detail: statusDetail(fileManager.fileExists(atPath: BearPaths.noteTemplateURL.path))
            ),
            BearDoctorCheck(
                key: "backups-index",
                value: BearPaths.backupsIndexURL.path,
                status: fileManager.fileExists(atPath: BearPaths.backupsIndexURL.path) ? .ok : .missing,
                detail: statusDetail(fileManager.fileExists(atPath: BearPaths.backupsIndexURL.path))
            ),
            BearDoctorCheck(
                key: "process-lock-primary",
                value: BearPaths.processLockURL.path,
                status: fileManager.fileExists(atPath: BearPaths.processLockURL.path) ? .ok : .missing,
                detail: statusDetail(fileManager.fileExists(atPath: BearPaths.processLockURL.path))
            ),
            BearDoctorCheck(
                key: "process-lock-fallback",
                value: BearPaths.fallbackProcessLockURL.path,
                status: fileManager.fileExists(atPath: BearPaths.fallbackProcessLockURL.path) ? .ok : .missing,
                detail: statusDetail(fileManager.fileExists(atPath: BearPaths.fallbackProcessLockURL.path))
            ),
            BearDoctorCheck(
                key: "debug-log",
                value: BearPaths.debugLogURL.path,
                status: fileManager.fileExists(atPath: BearPaths.debugLogURL.path) ? .ok : .missing,
                detail: statusDetail(fileManager.fileExists(atPath: BearPaths.debugLogURL.path))
            ),
            BearDoctorCheck(
                key: "bear-db",
                value: BearPaths.defaultBearDatabaseURL.path,
                status: fileManager.fileExists(atPath: BearPaths.defaultBearDatabaseURL.path) ? .ok : .missing,
                detail: statusDetail(fileManager.fileExists(atPath: BearPaths.defaultBearDatabaseURL.path))
            ),
        ]

        if let configuration {
            checks.append(
                BearDoctorCheck(
                    key: "selected-note-token",
                    value: configuration.selectedNoteTokenConfigured ? "configured" : "not configured",
                    status: configuration.selectedNoteTokenConfigured ? .configured : .notConfigured
                )
            )

            if let callbackAppBundleURL = callbackAppBundleURLProvider(fileManager) {
                do {
                    let executableURL = try callbackAppExecutableURLResolver(callbackAppBundleURL, fileManager)
                    checks.append(
                        BearDoctorCheck(
                            key: "selected-note-callback-app",
                            value: callbackAppBundleURL.path,
                            status: .ok,
                            detail: "\(BearMCPAppLocator.installationLocationDescription(forAppBundleURL: callbackAppBundleURL)); preferred host -> \(executableURL.path)"
                        )
                    )
                } catch {
                    checks.append(
                        BearDoctorCheck(
                            key: "selected-note-callback-app",
                            value: callbackAppBundleURL.path,
                            status: .invalid,
                            detail: "invalid: \(localizedMessage(for: error))"
                        )
                    )
                }
            } else {
                checks.append(
                    BearDoctorCheck(
                        key: "selected-note-callback-app",
                        value: "not detected",
                        status: .missing,
                        detail: BearMCPAppLocator.installGuidance
                    )
                )
            }

            if let helperBundleURL = helperBundleURLProvider(fileManager) {
                do {
                    let executableURL = try helperExecutableURLResolver(helperBundleURL, fileManager)
                    checks.append(
                        BearDoctorCheck(
                            key: "selected-note-helper-fallback",
                            value: helperBundleURL.path,
                            status: .ok,
                            detail: "helper fallback; \(BearSelectedNoteHelperLocator.installationLocationDescription(forAppBundleURL: helperBundleURL)) -> \(executableURL.path)"
                        )
                    )
                } catch {
                    checks.append(
                        BearDoctorCheck(
                            key: "selected-note-helper-fallback",
                            value: helperBundleURL.path,
                            status: .invalid,
                            detail: "invalid: \(localizedMessage(for: error))"
                        )
                    )
                }
            }
        } else if let configLoadError {
            checks.append(
                BearDoctorCheck(
                    key: "config-load",
                    value: "failed",
                    status: .failed,
                    detail: configLoadError
                )
            )
        }

        return checks
    }

    private static func statusDetail(_ exists: Bool) -> String {
        exists ? "ok" : "missing"
    }

    private static func localizedMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
