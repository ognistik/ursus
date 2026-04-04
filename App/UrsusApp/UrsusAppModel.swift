import AppKit
import BearApplication
import BearCore
import Foundation

enum UrsusBridgeOperation: Equatable {
    case install
    case repair
    case pause
    case resume
    case remove

    var progressMessage: String {
        switch self {
        case .install:
            return "Installing the bridge and waiting for the MCP endpoint to become ready..."
        case .repair:
            return "Repairing the bridge and waiting for the MCP endpoint to become ready..."
        case .pause:
            return "Pausing the bridge..."
        case .resume:
            return "Resuming the bridge and waiting for the MCP endpoint to become ready..."
        case .remove:
            return "Removing the bridge..."
        }
    }
}

@MainActor
final class UrsusAppModel: ObservableObject {
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
    @Published private(set) var activeBridgeOperation: UrsusBridgeOperation?

    @Published var databasePathDraft = ""
    @Published var inboxTagsDraft = ""
    @Published var bridgeHostDraft = BearBridgeConfiguration.defaultHost
    @Published var bridgePortDraft = BearBridgeConfiguration.preferredPort
    @Published var defaultInsertPositionDraft: BearConfiguration.InsertDefault = .bottom
    @Published var templateManagementEnabledDraft = true
    @Published var createOpensNoteByDefaultDraft = true
    @Published var openUsesNewWindowByDefaultDraft = true
    @Published var createAddsInboxTagsByDefaultDraft = true
    @Published var tagsMergeModeDraft: BearConfiguration.TagsMergeMode = .append
    @Published var defaultDiscoveryLimitDraft = 20
    @Published var defaultSnippetLengthDraft = 280
    @Published var backupRetentionDaysDraft = 30
    @Published private var disabledToolsDraft: Set<BearToolName> = []

    private var configurationAutosaveTask: Task<Void, Never>?
    private var bridgeStatusMessageClearTask: Task<Void, Never>?
    private var tokenStatusMessageClearTask: Task<Void, Never>?
    private var templateStatusMessageClearTask: Task<Void, Never>?
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
            hideStoredSelectedNoteToken()
            tokenStatusMessage = "Token saved in macOS Keychain."
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
            hideStoredSelectedNoteToken()
            tokenStatusMessage = "Token removed from macOS Keychain."
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
            configurationStatusError = "Fix the highlighted configuration errors before Ursus can save."
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
            templateStatusMessageClearTask?.cancel()
            loadTemplateDraft()
            templateStatusMessage = validation.warnings.isEmpty
                ? "Template saved."
                : "Template saved. Review the warnings below."
            templateStatusError = nil
            scheduleTemplateStatusMessageClear()
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

    func updateBridgePortDraft(_ value: Int) {
        let requestedPort = min(max(value, 1024), 65_535)
        let bridgeHost = bridgeHostDraft

        guard requestedPort != bridgePortDraft else {
            return
        }

        let selectedPort = selectBridgePortForDraft(
            requestedPort: requestedPort,
            currentPort: bridgePortDraft,
            host: bridgeHost
        )

        bridgePortDraft = selectedPort

        if selectedPort != requestedPort {
            bridgeStatusMessage = "Port \(requestedPort) is already in use. Switched to \(selectedPort) instead."
            bridgeStatusError = nil
        }

        configurationDraftDidChange()
    }

    private func saveConfigurationAutomatically() {
        let draft = currentConfigurationDraft()
        let validation = BearAppSupport.validateConfigurationDraft(draft)
        configurationValidation = validation

        guard !validation.hasErrors else {
            configurationStatusMessage = nil
            configurationStatusError = "Fix the highlighted configuration errors before Ursus can save."
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

    func installBridge(repairing: Bool = false) {
        let appBundleURL = Bundle.main.bundleURL
        runBridgeOperation(repairing ? .repair : .install) {
            let receipt = try BearAppSupport.installBridgeLaunchAgent(fromAppBundleURL: appBundleURL)
            return receipt.status == .installed
                ? "Bridge installed and started at \(receipt.endpointURL)."
                : "Bridge repaired and restarted at \(receipt.endpointURL)."
        }
    }

    func removeBridge() {
        runBridgeOperation(.remove) {
            let receipt = try BearAppSupport.removeBridgeLaunchAgent()
            return receipt.status == .removed
                ? "Bridge LaunchAgent removed."
                : "Bridge LaunchAgent was already removed."
        }
    }

    func pauseBridge() {
        runBridgeOperation(.pause) {
            let receipt = try BearAppSupport.pauseBridgeLaunchAgent()
            return receipt.status == .paused
                ? "Bridge paused without deleting its LaunchAgent."
                : "Bridge was already paused."
        }
    }

    func resumeBridge() {
        let endpointURL = bridgeEndpointURL
        runBridgeOperation(.resume) {
            let receipt = try BearAppSupport.resumeBridgeLaunchAgent()
            return receipt.status == .resumed
                ? "Bridge resumed at \(receipt.endpointURL ?? endpointURL)."
                : "Bridge was already running."
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

    func copySelectedNoteToken() {
        do {
            guard let token = try BearAppSupport.loadResolvedSelectedNoteToken()?.value, !token.isEmpty else {
                tokenStatusMessage = nil
                tokenStatusError = "Saved token unavailable in the app."
                return
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(token, forType: .string)
            tokenStatusMessageClearTask?.cancel()
            tokenStatusMessage = "Token copied."
            tokenStatusError = nil
            scheduleTokenStatusMessageClear()
        } catch {
            tokenStatusMessage = nil
            tokenStatusError = localizedMessage(for: error)
        }
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

    func updateInboxTagsDraft(from tags: [String]) {
        let normalizedTags = normalizedTags(from: tags)
        inboxTagsDraft = normalizedTags.joined(separator: ", ")
        configurationDraftDidChange()
    }

    func addInboxTags(from rawValue: String) {
        let additions = normalizedTags(
            from: rawValue
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map(String.init)
        )

        guard !additions.isEmpty else {
            return
        }

        updateInboxTagsDraft(from: parsedInboxTags + additions)
    }

    func removeInboxTag(_ tag: String) {
        updateInboxTagsDraft(from: parsedInboxTags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame })
    }

    func loadStoredSelectedNoteToken() {
        if revealsStoredToken {
            hideStoredSelectedNoteToken()
            tokenStatusError = nil
            return
        }

        do {
            storedSelectedNoteToken = try BearAppSupport.loadResolvedSelectedNoteToken()?.value
            revealsStoredToken = storedSelectedNoteToken != nil
            tokenStatusError = nil
        } catch {
            hideStoredSelectedNoteToken()
            tokenStatusError = localizedMessage(for: error)
        }
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

        return "Ursus"
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
        dashboard.settings?.selectedNoteTokenConfigured == true ? "********" : nil
    }

    private func refreshStoredSelectedNoteToken() {
        hideStoredSelectedNoteToken()
    }

    private func hideStoredSelectedNoteToken() {
        revealsStoredToken = false
        storedSelectedNoteToken = nil
    }

    var currentBundledCLIPath: String? {
        try? UrsusCLILocator.bundledExecutableURL(forAppBundleURL: Bundle.main.bundleURL).path
    }

    var launcherPath: String {
        dashboard.settings?.launcherPath ?? UrsusCLILocator.publicLauncherURL.path
    }

    var templateHasUnsavedChanges: Bool {
        templateDraft != lastSavedTemplateDraft
    }

    var bridgeEndpointURL: String {
        dashboard.settings?.bridge.endpointURL ?? "http://127.0.0.1:6190/mcp"
    }

    var isBridgeOperationInProgress: Bool {
        activeBridgeOperation != nil
    }

    var bridgeOperationProgressMessage: String? {
        activeBridgeOperation?.progressMessage
    }

    var setupHostSetups: [BearHostAppSetupSnapshot] {
        dashboard.settings?.hostAppSetups.filter(\.presentInSetup) ?? []
    }

    var inboxTagValues: [String] {
        parsedInboxTags
    }

    private var parsedInboxTags: [String] {
        normalizedTags(
            from: inboxTagsDraft
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map(String.init)
        )
    }

    private func currentConfigurationDraft() -> BearAppConfigurationDraft {
        BearAppConfigurationDraft(
            databasePath: databasePathDraft,
            inboxTags: parsedInboxTags,
            bridgeHost: bridgeHostDraft,
            bridgePort: bridgePortDraft,
            defaultInsertPosition: defaultInsertPositionDraft,
            templateManagementEnabled: templateManagementEnabledDraft,
            createOpensNoteByDefault: createOpensNoteByDefaultDraft,
            openUsesNewWindowByDefault: openUsesNewWindowByDefaultDraft,
            createAddsInboxTagsByDefault: createAddsInboxTagsByDefaultDraft,
            tagsMergeMode: tagsMergeModeDraft,
            defaultDiscoveryLimit: defaultDiscoveryLimitDraft,
            defaultSnippetLength: defaultSnippetLengthDraft,
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
        bridgeHostDraft = settings.bridge.host
        bridgePortDraft = settings.bridge.port
        defaultInsertPositionDraft = BearConfiguration.InsertDefault(rawValue: settings.defaultInsertPosition) ?? .bottom
        templateManagementEnabledDraft = settings.templateManagementEnabled
        createOpensNoteByDefaultDraft = settings.createOpensNoteByDefault
        openUsesNewWindowByDefaultDraft = settings.openUsesNewWindowByDefault
        createAddsInboxTagsByDefaultDraft = settings.createAddsInboxTagsByDefault
        tagsMergeModeDraft = BearConfiguration.TagsMergeMode(rawValue: settings.tagsMergeMode) ?? .append
        defaultDiscoveryLimitDraft = settings.defaultDiscoveryLimit
        defaultSnippetLengthDraft = settings.defaultSnippetLength
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

    private func runBridgeOperation(
        _ operation: UrsusBridgeOperation,
        work: @escaping @Sendable () throws -> String
    ) {
        guard activeBridgeOperation == nil else {
            return
        }

        activeBridgeOperation = operation
        bridgeStatusMessageClearTask?.cancel()
        bridgeStatusMessage = nil
        bridgeStatusError = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<String, Error>
            do {
                result = .success(try work())
            } catch {
                result = .failure(error)
            }

            await MainActor.run { [weak self, result] in
                self?.completeBridgeOperation(with: result)
            }
        }
    }

    private func completeBridgeOperation(with result: Result<String, Error>) {
        let completedOperation = activeBridgeOperation
        activeBridgeOperation = nil
        reload()
        bridgeStatusMessageClearTask?.cancel()

        switch result {
        case .success(let message):
            bridgeStatusMessage = message
            bridgeStatusError = nil
            if completedOperation != nil {
                scheduleBridgeStatusMessageClear()
            }
        case .failure(let error):
            bridgeStatusMessage = nil
            bridgeStatusError = localizedMessage(for: error)
        }
    }

    private func scheduleBridgeStatusMessageClear() {
        bridgeStatusMessageClearTask?.cancel()
        let currentMessage = bridgeStatusMessage

        bridgeStatusMessageClearTask = Task { [weak self, currentMessage] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard self?.bridgeStatusMessage == currentMessage else {
                    return
                }

                self?.bridgeStatusMessage = nil
            }
        }
    }

    private func scheduleTemplateStatusMessageClear() {
        templateStatusMessageClearTask?.cancel()
        let currentMessage = templateStatusMessage

        templateStatusMessageClearTask = Task { [weak self, currentMessage] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard self?.templateStatusMessage == currentMessage else {
                    return
                }

                self?.templateStatusMessage = nil
            }
        }
    }

    private func scheduleTokenStatusMessageClear() {
        tokenStatusMessageClearTask?.cancel()
        let currentMessage = tokenStatusMessage

        tokenStatusMessageClearTask = Task { [weak self, currentMessage] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard self?.tokenStatusMessage == currentMessage else {
                    return
                }

                self?.tokenStatusMessage = nil
            }
        }
    }

    private func localizedMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private func selectBridgePortForDraft(
        requestedPort: Int,
        currentPort: Int,
        host: String
    ) -> Int {
        if bridgePortIsSelectable(requestedPort, host: host) {
            return requestedPort
        }

        let searchUpwardFirst = requestedPort >= currentPort

        if searchUpwardFirst {
            for candidate in requestedPort...65_535 where bridgePortIsSelectable(candidate, host: host) {
                return candidate
            }

            if requestedPort > 1024 {
                for candidate in stride(from: requestedPort - 1, through: 1024, by: -1) where bridgePortIsSelectable(candidate, host: host) {
                    return candidate
                }
            }
        } else {
            for candidate in stride(from: requestedPort, through: 1024, by: -1) where bridgePortIsSelectable(candidate, host: host) {
                return candidate
            }

            if requestedPort < 65_535 {
                for candidate in (requestedPort + 1)...65_535 where bridgePortIsSelectable(candidate, host: host) {
                    return candidate
                }
            }
        }

        return currentPort
    }

    private func bridgePortIsSelectable(_ port: Int, host: String) -> Bool {
        if let bridge = dashboard.settings?.bridge,
           bridge.loaded,
           bridge.host == host,
           bridge.port == port
        {
            return true
        }

        return BearBridgePortAllocator.isPortAvailable(host: host, port: port)
    }

    private func normalizedTags(from tags: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else {
                continue
            }

            normalized.append(trimmed)
        }

        return normalized
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
