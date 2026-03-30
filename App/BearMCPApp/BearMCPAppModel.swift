import AppKit
import BearApplication
import BearCore
import Foundation

@MainActor
final class BearMCPAppModel: ObservableObject {
    @Published private(set) var dashboard = BearAppSupport.loadDashboardSnapshot(
        currentAppBundleURL: Bundle.main.bundleURL
    )
    @Published var tokenDraft = ""
    @Published var revealsStoredToken = false
    @Published private(set) var tokenStatusMessage: String?
    @Published private(set) var tokenStatusError: String?
    @Published private(set) var cliStatusMessage: String?
    @Published private(set) var cliStatusError: String?
    @Published private(set) var bridgeStatusMessage: String?
    @Published private(set) var bridgeStatusError: String?
    @Published private(set) var hostSetupStatusMessage: String?
    @Published private(set) var hostSetupStatusError: String?
    @Published private(set) var configurationStatusMessage: String?
    @Published private(set) var configurationStatusError: String?
    @Published private(set) var configurationValidation = BearAppConfigurationValidationReport()
    @Published var templateDraft = ""
    @Published private(set) var templateStatusMessage: String?
    @Published private(set) var templateStatusError: String?
    @Published private(set) var templateValidation = BearTemplateValidationReport()
    @Published private(set) var storedSelectedNoteToken: String?

    @Published var databasePathDraft = ""
    @Published var inboxTagsDraft = ""
    @Published var defaultInsertPositionDraft: BearConfiguration.InsertDefault = .bottom
    @Published var templateManagementEnabledDraft = true
    @Published var openNoteInEditModeByDefaultDraft = true
    @Published var createOpensNoteByDefaultDraft = true
    @Published var openUsesNewWindowByDefaultDraft = true
    @Published var createAddsInboxTagsByDefaultDraft = true
    @Published var tagsMergeModeDraft: BearConfiguration.TagsMergeMode = .append
    @Published var defaultDiscoveryLimitDraft = 20
    @Published var maxDiscoveryLimitDraft = 100
    @Published var defaultSnippetLengthDraft = 280
    @Published var maxSnippetLengthDraft = 1_000
    @Published var backupRetentionDaysDraft = 30
    @Published private var disabledToolsDraft: Set<BearToolName> = []

    private var configurationAutosaveTask: Task<Void, Never>?
    private var suppressConfigurationAutosave = false
    private var lastSavedTemplateDraft = ""

    init() {
        applyDraft(from: dashboard.settings)
        reconcilePublicLauncherAutomatically()
        loadTemplateDraft()
        refreshStoredSelectedNoteToken()
    }

    func reload() {
        dashboard = BearAppSupport.loadDashboardSnapshot(
            currentAppBundleURL: Bundle.main.bundleURL
        )
        applyDraft(from: dashboard.settings)
        loadTemplateDraft()
        refreshStoredSelectedNoteToken()
    }

    func saveSelectedNoteToken() {
        do {
            try BearAppSupport.saveSelectedNoteToken(tokenDraft)
            tokenDraft = ""
            revealsStoredToken = false
            tokenStatusMessage = "Token saved in config.json."
            tokenStatusError = nil
            reload()
        } catch {
            tokenStatusMessage = nil
            tokenStatusError = localizedMessage(for: error)
        }
    }

    func removeSelectedNoteToken() {
        do {
            try BearAppSupport.removeSelectedNoteToken()
            tokenDraft = ""
            revealsStoredToken = false
            tokenStatusMessage = "Token removed from config.json."
            tokenStatusError = nil
            reload()
        } catch {
            tokenStatusMessage = nil
            tokenStatusError = localizedMessage(for: error)
        }
    }

    func configurationDraftDidChange() {
        guard !suppressConfigurationAutosave else {
            return
        }

        configurationAutosaveTask?.cancel()
        configurationValidation = validateCurrentConfigurationDraft()

        guard !configurationValidation.hasErrors else {
            configurationStatusMessage = nil
            configurationStatusError = "Fix the highlighted configuration errors before Bear MCP can save."
            return
        }

        configurationStatusError = nil
        configurationStatusMessage = "Saving changes..."
        configurationAutosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.saveConfigurationAutomatically()
            }
        }
    }

    func configurationIssues(for field: BearAppConfigurationField) -> [BearAppConfigurationIssue] {
        configurationValidation.issues(for: field)
    }

    func templateDraftDidChange() {
        templateValidation = validateCurrentTemplateDraft()

        if templateValidation.hasErrors {
            templateStatusMessage = nil
            templateStatusError = "Fix the template errors before saving."
            return
        }

        templateStatusError = nil
        templateStatusMessage = templateValidation.warnings.isEmpty
            ? nil
            : "Review the template warnings before saving."
    }

    func saveTemplate() {
        let validation = validateCurrentTemplateDraft()
        templateValidation = validation

        guard !validation.hasErrors else {
            templateStatusMessage = nil
            templateStatusError = "Fix the template errors before saving."
            return
        }

        do {
            try BearAppSupport.saveTemplateDraft(templateDraft)
            dashboard = BearAppSupport.loadDashboardSnapshot(
                currentAppBundleURL: Bundle.main.bundleURL
            )
            loadTemplateDraft()
            templateStatusMessage = validation.warnings.isEmpty
                ? "Template saved."
                : "Template saved. Review the warnings below."
            templateStatusError = nil
        } catch {
            templateStatusMessage = nil
            templateStatusError = localizedMessage(for: error)
        }
    }

    func revertTemplateDraft() {
        templateDraft = lastSavedTemplateDraft
        templateValidation = validateCurrentTemplateDraft()
        templateStatusMessage = nil
        templateStatusError = nil
    }

    func updateDatabasePathDraft(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            configurationStatusMessage = nil
            configurationStatusError = "Database path cannot be empty."
            configurationValidation = validateCurrentConfigurationDraft()
            return
        }

        databasePathDraft = trimmed
        configurationDraftDidChange()
    }

    private func saveConfigurationAutomatically() {
        let draft = currentConfigurationDraft()
        let validation = BearAppSupport.validateConfigurationDraft(draft)
        configurationValidation = validation

        guard !validation.hasErrors else {
            configurationStatusMessage = nil
            configurationStatusError = "Fix the highlighted configuration errors before Bear MCP can save."
            return
        }

        do {
            try BearAppSupport.saveConfigurationDraft(draft)
            dashboard = BearAppSupport.loadDashboardSnapshot(
                currentAppBundleURL: Bundle.main.bundleURL
            )
            configurationStatusMessage = validation.warnings.isEmpty
                ? "Configuration saved automatically."
                : "Configuration saved automatically. Review the warnings below."
            configurationStatusError = nil
        } catch {
            configurationStatusMessage = nil
            configurationStatusError = localizedMessage(for: error)
        }
    }

    func installPublicLauncher() {
        do {
            let receipt = try BearAppSupport.installPublicLauncher(fromAppBundleURL: Bundle.main.bundleURL)
            cliStatusMessage = "Launcher installed at \(receipt.destinationPath). Local MCP hosts and Terminal should use that path."
            cliStatusError = nil
            reload()
        } catch {
            cliStatusMessage = nil
            cliStatusError = localizedMessage(for: error)
        }
    }

    func performCLIMaintenanceAction(_ action: BearAppCLIMaintenanceAction) {
        switch action {
        case .installLauncher, .refreshLauncher:
            installPublicLauncher()
        }
    }

    func installBridge() {
        defer { reload() }
        do {
            let receipt = try BearAppSupport.installBridgeLaunchAgent(fromAppBundleURL: Bundle.main.bundleURL)
            bridgeStatusMessage = receipt.status == .installed
                ? "Bridge installed and started at \(receipt.endpointURL)."
                : "Bridge repaired and restarted at \(receipt.endpointURL)."
            bridgeStatusError = nil
        } catch {
            bridgeStatusMessage = nil
            bridgeStatusError = localizedMessage(for: error)
        }
    }

    func removeBridge() {
        defer { reload() }
        do {
            let receipt = try BearAppSupport.removeBridgeLaunchAgent()
            bridgeStatusMessage = receipt.status == .removed
                ? "Bridge LaunchAgent removed."
                : "Bridge LaunchAgent was already removed."
            bridgeStatusError = nil
        } catch {
            bridgeStatusMessage = nil
            bridgeStatusError = localizedMessage(for: error)
        }
    }

    func pauseBridge() {
        defer { reload() }
        do {
            let receipt = try BearAppSupport.pauseBridgeLaunchAgent()
            bridgeStatusMessage = receipt.status == .paused
                ? "Bridge paused without deleting its LaunchAgent."
                : "Bridge was already paused."
            bridgeStatusError = nil
        } catch {
            bridgeStatusMessage = nil
            bridgeStatusError = localizedMessage(for: error)
        }
    }

    func resumeBridge() {
        defer { reload() }
        do {
            let receipt = try BearAppSupport.resumeBridgeLaunchAgent()
            bridgeStatusMessage = receipt.status == .resumed
                ? "Bridge resumed at \(receipt.endpointURL ?? bridgeEndpointURL)."
                : "Bridge was already running."
            bridgeStatusError = nil
        } catch {
            bridgeStatusMessage = nil
            bridgeStatusError = localizedMessage(for: error)
        }
    }

    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFile(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func copyLauncherPath() {
        let path = launcherPath
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        cliStatusMessage = "Copied launcher path: \(path)"
        cliStatusError = nil
    }

    func copyBridgeURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(bridgeEndpointURL, forType: .string)
        bridgeStatusMessage = "Copied bridge MCP URL: \(bridgeEndpointURL)"
        bridgeStatusError = nil
    }

    func copyHostSetupSnippet(_ setup: BearHostAppSetupSnapshot) {
        guard let snippet = setup.snippet else {
            hostSetupStatusMessage = nil
            hostSetupStatusError = "No local snippet is available for \(setup.appName)."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet, forType: .string)
        hostSetupStatusMessage = "Copied \(setup.appName) setup snippet."
        hostSetupStatusError = nil
    }

    func copyHostConfigPath(_ setup: BearHostAppSetupSnapshot) {
        guard let configPath = setup.configPath else {
            hostSetupStatusMessage = nil
            hostSetupStatusError = "No local config path is tracked for \(setup.appName)."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(configPath, forType: .string)
        hostSetupStatusMessage = "Copied \(setup.appName) config path: \(configPath)"
        hostSetupStatusError = nil
    }

    func loadStoredSelectedNoteToken() {
        refreshStoredSelectedNoteToken()
    }

    func isToolEnabledInDraft(_ tool: BearToolName) -> Bool {
        !disabledToolsDraft.contains(tool)
    }

    func setToolEnabledInDraft(_ tool: BearToolName, enabled: Bool) {
        if enabled {
            disabledToolsDraft.remove(tool)
        } else {
            disabledToolsDraft.insert(tool)
        }

        configurationDraftDidChange()
    }

    var appDisplayName: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !value.isEmpty {
            return value
        }

        return "Bear MCP"
    }

    var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    var versionDescription: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(buildVersion))"
    }

    var maskedStoredSelectedNoteToken: String? {
        guard let storedSelectedNoteToken else {
            return nil
        }

        return String(repeating: "*", count: max(8, storedSelectedNoteToken.count))
    }

    private func refreshStoredSelectedNoteToken() {
        do {
            storedSelectedNoteToken = try BearAppSupport.loadResolvedSelectedNoteToken()?.value
            tokenStatusError = nil
        } catch {
            storedSelectedNoteToken = nil
            tokenStatusError = localizedMessage(for: error)
        }
    }

    var currentBundledCLIPath: String? {
        try? BearMCPCLILocator.bundledExecutableURL(forAppBundleURL: Bundle.main.bundleURL).path
    }

    var launcherPath: String {
        dashboard.settings?.launcherPath ?? BearMCPCLILocator.publicLauncherURL.path
    }

    var templateHasUnsavedChanges: Bool {
        templateDraft != lastSavedTemplateDraft
    }

    var bridgeEndpointURL: String {
        dashboard.settings?.bridge.endpointURL ?? "http://127.0.0.1:6190/mcp"
    }

    private var parsedInboxTags: [String] {
        inboxTagsDraft
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func currentConfigurationDraft() -> BearAppConfigurationDraft {
        BearAppConfigurationDraft(
            databasePath: databasePathDraft,
            inboxTags: parsedInboxTags,
            defaultInsertPosition: defaultInsertPositionDraft,
            templateManagementEnabled: templateManagementEnabledDraft,
            openNoteInEditModeByDefault: openNoteInEditModeByDefaultDraft,
            createOpensNoteByDefault: createOpensNoteByDefaultDraft,
            openUsesNewWindowByDefault: openUsesNewWindowByDefaultDraft,
            createAddsInboxTagsByDefault: createAddsInboxTagsByDefaultDraft,
            tagsMergeMode: tagsMergeModeDraft,
            defaultDiscoveryLimit: defaultDiscoveryLimitDraft,
            maxDiscoveryLimit: maxDiscoveryLimitDraft,
            defaultSnippetLength: defaultSnippetLengthDraft,
            maxSnippetLength: maxSnippetLengthDraft,
            backupRetentionDays: backupRetentionDaysDraft,
            disabledTools: Array(disabledToolsDraft)
        )
    }

    private func validateCurrentConfigurationDraft() -> BearAppConfigurationValidationReport {
        BearAppSupport.validateConfigurationDraft(currentConfigurationDraft())
    }

    private func validateCurrentTemplateDraft() -> BearTemplateValidationReport {
        BearAppSupport.validateTemplateDraft(templateDraft)
    }

    private func applyDraft(from settings: BearAppSettingsSnapshot?) {
        guard let settings else {
            return
        }

        suppressConfigurationAutosave = true
        databasePathDraft = settings.databasePath
        inboxTagsDraft = settings.inboxTags.joined(separator: ", ")
        defaultInsertPositionDraft = BearConfiguration.InsertDefault(rawValue: settings.defaultInsertPosition) ?? .bottom
        templateManagementEnabledDraft = settings.templateManagementEnabled
        openNoteInEditModeByDefaultDraft = settings.openNoteInEditModeByDefault
        createOpensNoteByDefaultDraft = settings.createOpensNoteByDefault
        openUsesNewWindowByDefaultDraft = settings.openUsesNewWindowByDefault
        createAddsInboxTagsByDefaultDraft = settings.createAddsInboxTagsByDefault
        tagsMergeModeDraft = BearConfiguration.TagsMergeMode(rawValue: settings.tagsMergeMode) ?? .append
        defaultDiscoveryLimitDraft = settings.defaultDiscoveryLimit
        maxDiscoveryLimitDraft = settings.maxDiscoveryLimit
        defaultSnippetLengthDraft = settings.defaultSnippetLength
        maxSnippetLengthDraft = settings.maxSnippetLength
        backupRetentionDaysDraft = settings.backupRetentionDays
        disabledToolsDraft = Set(settings.disabledTools)
        configurationValidation = validateCurrentConfigurationDraft()
        suppressConfigurationAutosave = false
    }

    private func loadTemplateDraft() {
        do {
            let draft = try BearAppSupport.loadTemplateDraft()
            templateDraft = draft
            lastSavedTemplateDraft = draft
            templateValidation = BearAppSupport.validateTemplateDraft(draft)
            templateStatusMessage = nil
            templateStatusError = nil
        } catch {
            templateDraft = ""
            lastSavedTemplateDraft = ""
            templateValidation = BearTemplateValidationReport()
            templateStatusMessage = nil
            templateStatusError = localizedMessage(for: error)
        }
    }

    private func localizedMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private func reconcilePublicLauncherAutomatically() {
        do {
            let result = try BearAppSupport.reconcilePublicLauncherIfNeeded(
                fromAppBundleURL: Bundle.main.bundleURL
            )

            guard result.changed else {
                return
            }

            reload()

            let destinationPath = result.destinationPath ?? launcherPath
            switch result.status {
            case .installed:
                cliStatusMessage = "Public launcher installed automatically at \(destinationPath)."
            case .refreshed:
                cliStatusMessage = "Public launcher repaired automatically at \(destinationPath)."
            case .unchanged, .unavailable:
                cliStatusMessage = nil
            }
            cliStatusError = nil
        } catch {
            cliStatusMessage = nil
            cliStatusError = localizedMessage(for: error)
        }
    }
}
