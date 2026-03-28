import AppKit
import BearApplication
import BearCore
import Combine
import Foundation

@MainActor
final class BearMCPAppModel: ObservableObject {
    let runsHeadlessCallbackHost: Bool

    @Published private(set) var dashboard = BearAppSupport.loadDashboardSnapshot(
        currentAppBundleURL: Bundle.main.bundleURL
    )
    @Published private(set) var lastIncomingCallbackURL: URL?
    @Published var tokenDraft = ""
    @Published var revealsStoredToken = false
    @Published private(set) var tokenStatusMessage: String?
    @Published private(set) var tokenStatusError: String?
    @Published private(set) var cliStatusMessage: String?
    @Published private(set) var cliStatusError: String?
    @Published private(set) var hostSetupStatusMessage: String?
    @Published private(set) var hostSetupStatusError: String?
    @Published private(set) var configurationStatusMessage: String?
    @Published private(set) var configurationStatusError: String?
    @Published private(set) var configurationValidation = BearAppConfigurationValidationReport()
    @Published private(set) var storedSelectedNoteToken: String?
    @Published private(set) var storedTokenHasBeenExplicitlyLoaded = false

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

    private var cancellables: Set<AnyCancellable> = []
    private var configurationAutosaveTask: Task<Void, Never>?
    private var suppressConfigurationAutosave = false

    init(
        runsHeadlessCallbackHost: Bool = BearSelectedNoteAppHost.shouldRunHeadless()
    ) {
        self.runsHeadlessCallbackHost = runsHeadlessCallbackHost

        NotificationCenter.default.publisher(for: .bearMCPDidReceiveIncomingCallbackURL)
            .compactMap { $0.object as? URL }
            .sink { [weak self] url in
                self?.recordIncomingCallback(url)
            }
            .store(in: &cancellables)

        applyDraft(from: dashboard.settings)
    }

    func reload() {
        dashboard = BearAppSupport.loadDashboardSnapshot(
            currentAppBundleURL: Bundle.main.bundleURL
        )
        applyDraft(from: dashboard.settings)
    }

    func saveSelectedNoteToken() {
        do {
            try BearAppSupport.saveSelectedNoteToken(tokenDraft)
            tokenDraft = ""
            storedSelectedNoteToken = nil
            storedTokenHasBeenExplicitlyLoaded = false
            revealsStoredToken = false
            tokenStatusMessage = "Token saved in Keychain. Any legacy config copy was cleaned up."
            tokenStatusError = nil
            reload()
        } catch {
            tokenStatusMessage = nil
            tokenStatusError = localizedMessage(for: error)
        }
    }

    func importSelectedNoteTokenFromConfig() {
        do {
            let imported = try BearAppSupport.importSelectedNoteTokenFromConfig()
            storedSelectedNoteToken = nil
            storedTokenHasBeenExplicitlyLoaded = false
            revealsStoredToken = false
            tokenStatusMessage = imported
                ? "Token imported into Keychain and removed from config.json."
                : "No legacy config token was found to import."
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
            storedSelectedNoteToken = nil
            storedTokenHasBeenExplicitlyLoaded = false
            revealsStoredToken = false
            tokenStatusMessage = "Token removed. Keychain and any legacy config copy are now cleared."
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

    func installBundledCLI() {
        do {
            let receipt = try BearAppSupport.installBundledCLI(fromAppBundleURL: Bundle.main.bundleURL)
            cliStatusMessage = "CLI installed at \(receipt.destinationPath). MCP hosts should use that path."
            cliStatusError = nil
            reload()
        } catch {
            cliStatusMessage = nil
            cliStatusError = localizedMessage(for: error)
        }
    }

    func installTerminalCLI() {
        do {
            let receipt = try BearAppSupport.installTerminalCLI()
            cliStatusMessage = "Terminal CLI installed at \(receipt.destinationPath) from \(receipt.sourcePath)"
            cliStatusError = nil
            reload()
        } catch {
            cliStatusMessage = nil
            cliStatusError = localizedMessage(for: error)
        }
    }

    func performCLIMaintenanceAction(_ action: BearAppCLIMaintenanceAction) {
        switch action {
        case .installAppManagedCLI, .refreshAppManagedCLI:
            installBundledCLI()
        case .installTerminalCLI, .refreshTerminalCLI:
            installTerminalCLI()
        }
    }

    func recordIncomingCallback(_ url: URL) {
        lastIncomingCallbackURL = url
    }

    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFile(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func copyInstalledCLIPath() {
        let path = installedCLIPath
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        cliStatusMessage = "Copied CLI path: \(path)"
        cliStatusError = nil
    }

    func copyTerminalCLIPath() {
        let path = terminalCLIPath
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        cliStatusMessage = "Copied terminal CLI path: \(path)"
        cliStatusError = nil
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
        do {
            storedSelectedNoteToken = try BearAppSupport.loadResolvedSelectedNoteToken()?.value
            storedTokenHasBeenExplicitlyLoaded = true
            tokenStatusError = nil
        } catch {
            storedSelectedNoteToken = nil
            storedTokenHasBeenExplicitlyLoaded = false
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

    var callbackSchemes: [String] {
        guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return []
        }

        return urlTypes
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .sorted()
    }

    var maskedStoredSelectedNoteToken: String? {
        guard let storedSelectedNoteToken else {
            return nil
        }

        return String(repeating: "*", count: max(8, storedSelectedNoteToken.count))
    }

    var currentBundledCLIPath: String? {
        try? BearMCPCLILocator.bundledExecutableURL(forAppBundleURL: Bundle.main.bundleURL).path
    }

    var installedCLIPath: String {
        dashboard.settings?.appManagedCLIPath ?? BearMCPCLILocator.appManagedInstallURL.path
    }

    var terminalCLIPath: String {
        dashboard.settings?.terminalCLIPath ?? BearMCPCLILocator.userCommandInstallURL.path
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

    private func localizedMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

extension Notification.Name {
    static let bearMCPDidReceiveIncomingCallbackURL = Notification.Name("bear-mcp.did-receive-incoming-callback-url")
}
