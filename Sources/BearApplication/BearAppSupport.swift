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
    public let appManagedCLIPath: String
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
    public let selectedNoteTokenStoredInKeychain: Bool
    public let selectedNoteLegacyConfigTokenDetected: Bool
    public let selectedNoteTokenStorageDescription: String
    public let selectedNoteTokenStatusDetail: String?
    public let hostAppSetups: [BearHostAppSetupSnapshot]
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
        tokenStore: any BearSelectedNoteTokenStore = BearKeychainSelectedNoteTokenStore(),
        allowSecureTokenStatusRead: Bool = false,
        currentAppBundleURL: URL? = nil,
        appManagedCLIURL: URL = BearMCPCLILocator.appManagedInstallURL,
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        bundledCLIExecutableURLResolver: (URL, FileManager) throws -> URL = BearMCPCLILocator.bundledExecutableURL,
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
                templateURL: templateURL,
                tokenStore: tokenStore,
                allowSecureTokenStatusRead: allowSecureTokenStatusRead,
                appManagedCLIURL: appManagedCLIURL,
                homeDirectoryURL: homeDirectoryURL
            )

            return BearAppDashboardSnapshot(
                generatedAt: Date(),
                diagnostics: doctorChecks(
                    fileManager: fileManager,
                    configuration: settings,
                    currentAppBundleURL: currentAppBundleURL,
                    appManagedCLIURL: appManagedCLIURL,
                    homeDirectoryURL: homeDirectoryURL,
                    bundledCLIExecutableURLResolver: bundledCLIExecutableURLResolver,
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
                    currentAppBundleURL: currentAppBundleURL,
                    appManagedCLIURL: appManagedCLIURL,
                    homeDirectoryURL: homeDirectoryURL,
                    bundledCLIExecutableURLResolver: bundledCLIExecutableURLResolver,
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
        templateURL: URL = BearPaths.noteTemplateURL,
        tokenStore: any BearSelectedNoteTokenStore = BearKeychainSelectedNoteTokenStore(),
        allowSecureTokenStatusRead: Bool = false,
        appManagedCLIURL: URL = BearMCPCLILocator.appManagedInstallURL,
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) throws -> BearAppSettingsSnapshot {
        var configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
        let tokenStatus = BearSelectedNoteTokenResolver.status(
            configuration: configuration,
            tokenStore: tokenStore,
            allowSecureRead: allowSecureTokenStatusRead
        )

        if allowSecureTokenStatusRead && tokenStatus.keychainTokenPresent && !configuration.selectedNoteTokenStoredInKeychain {
            configuration = configuration.updatingSelectedNoteTokenStorage(
                token: configuration.token,
                storedInKeychain: true
            )
            try BearRuntimeBootstrap.saveConfiguration(
                configuration,
                fileManager: fileManager,
                configDirectoryURL: configDirectoryURL,
                configFileURL: configFileURL,
                templateURL: templateURL
            )
        }

        return BearAppSettingsSnapshot(
            configDirectoryPath: configDirectoryURL.path,
            configFilePath: configFileURL.path,
            templatePath: templateURL.path,
            backupsDirectoryPath: BearPaths.backupsDirectoryURL.path,
            backupsIndexPath: BearPaths.backupsIndexURL.path,
            appManagedCLIPath: appManagedCLIURL.path,
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
            selectedNoteTokenConfigured: tokenStatus.isConfigured,
            selectedNoteTokenStoredInKeychain: tokenStatus.keychainTokenPresent,
            selectedNoteLegacyConfigTokenDetected: tokenStatus.legacyConfigTokenPresent,
            selectedNoteTokenStorageDescription: tokenStorageDescription(for: tokenStatus),
            selectedNoteTokenStatusDetail: tokenStatusDetail(for: tokenStatus),
            hostAppSetups: BearHostAppSupport.loadSetups(
                fileManager: fileManager,
                appManagedCLIURL: appManagedCLIURL,
                homeDirectoryURL: homeDirectoryURL
            )
        )
    }

    public static func saveSelectedNoteToken(
        _ token: String,
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL,
        tokenStore: any BearSelectedNoteTokenStore = BearKeychainSelectedNoteTokenStore()
    ) throws {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        try tokenStore.saveToken(token)
        try BearRuntimeBootstrap.saveConfiguration(
            configuration.updatingSelectedNoteTokenStorage(
                storedInKeychain: true
            ),
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
    }

    public static func loadResolvedSelectedNoteToken(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL,
        tokenStore: any BearSelectedNoteTokenStore = BearKeychainSelectedNoteTokenStore()
    ) throws -> BearResolvedSelectedNoteToken? {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        return try BearSelectedNoteTokenResolver.resolve(
            configuration: configuration,
            tokenStore: tokenStore
        )
    }

    @discardableResult
    public static func installBundledCLI(
        fromAppBundleURL appBundleURL: URL,
        fileManager: FileManager = .default,
        destinationURL: URL = BearMCPCLILocator.appManagedInstallURL
    ) throws -> BearBundledCLIInstallReceipt {
        try BearMCPCLILocator.installBundledExecutable(
            fromAppBundleURL: appBundleURL,
            fileManager: fileManager,
            destinationURL: destinationURL
        )
    }

    @discardableResult
    public static func importSelectedNoteTokenFromConfig(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL,
        tokenStore: any BearSelectedNoteTokenStore = BearKeychainSelectedNoteTokenStore()
    ) throws -> Bool {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        guard let token = configuration.token else {
            return false
        }

        try tokenStore.saveToken(token)
        try BearRuntimeBootstrap.saveConfiguration(
            configuration.updatingSelectedNoteTokenStorage(
                storedInKeychain: true
            ),
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
        return true
    }

    public static func removeSelectedNoteToken(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL,
        tokenStore: any BearSelectedNoteTokenStore = BearKeychainSelectedNoteTokenStore()
    ) throws {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        try tokenStore.removeToken()
        try BearRuntimeBootstrap.saveConfiguration(
            configuration.updatingSelectedNoteTokenStorage(
                storedInKeychain: false
            ),
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
    }

    public static func prepareManagedSelectedNoteRequestURL(
        _ requestURL: URL,
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL,
        tokenStore: any BearSelectedNoteTokenStore = BearKeychainSelectedNoteTokenStore()
    ) throws -> URL {
        guard requiresManagedSelectedNoteTokenInjection(requestURL) else {
            return requestURL
        }

        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
        guard let token = try BearSelectedNoteTokenResolver.resolve(
            configuration: configuration,
            tokenStore: tokenStore
        )?.value else {
            throw BearError.invalidInput("Selected-note targeting requires a configured Bear API token.")
        }

        guard var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
            throw BearError.invalidInput("Invalid Bear selected-note request URL.")
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = queryItems

        guard let resolvedURL = components.url else {
            throw BearError.invalidInput("Failed to prepare the Bear selected-note request URL.")
        }

        return resolvedURL
    }

    public static func doctorChecks(
        fileManager: FileManager = .default,
        configuration: BearAppSettingsSnapshot? = nil,
        configLoadError: String? = nil,
        currentAppBundleURL: URL? = nil,
        appManagedCLIURL: URL = BearMCPCLILocator.appManagedInstallURL,
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        bundledCLIExecutableURLResolver: (URL, FileManager) throws -> URL = BearMCPCLILocator.bundledExecutableURL,
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

        let appBundleURLForBundledCLI = currentAppBundleURL ?? callbackAppBundleURLProvider(fileManager)

        if let appBundleURLForBundledCLI {
            do {
                let bundledCLIURL = try bundledCLIExecutableURLResolver(appBundleURLForBundledCLI, fileManager)
                checks.append(
                    BearDoctorCheck(
                        key: "bundled-cli",
                        value: bundledCLIURL.path,
                        status: .ok,
                        detail: "embedded in \(appBundleURLForBundledCLI.path)"
                    )
                )
            } catch {
                checks.append(
                    BearDoctorCheck(
                        key: "bundled-cli",
                        value: appBundleURLForBundledCLI.path,
                        status: .invalid,
                        detail: "invalid: \(localizedMessage(for: error))"
                    )
                )
            }
        } else {
            checks.append(
                BearDoctorCheck(
                    key: "bundled-cli",
                    value: "not detected",
                    status: .missing,
                    detail: BearMCPCLILocator.bundledExecutableGuidance
                )
            )
        }

        let appManagedCLIPath = appManagedCLIURL.path
        if fileManager.fileExists(atPath: appManagedCLIPath) {
            checks.append(
                BearDoctorCheck(
                    key: "app-managed-cli",
                    value: appManagedCLIPath,
                    status: fileManager.isExecutableFile(atPath: appManagedCLIPath) ? .ok : .invalid,
                    detail: fileManager.isExecutableFile(atPath: appManagedCLIPath)
                        ? "stable CLI path for MCP hosts"
                        : "invalid: app-managed CLI is not executable"
                )
            )
        } else {
            checks.append(
                BearDoctorCheck(
                    key: "app-managed-cli",
                    value: appManagedCLIPath,
                    status: .missing,
                    detail: BearMCPCLILocator.appManagedInstallGuidance
                )
            )
        }

        checks.append(
            contentsOf: BearHostAppSupport.diagnostics(
                fileManager: fileManager,
                appManagedCLIURL: appManagedCLIURL,
                homeDirectoryURL: homeDirectoryURL
            )
        )

        if let configuration {
            checks.append(
                BearDoctorCheck(
                    key: "selected-note-token",
                    value: configuration.selectedNoteTokenStorageDescription,
                    status: configuration.selectedNoteTokenConfigured
                        ? .configured
                        : (configuration.selectedNoteTokenStatusDetail != nil ? .failed : .notConfigured),
                    detail: configuration.selectedNoteTokenStatusDetail
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

    private static func tokenStorageDescription(for status: BearSelectedNoteTokenStatus) -> String {
        if status.keychainTokenPresent {
            if status.keychainStatusDerivedFromHint {
                return "Managed in Keychain"
            }
            return "Stored in Keychain"
        }

        if status.legacyConfigTokenPresent {
            return "Legacy config.json fallback"
        }

        if status.keychainAccessError != nil {
            return "Keychain unavailable"
        }

        return "Not configured"
    }

    private static func tokenStatusDetail(for status: BearSelectedNoteTokenStatus) -> String? {
        if status.keychainTokenPresent {
            if status.keychainStatusDerivedFromHint {
                return status.legacyConfigTokenPresent
                    ? "Config says the token is managed in Keychain, and a legacy plaintext token is still present in config.json. Open token settings only when you intentionally want to re-read or change the secret."
                    : "Config says the Bear API token is managed in macOS Keychain. Normal diagnostics avoid re-reading it so routine checks do not trigger Keychain prompts."
            }
            return status.legacyConfigTokenPresent
                ? "A legacy plaintext token is still present in config.json. Saving or removing the token from the app will clean that up."
                : "The Bear API token is stored in macOS Keychain."
        }

        if status.legacyConfigTokenPresent {
            return "The current token is still being read from config.json. Import it into Keychain from the app to keep it out of plaintext config."
        }

        return status.keychainAccessError
    }

    private static func localizedMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private static func requiresManagedSelectedNoteTokenInjection(_ requestURL: URL) -> Bool {
        guard
            let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
            components.scheme == "bear",
            components.host == "x-callback-url",
            components.path == "/open-note"
        else {
            return false
        }

        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        let selectedValue = query["selected"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tokenValue = query["token"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (selectedValue == "yes" || selectedValue == "true" || selectedValue == "1") && tokenValue.isEmpty
    }
}
