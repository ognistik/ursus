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
    public let launcherPath: String
    public let launcherStatus: BearDoctorCheckStatus
    public let launcherStatusTitle: String
    public let launcherStatusDetail: String
    public let processLockPath: String
    public let fallbackProcessLockPath: String
    public let debugLogPath: String
    public let cliMaintenancePrompt: BearAppCLIMaintenancePrompt?
    public let databasePath: String
    public let inboxTags: [String]
    public let defaultInsertPosition: String
    public let templateManagementEnabled: Bool
    public let openNoteInEditModeByDefault: Bool
    public let createOpensNoteByDefault: Bool
    public let openUsesNewWindowByDefault: Bool
    public let createAddsInboxTagsByDefault: Bool
    public let tagsMergeMode: String
    public let defaultDiscoveryLimit: Int
    public let maxDiscoveryLimit: Int
    public let defaultSnippetLength: Int
    public let maxSnippetLength: Int
    public let backupRetentionDays: Int
    public let disabledTools: [BearToolName]
    public let selectedNoteTokenConfigured: Bool
    public let selectedNoteTokenStorageDescription: String
    public let selectedNoteTokenStatusDetail: String?
    public let toolToggles: [BearAppToolToggleSnapshot]
    public let hostAppSetups: [BearHostAppSetupSnapshot]
}

public enum BearAppCLIMaintenanceAction: String, Codable, Hashable, Sendable, Identifiable {
    case installLauncher
    case refreshLauncher

    public var id: String { rawValue }
}

public struct BearAppCLIMaintenancePrompt: Codable, Hashable, Sendable {
    public let title: String
    public let detail: String
    public let actions: [BearAppCLIMaintenanceAction]

    public init(
        title: String,
        detail: String,
        actions: [BearAppCLIMaintenanceAction]
    ) {
        self.title = title
        self.detail = detail
        self.actions = actions
    }
}

public enum BearAppPublicLauncherReconciliationStatus: String, Codable, Hashable, Sendable {
    case unchanged
    case installed
    case refreshed
    case unavailable
}

public struct BearAppPublicLauncherReconciliationResult: Codable, Hashable, Sendable {
    public let status: BearAppPublicLauncherReconciliationStatus
    public let sourcePath: String?
    public let destinationPath: String?

    public init(
        status: BearAppPublicLauncherReconciliationStatus,
        sourcePath: String? = nil,
        destinationPath: String? = nil
    ) {
        self.status = status
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
    }

    public var changed: Bool {
        switch status {
        case .installed, .refreshed:
            return true
        case .unchanged, .unavailable:
            return false
        }
    }
}

public struct BearAppToolToggleSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let tool: BearToolName
    public let title: String
    public let summary: String
    public let category: BearToolCategory
    public let enabled: Bool

    public var id: String { tool.rawValue }
}

public struct BearAppConfigurationDraft: Codable, Hashable, Sendable {
    public let databasePath: String
    public let inboxTags: [String]
    public let defaultInsertPosition: BearConfiguration.InsertDefault
    public let templateManagementEnabled: Bool
    public let openNoteInEditModeByDefault: Bool
    public let createOpensNoteByDefault: Bool
    public let openUsesNewWindowByDefault: Bool
    public let createAddsInboxTagsByDefault: Bool
    public let tagsMergeMode: BearConfiguration.TagsMergeMode
    public let defaultDiscoveryLimit: Int
    public let maxDiscoveryLimit: Int
    public let defaultSnippetLength: Int
    public let maxSnippetLength: Int
    public let backupRetentionDays: Int
    public let disabledTools: [BearToolName]

    public init(
        databasePath: String,
        inboxTags: [String],
        defaultInsertPosition: BearConfiguration.InsertDefault,
        templateManagementEnabled: Bool,
        openNoteInEditModeByDefault: Bool,
        createOpensNoteByDefault: Bool,
        openUsesNewWindowByDefault: Bool,
        createAddsInboxTagsByDefault: Bool,
        tagsMergeMode: BearConfiguration.TagsMergeMode,
        defaultDiscoveryLimit: Int,
        maxDiscoveryLimit: Int,
        defaultSnippetLength: Int,
        maxSnippetLength: Int,
        backupRetentionDays: Int,
        disabledTools: [BearToolName]
    ) {
        self.databasePath = databasePath
        self.inboxTags = inboxTags
        self.defaultInsertPosition = defaultInsertPosition
        self.templateManagementEnabled = templateManagementEnabled
        self.openNoteInEditModeByDefault = openNoteInEditModeByDefault
        self.createOpensNoteByDefault = createOpensNoteByDefault
        self.openUsesNewWindowByDefault = openUsesNewWindowByDefault
        self.createAddsInboxTagsByDefault = createAddsInboxTagsByDefault
        self.tagsMergeMode = tagsMergeMode
        self.defaultDiscoveryLimit = defaultDiscoveryLimit
        self.maxDiscoveryLimit = maxDiscoveryLimit
        self.defaultSnippetLength = defaultSnippetLength
        self.maxSnippetLength = maxSnippetLength
        self.backupRetentionDays = backupRetentionDays
        self.disabledTools = BearConfiguration.normalizedDisabledTools(disabledTools)
    }
}

public enum BearAppConfigurationField: String, Codable, Hashable, Sendable {
    case databasePath
    case inboxTags
    case defaultDiscoveryLimit
    case maxDiscoveryLimit
    case defaultSnippetLength
    case maxSnippetLength
    case backupRetentionDays
}

public enum BearAppConfigurationIssueSeverity: String, Codable, Hashable, Sendable {
    case error
    case warning
}

public struct BearAppConfigurationIssue: Codable, Hashable, Sendable, Identifiable {
    public let field: BearAppConfigurationField
    public let severity: BearAppConfigurationIssueSeverity
    public let message: String

    public var id: String {
        "\(field.rawValue):\(severity.rawValue):\(message)"
    }

    public init(
        field: BearAppConfigurationField,
        severity: BearAppConfigurationIssueSeverity,
        message: String
    ) {
        self.field = field
        self.severity = severity
        self.message = message
    }
}

public struct BearAppConfigurationValidationReport: Codable, Hashable, Sendable {
    public let issues: [BearAppConfigurationIssue]

    public init(issues: [BearAppConfigurationIssue] = []) {
        self.issues = issues
    }

    public var errors: [BearAppConfigurationIssue] {
        issues.filter { $0.severity == .error }
    }

    public var warnings: [BearAppConfigurationIssue] {
        issues.filter { $0.severity == .warning }
    }

    public var hasErrors: Bool {
        !errors.isEmpty
    }

    public func issues(for field: BearAppConfigurationField) -> [BearAppConfigurationIssue] {
        issues.filter { $0.field == field }
    }
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
        currentAppBundleURL: URL? = nil,
        launcherURL: URL = BearMCPCLILocator.publicLauncherURL,
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
                currentAppBundleURL: currentAppBundleURL,
                launcherURL: launcherURL,
                homeDirectoryURL: homeDirectoryURL
            )

            return BearAppDashboardSnapshot(
                generatedAt: Date(),
                diagnostics: doctorChecks(
                    fileManager: fileManager,
                    configuration: settings,
                    currentAppBundleURL: currentAppBundleURL,
                    launcherURL: launcherURL,
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
                    launcherURL: launcherURL,
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
        currentAppBundleURL: URL? = nil,
        launcherURL: URL = BearMCPCLILocator.publicLauncherURL,
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) throws -> BearAppSettingsSnapshot {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
        let tokenStatus = BearSelectedNoteTokenResolver.status(configuration: configuration)

        let launcherStatus = launcherStatus(
            fileManager: fileManager,
            launcherURL: launcherURL,
            currentAppBundleURL: currentAppBundleURL
        )

        return BearAppSettingsSnapshot(
            configDirectoryPath: configDirectoryURL.path,
            configFilePath: configFileURL.path,
            templatePath: templateURL.path,
            backupsDirectoryPath: BearPaths.backupsDirectoryURL.path,
            backupsIndexPath: BearPaths.backupsIndexURL.path,
            launcherPath: launcherURL.path,
            launcherStatus: launcherStatus.status,
            launcherStatusTitle: launcherStatus.title,
            launcherStatusDetail: launcherStatus.detail,
            processLockPath: BearPaths.processLockURL.path,
            fallbackProcessLockPath: BearPaths.fallbackProcessLockURL.path,
            debugLogPath: BearPaths.debugLogURL.path,
            cliMaintenancePrompt: cliMaintenancePrompt(launcherStatus: launcherStatus),
            databasePath: configuration.databasePath,
            inboxTags: configuration.inboxTags,
            defaultInsertPosition: configuration.defaultInsertPosition.rawValue,
            templateManagementEnabled: configuration.templateManagementEnabled,
            openNoteInEditModeByDefault: configuration.openNoteInEditModeByDefault,
            createOpensNoteByDefault: configuration.createOpensNoteByDefault,
            openUsesNewWindowByDefault: configuration.openUsesNewWindowByDefault,
            createAddsInboxTagsByDefault: configuration.createAddsInboxTagsByDefault,
            tagsMergeMode: configuration.tagsMergeMode.rawValue,
            defaultDiscoveryLimit: configuration.defaultDiscoveryLimit,
            maxDiscoveryLimit: configuration.maxDiscoveryLimit,
            defaultSnippetLength: configuration.defaultSnippetLength,
            maxSnippetLength: configuration.maxSnippetLength,
            backupRetentionDays: configuration.backupRetentionDays,
            disabledTools: configuration.disabledTools,
            selectedNoteTokenConfigured: tokenStatus.isConfigured,
            selectedNoteTokenStorageDescription: tokenStorageDescription(for: tokenStatus),
            selectedNoteTokenStatusDetail: tokenStatusDetail(for: tokenStatus),
            toolToggles: toolToggles(for: configuration),
            hostAppSetups: BearHostAppSupport.loadSetups(
                fileManager: fileManager,
                launcherURL: launcherURL,
                homeDirectoryURL: homeDirectoryURL
            )
        )
    }

    public static func saveSelectedNoteToken(
        _ token: String,
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL
    ) throws {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        try BearRuntimeBootstrap.saveConfiguration(
            configuration.updatingToken(token),
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
        templateURL: URL = BearPaths.noteTemplateURL
    ) throws -> BearResolvedSelectedNoteToken? {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        return BearSelectedNoteTokenResolver.resolve(configuration: configuration)
    }

    @discardableResult
    public static func installPublicLauncher(
        fromAppBundleURL appBundleURL: URL,
        fileManager: FileManager = .default,
        destinationURL: URL = BearMCPCLILocator.publicLauncherURL
    ) throws -> BearPublicCLILauncherInstallReceipt {
        try BearMCPCLILocator.installPublicLauncher(
            fromAppBundleURL: appBundleURL,
            fileManager: fileManager,
            destinationURL: destinationURL
        )
    }

    @discardableResult
    public static func reconcilePublicLauncherIfNeeded(
        fromAppBundleURL appBundleURL: URL,
        fileManager: FileManager = .default,
        destinationURL: URL = BearMCPCLILocator.publicLauncherURL,
        bundledCLIExecutableURLResolver: (URL, FileManager) throws -> URL = BearMCPCLILocator.bundledExecutableURL
    ) throws -> BearAppPublicLauncherReconciliationResult {
        do {
            _ = try bundledCLIExecutableURLResolver(appBundleURL, fileManager)
        } catch {
            return BearAppPublicLauncherReconciliationResult(status: .unavailable)
        }

        let destinationPath = destinationURL.path
        let destinationExists = fileManager.fileExists(atPath: destinationPath)

        if !destinationExists || !fileManager.isExecutableFile(atPath: destinationPath) {
            let receipt = try installPublicLauncher(
                fromAppBundleURL: appBundleURL,
                fileManager: fileManager,
                destinationURL: destinationURL
            )

            return BearAppPublicLauncherReconciliationResult(
                status: destinationExists ? .refreshed : .installed,
                sourcePath: receipt.sourcePath,
                destinationPath: receipt.destinationPath
            )
        }

        let launcherScript: String
        do {
            launcherScript = try BearMCPCLILocator.launcherScript(
                forAppBundleURL: appBundleURL,
                fileManager: fileManager
            )
        } catch {
            return BearAppPublicLauncherReconciliationResult(status: .unavailable)
        }

        let contentsMatch: Bool
        do {
            contentsMatch = try BearMCPCLILocator.launcherMatches(
                expectedScript: launcherScript,
                destinationURL: destinationURL,
            )
        } catch {
            let receipt = try installPublicLauncher(
                fromAppBundleURL: appBundleURL,
                fileManager: fileManager,
                destinationURL: destinationURL
            )

            return BearAppPublicLauncherReconciliationResult(
                status: .refreshed,
                sourcePath: receipt.sourcePath,
                destinationPath: receipt.destinationPath
            )
        }

        guard !contentsMatch else {
            return BearAppPublicLauncherReconciliationResult(status: .unchanged)
        }

        let receipt = try installPublicLauncher(
            fromAppBundleURL: appBundleURL,
            fileManager: fileManager,
            destinationURL: destinationURL
        )

        return BearAppPublicLauncherReconciliationResult(
            status: .refreshed,
            sourcePath: receipt.sourcePath,
            destinationPath: receipt.destinationPath
        )
    }

    public static func saveConfigurationDraft(
        _ draft: BearAppConfigurationDraft,
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL
    ) throws {
        let validation = validateConfigurationDraft(
            draft,
            fileManager: fileManager
        )
        if let firstError = validation.errors.first {
            throw BearError.invalidInput(firstError.message)
        }

        let currentConfiguration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
        let normalizedDatabasePath = draft.databasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDatabasePath.isEmpty else {
            throw BearError.invalidInput("Database path cannot be empty.")
        }

        let defaultDiscoveryLimit = max(1, draft.defaultDiscoveryLimit)
        let maxDiscoveryLimit = max(defaultDiscoveryLimit, draft.maxDiscoveryLimit)
        let defaultSnippetLength = max(1, draft.defaultSnippetLength)
        let maxSnippetLength = max(defaultSnippetLength, draft.maxSnippetLength)
        let normalizedInboxTags = normalizedInboxTags(draft.inboxTags)

        let updatedConfiguration = BearConfiguration(
            databasePath: normalizedDatabasePath,
            inboxTags: normalizedInboxTags,
            defaultInsertPosition: draft.defaultInsertPosition,
            templateManagementEnabled: draft.templateManagementEnabled,
            openNoteInEditModeByDefault: draft.openNoteInEditModeByDefault,
            createOpensNoteByDefault: draft.createOpensNoteByDefault,
            openUsesNewWindowByDefault: draft.openUsesNewWindowByDefault,
            createAddsInboxTagsByDefault: draft.createAddsInboxTagsByDefault,
            tagsMergeMode: draft.tagsMergeMode,
            defaultDiscoveryLimit: defaultDiscoveryLimit,
            maxDiscoveryLimit: maxDiscoveryLimit,
            defaultSnippetLength: defaultSnippetLength,
            maxSnippetLength: maxSnippetLength,
            backupRetentionDays: max(0, draft.backupRetentionDays),
            disabledTools: draft.disabledTools,
            token: currentConfiguration.token
        )

        try BearRuntimeBootstrap.saveConfiguration(
            updatedConfiguration,
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
    }

    public static func loadTemplateDraft(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL
    ) throws -> String {
        try BearRuntimeBootstrap.prepareSupportFiles(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )
        return try String(contentsOf: templateURL, encoding: .utf8)
    }

    public static func saveTemplateDraft(
        _ draft: String,
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL
    ) throws {
        let validation = validateTemplateDraft(draft)
        if let firstError = validation.errors.first {
            throw BearError.invalidInput(firstError.message)
        }

        try BearRuntimeBootstrap.prepareSupportFiles(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        guard let data = draft.data(using: .utf8) else {
            throw BearError.invalidInput("Template must be valid UTF-8 text.")
        }

        try data.write(to: templateURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: templateURL.path)
    }

    public static func validateConfigurationDraft(
        _ draft: BearAppConfigurationDraft,
        fileManager: FileManager = .default
    ) -> BearAppConfigurationValidationReport {
        var issues: [BearAppConfigurationIssue] = []
        let normalizedDatabasePath = draft.databasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTags = normalizedInboxTags(draft.inboxTags)

        if normalizedDatabasePath.isEmpty {
            issues.append(
                BearAppConfigurationIssue(
                    field: .databasePath,
                    severity: .error,
                    message: "Database path cannot be empty."
                )
            )
        } else {
            if !normalizedDatabasePath.hasPrefix("/") {
                issues.append(
                    BearAppConfigurationIssue(
                        field: .databasePath,
                        severity: .warning,
                        message: "Database path should usually be an absolute macOS path."
                    )
                )
            }

            if !fileManager.fileExists(atPath: normalizedDatabasePath) {
                issues.append(
                    BearAppConfigurationIssue(
                        field: .databasePath,
                        severity: .warning,
                        message: "No file exists at this database path right now."
                    )
                )
            }
        }

        if normalizedTags.isEmpty {
            issues.append(
                BearAppConfigurationIssue(
                    field: .inboxTags,
                    severity: .warning,
                    message: "Inbox tags are empty. Fallback note creation will not add inbox tags."
                )
            )
        }

        if draft.defaultDiscoveryLimit < 1 {
            issues.append(
                BearAppConfigurationIssue(
                    field: .defaultDiscoveryLimit,
                    severity: .error,
                    message: "Default discovery limit must be at least 1."
                )
            )
        }

        if draft.maxDiscoveryLimit < draft.defaultDiscoveryLimit {
            issues.append(
                BearAppConfigurationIssue(
                    field: .maxDiscoveryLimit,
                    severity: .error,
                    message: "Max discovery limit must be greater than or equal to the default discovery limit."
                )
            )
        }

        if draft.defaultSnippetLength < 1 {
            issues.append(
                BearAppConfigurationIssue(
                    field: .defaultSnippetLength,
                    severity: .error,
                    message: "Default snippet length must be at least 1."
                )
            )
        }

        if draft.maxSnippetLength < draft.defaultSnippetLength {
            issues.append(
                BearAppConfigurationIssue(
                    field: .maxSnippetLength,
                    severity: .error,
                    message: "Max snippet length must be greater than or equal to the default snippet length."
                )
            )
        }

        if draft.backupRetentionDays < 0 {
            issues.append(
                BearAppConfigurationIssue(
                    field: .backupRetentionDays,
                    severity: .error,
                    message: "Backup retention days cannot be negative."
                )
            )
        }

        return BearAppConfigurationValidationReport(issues: issues)
    }

    public static func validateTemplateDraft(_ draft: String) -> BearTemplateValidationReport {
        BearTemplateValidator.validate(draft)
    }

    public static func removeSelectedNoteToken(
        fileManager: FileManager = .default,
        configDirectoryURL: URL = BearPaths.configDirectoryURL,
        configFileURL: URL = BearPaths.configFileURL,
        templateURL: URL = BearPaths.noteTemplateURL
    ) throws {
        let configuration = try BearRuntimeBootstrap.loadConfiguration(
            fileManager: fileManager,
            configDirectoryURL: configDirectoryURL,
            configFileURL: configFileURL,
            templateURL: templateURL
        )

        try BearRuntimeBootstrap.saveConfiguration(
            configuration.updatingToken(nil),
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
        templateURL: URL = BearPaths.noteTemplateURL
    ) throws -> URL {
        _ = configDirectoryURL
        _ = templateURL
        return try BearSelectedNoteRequestAuthorizer.prepareManagedRequestURL(
            requestURL,
            fileManager: fileManager,
            configFileURL: configFileURL
        )
    }

    public static func doctorChecks(
        fileManager: FileManager = .default,
        configuration: BearAppSettingsSnapshot? = nil,
        configLoadError: String? = nil,
        currentAppBundleURL: URL? = nil,
        launcherURL: URL = BearMCPCLILocator.publicLauncherURL,
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

        let launcherStatus = launcherStatus(
            fileManager: fileManager,
            launcherURL: launcherURL,
            currentAppBundleURL: appBundleURLForBundledCLI,
            bundledCLIExecutableURLResolver: bundledCLIExecutableURLResolver
        )
        checks.append(
            BearDoctorCheck(
                key: "public-cli-launcher",
                value: launcherURL.path,
                status: launcherStatus.status,
                detail: launcherStatus.detail
            )
        )

        checks.append(
            contentsOf: BearHostAppSupport.diagnostics(
                fileManager: fileManager,
                launcherURL: launcherURL,
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
                            detail: "\(BearMCPAppLocator.installationLocationDescription(forAppBundleURL: callbackAppBundleURL)); dashboard app -> \(executableURL.path)"
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
                            detail: "selected-note background helper; \(BearSelectedNoteHelperLocator.installationLocationDescription(forAppBundleURL: helperBundleURL)) -> \(executableURL.path)"
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
        if status.tokenPresent {
            return "Stored in config.json"
        }

        return "Not configured"
    }

    private static func tokenStatusDetail(for status: BearSelectedNoteTokenStatus) -> String? {
        if status.tokenPresent {
            return "The Bear API token is stored in Bear MCP's config.json and hidden by default in the app UI."
        }

        return nil
    }

    private static func toolToggles(for configuration: BearConfiguration) -> [BearAppToolToggleSnapshot] {
        BearToolName.allCases.map { tool in
            BearAppToolToggleSnapshot(
                tool: tool,
                title: tool.title,
                summary: tool.summary,
                category: tool.category,
                enabled: configuration.isToolEnabled(tool)
            )
        }
    }

    private static func normalizedInboxTags(_ inboxTags: [String]) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []

        for tag in inboxTags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }

            seen.insert(trimmed)
            normalized.append(trimmed)
        }

        return normalized
    }

    private static func launcherStatus(
        fileManager: FileManager,
        launcherURL: URL,
        currentAppBundleURL: URL?,
        bundledCLIExecutableURLResolver: (URL, FileManager) throws -> URL = BearMCPCLILocator.bundledExecutableURL
    ) -> (status: BearDoctorCheckStatus, title: String, detail: String) {
        let launcherPath = launcherURL.path

        guard fileManager.fileExists(atPath: launcherPath) else {
            return (
                .missing,
                "Not installed",
                "Install the public launcher once so local MCP hosts and Terminal can run Bear MCP from one shared path."
            )
        }

        guard fileManager.isExecutableFile(atPath: launcherPath) else {
            return (
                .invalid,
                "Invalid executable",
                "The public launcher exists, but it is not executable. Repair it from this app."
            )
        }

        guard let currentAppBundleURL else {
            return (
                .ok,
                "Installed",
                "Local MCP hosts and Terminal should use this one launcher path."
            )
        }

        do {
            _ = try bundledCLIExecutableURLResolver(currentAppBundleURL, fileManager)
            let expectedLauncherScript = try BearMCPCLILocator.launcherScript(
                forAppBundleURL: currentAppBundleURL,
                fileManager: fileManager
            )
            guard try BearMCPCLILocator.launcherMatches(
                expectedScript: expectedLauncherScript,
                destinationURL: launcherURL
            ) else {
                return (
                    .invalid,
                    "Needs refresh",
                    "This public launcher does not match the current app build. Repair it from this app."
                )
            }
        } catch {
            return (
                .invalid,
                "Invalid launcher",
                "This app could not validate its launcher against the bundled CLI. Rebuild or reinstall Bear MCP.app."
            )
        }

        return (
            .ok,
            "Installed",
            "Local MCP hosts and Terminal should use this one launcher path."
        )
    }

    private static func cliMaintenancePrompt(
        launcherStatus: (status: BearDoctorCheckStatus, title: String, detail: String)
    ) -> BearAppCLIMaintenancePrompt? {
        switch launcherStatus.status {
        case .missing:
            return BearAppCLIMaintenancePrompt(
                title: "Install the public launcher",
                detail: launcherStatus.detail,
                actions: [.installLauncher]
            )
        case .invalid:
            return BearAppCLIMaintenancePrompt(
                title: "Repair the public launcher",
                detail: launcherStatus.detail,
                actions: [.refreshLauncher]
            )
        case .ok, .configured, .notConfigured, .failed:
            return nil
        }
    }

    private static func localizedMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

}
