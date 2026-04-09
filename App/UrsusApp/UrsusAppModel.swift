import AppKit
import BearApplication
import BearCLIRuntime
import BearCore
import Foundation

enum UrsusBridgeOperation: Equatable {
    case install
    case repair
    case restart
    case pause
    case resume
    case remove
}

@MainActor
final class UrsusAppModel: ObservableObject {
    @Published private(set) var dashboard = BearAppSupport.loadDashboardSnapshot(
        currentAppBundleURL: Bundle.main.bundleURL,
        bridgeSurfaceMarkerProvider: UrsusCLIRuntime.bridgeSurfaceMarker
    )
    @Published var tokenDraft = ""
    @Published var revealsStoredToken = false
    @Published private(set) var tokenStatusError: String?
    @Published private(set) var cliStatusError: String?
    @Published private(set) var bridgeStatusError: String?
    @Published private(set) var hostSetupStatusError: String?
    @Published private(set) var configurationStatusError: String?
    @Published private(set) var configurationValidation = BearAppConfigurationValidationReport()
    @Published var templateDraft = ""
    @Published private(set) var templateStatusError: String?
    @Published private(set) var templateValidation = BearTemplateValidationReport()
    @Published private(set) var storedSelectedNoteToken: String?
    @Published private(set) var activeBridgeOperation: UrsusBridgeOperation?
    @Published var showsBridgeAccessOverlay = false
    @Published private(set) var bridgeAuthReview: BearBridgeAuthReviewSnapshot?
    @Published private(set) var bridgeAuthStatusError: String?
    @Published private(set) var bridgeAuthActionInProgress = false
    @Published var showsDonationPrompt = false
    @Published private(set) var donationPromptSnapshot = BearDonationPromptSnapshot(
        totalSuccessfulOperationCount: 0,
        nextPromptOperationCount: BearDonationPromptSnapshot.initialEligibilityThreshold,
        permanentSuppressionReason: nil
    )
#if DEBUG
    @Published private(set) var debugDonationStatusError: String?
#endif

    @Published var inboxTagsDraft = ""
    @Published var bridgeHostDraft = BearBridgeConfiguration.defaultHost
    @Published var bridgePortDraft = BearBridgeConfiguration.preferredPort
    @Published var bridgeRequiresOAuthDraft = false
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
    private var suppressConfigurationAutosave = false
    private var lastSavedTemplateDraft = ""
    private let bridgeAuthStore = BearBridgeAuthStore()
    private let runtimeStateStore = BearRuntimeStateStore()
    private let isPreviewMode: Bool
    private var lastPresentedDonationPromptOperationCount: Int?

    init() {
        isPreviewMode = false
        persistCurrentAppBundleLocation()
        refreshAppState()
        reconcilePublicLauncherAutomatically()
        Task { [weak self] in
            await self?.refreshDonationPromptState(presentIfEligible: false)
        }
    }

#if DEBUG
    init(previewState: UrsusBridgeUIPreviewState) {
        isPreviewMode = true
        dashboard = previewState.dashboard
        bridgeAuthReview = previewState.bridgeAuthReview
        showsBridgeAccessOverlay = previewState.showsBridgeAccessOverlay
        applyDraft(from: previewState.dashboard.settings)
    }
#endif

    private func refreshAppState() {
        persistCurrentAppBundleLocation()
        dashboard = BearAppSupport.loadDashboardSnapshot(
            currentAppBundleURL: Bundle.main.bundleURL,
            bridgeSurfaceMarkerProvider: UrsusCLIRuntime.bridgeSurfaceMarker
        )
        applyDraft(from: dashboard.settings)
        loadTemplateDraft()
        hideStoredSelectedNoteToken()
    }

    private func refreshDashboardSnapshot() {
        persistCurrentAppBundleLocation()
        dashboard = BearAppSupport.loadDashboardSnapshot(
            currentAppBundleURL: Bundle.main.bundleURL,
            bridgeSurfaceMarkerProvider: UrsusCLIRuntime.bridgeSurfaceMarker
        )
        applyDraft(from: dashboard.settings)
    }

    func saveSelectedNoteToken() {
        guard !isPreviewMode else {
            return
        }

        do {
            try BearAppSupport.saveSelectedNoteToken(tokenDraft)
            tokenDraft = ""
            hideStoredSelectedNoteToken()
            tokenStatusError = nil
            refreshAppState()
        } catch {
            tokenStatusError = localizedMessage(for: error)
        }
    }

    func removeSelectedNoteToken() {
        guard !isPreviewMode else {
            return
        }

        do {
            try BearAppSupport.removeSelectedNoteToken()
            tokenDraft = ""
            hideStoredSelectedNoteToken()
            tokenStatusError = nil
            refreshAppState()
        } catch {
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
            configurationStatusError = "Fix the highlighted configuration errors before Ursus can save."
            return
        }

        guard !isPreviewMode else {
            configurationStatusError = nil
            return
        }

        configurationStatusError = nil
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
        templateStatusError = nil
    }

    func saveTemplate() {
        guard !isPreviewMode else {
            return
        }

        let validation = validateCurrentTemplateDraft()
        templateValidation = validation

        guard !validation.hasErrors else {
            templateStatusError = nil
            return
        }

        do {
            try BearAppSupport.saveTemplateDraft(templateDraft)
            refreshDashboardSnapshot()
            loadTemplateDraft()
            templateStatusError = nil
        } catch {
            templateStatusError = localizedMessage(for: error)
        }
    }

    func revertTemplateDraft() {
        templateDraft = lastSavedTemplateDraft
        templateValidation = validateCurrentTemplateDraft()
        templateStatusError = nil
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
        bridgeStatusError = nil

        configurationDraftDidChange()
    }

    private func saveConfigurationAutomatically() {
        guard !isPreviewMode else {
            configurationStatusError = nil
            return
        }

        let draft = currentConfigurationDraft()
        let validation = BearAppSupport.validateConfigurationDraft(draft)
        configurationValidation = validation

        guard !validation.hasErrors else {
            configurationStatusError = "Fix the highlighted configuration errors before Ursus can save."
            return
        }

        do {
            try BearAppSupport.saveConfigurationDraft(draft)
            refreshDashboardSnapshot()
            configurationStatusError = nil
        } catch {
            configurationStatusError = localizedMessage(for: error)
        }
    }

    private func flushConfigurationDraftForBridgeOperation() throws {
        guard !isPreviewMode else {
            throw BearError.configuration("Bridge operations are unavailable in previews.")
        }

        configurationAutosaveTask?.cancel()

        let draft = currentConfigurationDraft()
        let validation = BearAppSupport.validateConfigurationDraft(draft)
        configurationValidation = validation

        guard !validation.hasErrors else {
            configurationStatusError = "Fix the highlighted configuration errors before Ursus can save."
            throw BearError.configuration("Fix the highlighted configuration errors before restarting or updating the bridge.")
        }

        try BearAppSupport.saveConfigurationDraft(draft)
        refreshDashboardSnapshot()
        configurationStatusError = nil
    }

    func installPublicLauncher() {
        guard !isPreviewMode else {
            return
        }

        do {
            _ = try BearAppSupport.installPublicLauncher(fromAppBundleURL: Bundle.main.bundleURL)
            cliStatusError = nil
            refreshAppState()
        } catch {
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
        guard !isPreviewMode else {
            return
        }

        let appBundleURL = Bundle.main.bundleURL
        runBridgeOperation(repairing ? .repair : .install) {
            _ = try BearAppSupport.installBridgeLaunchAgent(fromAppBundleURL: appBundleURL)
        }
    }

    func restartBridge() {
        guard !isPreviewMode else {
            return
        }

        let appBundleURL = Bundle.main.bundleURL
        runBridgeOperation(.restart) {
            _ = try BearAppSupport.installBridgeLaunchAgent(fromAppBundleURL: appBundleURL)
        }
    }

    func removeBridge() {
        guard !isPreviewMode else {
            return
        }

        runBridgeOperation(.remove) {
            _ = try BearAppSupport.removeBridgeLaunchAgent()
        }
    }

    func pauseBridge() {
        guard !isPreviewMode else {
            return
        }

        runBridgeOperation(.pause) {
            _ = try BearAppSupport.pauseBridgeLaunchAgent()
        }
    }

    func resumeBridge() {
        guard !isPreviewMode else {
            return
        }

        runBridgeOperation(.resume) {
            _ = try BearAppSupport.resumeBridgeLaunchAgent()
        }
    }

    func openBridgeAccessOverlay() {
        showsBridgeAccessOverlay = true
        Task { [weak self] in
            await self?.refreshBridgeAuthReviewNow()
        }
    }

    func closeBridgeAccessOverlay() {
        showsBridgeAccessOverlay = false
    }

    func revokeBridgeGrant(_ grant: BearBridgeAuthGrantSummary) {
        guard !isPreviewMode else {
            return
        }

        runBridgeAuthAction {
            guard let revokedGrant = try await self.bridgeAuthStore.revokeGrant(id: grant.id) else {
                throw BearError.configuration("The selected remembered grant is no longer available.")
            }

            guard !revokedGrant.isActive else {
                throw BearError.configuration("Failed to revoke the selected remembered grant.")
            }
        }
    }

    func revokeAllBridgeAccess() {
        guard !isPreviewMode else {
            return
        }

        let grantIDs = bridgeAuthGrantSummaries.map(\.id)
        guard !grantIDs.isEmpty else {
            return
        }

        runBridgeAuthAction {
            _ = try await BearAppSupport.revokeRememberedBridgeGrants(
                ids: grantIDs,
                bridgeAuthStore: self.bridgeAuthStore
            )
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
        cliStatusError = nil
    }

    func copyBridgeURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(bridgeEndpointURL, forType: .string)
        bridgeStatusError = nil
    }

    func copySelectedNoteToken() {
        do {
            guard let token = try BearAppSupport.loadResolvedSelectedNoteToken()?.value, !token.isEmpty else {
                tokenStatusError = "Saved token unavailable in the app."
                return
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(token, forType: .string)
            tokenStatusError = nil
        } catch {
            tokenStatusError = localizedMessage(for: error)
        }
    }

    func copyHostSetupSnippet(_ setup: BearHostAppSetupSnapshot) {
        guard let snippet = setup.snippet else {
            hostSetupStatusError = "No local snippet is available for \(setup.appName)."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet, forType: .string)
        hostSetupStatusError = nil
    }

    func copyHostConfigPath(_ setup: BearHostAppSetupSnapshot) {
        guard let configPath = setup.configPath else {
            hostSetupStatusError = "No local config path is tracked for \(setup.appName)."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(configPath, forType: .string)
        hostSetupStatusError = nil
    }

    func applicationDidBecomeActive() {
        guard !isPreviewMode else {
            return
        }

        Task { [weak self] in
            await self?.refreshDonationPromptState(presentIfEligible: true)
        }
    }

    func presentDonationPrompt() {
        guard donationPromptSnapshot.shouldShowSupportAffordance else {
            return
        }

        showsDonationPrompt = true
    }

    func handleDonationNotNow() {
        showsDonationPrompt = false

        guard !isPreviewMode else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                _ = try await runtimeStateStore.recordDonationPromptAction(.notNow)
            } catch {
                BearDebugLog.append("donation.not-now failed error=\(String(describing: error))")
            }

            await refreshDonationPromptState(presentIfEligible: false)
        }
    }

    func handleDonationDontAskAgain() {
        showsDonationPrompt = false

        guard !isPreviewMode else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                _ = try await runtimeStateStore.recordDonationPromptAction(.dontAskAgain)
            } catch {
                BearDebugLog.append("donation.dont-ask-again failed error=\(String(describing: error))")
            }

            await refreshDonationPromptState(presentIfEligible: false)
        }
    }

    func handleDonationAction() {
        showsDonationPrompt = false

        let supportURL = donationSupportURL

        guard !isPreviewMode else {
            if let supportURL {
                NSWorkspace.shared.open(supportURL)
            }
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                _ = try await runtimeStateStore.recordDonationPromptAction(.donated)
            } catch {
                BearDebugLog.append("donation.donated failed error=\(String(describing: error))")
            }

            if let supportURL {
                await MainActor.run {
                    NSWorkspace.shared.open(supportURL)
                }
            }

            await refreshDonationPromptState(presentIfEligible: false)
        }
    }

#if DEBUG
    func debugMarkDonationPromptEligible() {
        guard !isPreviewMode else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                _ = try await runtimeStateStore.debugMarkDonationPromptEligible()
                debugDonationStatusError = nil
            } catch {
                debugDonationStatusError = localizedMessage(for: error)
            }

            await refreshDonationPromptState(presentIfEligible: false)
        }
    }

    func debugResetDonationPromptState() {
        guard !isPreviewMode else {
            return
        }

        showsDonationPrompt = false
        lastPresentedDonationPromptOperationCount = nil

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                _ = try await runtimeStateStore.debugResetDonationPromptState()
                debugDonationStatusError = nil
            } catch {
                debugDonationStatusError = localizedMessage(for: error)
            }

            await refreshDonationPromptState(presentIfEligible: false)
        }
    }
#endif

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

    var bridgeAuthGrantSummaries: [BearBridgeAuthGrantSummary] {
        bridgeAuthReview?.activeGrants ?? []
    }

    var bridgeRememberedClientCount: Int {
        bridgeAuthReview?.activeGrants.count ?? dashboard.settings?.bridge.auth.activeGrantCount ?? 0
    }

    var bridgeAuthHasVisibleState: Bool {
        bridgeAuthReview?.hasStoredAuthState == true
    }

    var setupHostSetups: [BearHostAppSetupSnapshot] {
        dashboard.settings?.hostAppSetups.filter(\.presentInSetup) ?? []
    }

    var inboxTagValues: [String] {
        parsedInboxTags
    }

    var showsSupportAffordance: Bool {
        donationPromptSnapshot.shouldShowSupportAffordance
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
            inboxTags: parsedInboxTags,
            bridgeHost: bridgeHostDraft,
            bridgePort: bridgePortDraft,
            bridgeRequiresOAuth: bridgeRequiresOAuthDraft,
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
        inboxTagsDraft = settings.inboxTags.joined(separator: ", ")
        bridgeHostDraft = settings.bridge.host
        bridgePortDraft = settings.bridge.port
        bridgeRequiresOAuthDraft = settings.bridge.requiresOAuth
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
            templateStatusError = nil
        } catch {
            templateDraft = ""
            lastSavedTemplateDraft = ""
            templateValidation = BearTemplateValidationReport()
            templateStatusError = localizedMessage(for: error)
        }
    }

    private func runBridgeOperation(
        _ operation: UrsusBridgeOperation,
        work: @escaping @Sendable () throws -> Void
    ) {
        guard activeBridgeOperation == nil else {
            return
        }

        do {
            try flushConfigurationDraftForBridgeOperation()
        } catch {
            bridgeStatusError = localizedMessage(for: error)
            return
        }

        activeBridgeOperation = operation
        bridgeStatusError = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<Void, Error>
            do {
                try work()
                result = .success(())
            } catch {
                result = .failure(error)
            }

            await MainActor.run { [weak self, result] in
                self?.completeBridgeOperation(with: result)
            }
        }
    }

    private func completeBridgeOperation(with result: Result<Void, Error>) {
        activeBridgeOperation = nil
        refreshAppState()

        switch result {
        case .success:
            bridgeStatusError = nil
        case .failure(let error):
            bridgeStatusError = localizedMessage(for: error)
        }
    }

    private func refreshBridgeAuthReviewNow() async {
        let shouldLoadReview = await MainActor.run {
            if let settings = dashboard.settings {
                return settings.bridge.requiresOAuth || settings.bridge.auth.hasStoredAuthState || showsBridgeAccessOverlay || bridgeAuthHasVisibleState
            }

            return showsBridgeAccessOverlay || bridgeAuthHasVisibleState
        }

        guard shouldLoadReview else {
            await MainActor.run {
                bridgeAuthReview = nil
            }
            return
        }

        let snapshot = try? await bridgeAuthStore.reviewSnapshot(prepareIfMissing: false)
        await MainActor.run {
            bridgeAuthReview = snapshot
        }
    }

    private func runBridgeAuthAction(
        work: @escaping @MainActor @Sendable () async throws -> Void
    ) {
        guard !bridgeAuthActionInProgress else {
            return
        }

        bridgeAuthActionInProgress = true
        bridgeAuthStatusError = nil

        Task { [weak self] in
            guard let self else {
                return
            }

            let result: Result<Void, Error>
            do {
                try await work()
                result = .success(())
            } catch {
                result = .failure(error)
            }

            bridgeAuthActionInProgress = false
            await refreshBridgeAuthReviewNow()
            refreshDashboardSnapshot()

            switch result {
            case .success:
                bridgeAuthStatusError = nil
            case .failure(let error):
                bridgeAuthStatusError = localizedMessage(for: error)
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

    private func persistCurrentAppBundleLocation() {
        try? UrsusAppLocator.recordCurrentAppBundleURL(Bundle.main.bundleURL)
    }

    private func reconcilePublicLauncherAutomatically() {
        do {
            let result = try BearAppSupport.reconcilePublicLauncherIfNeeded(
                fromAppBundleURL: Bundle.main.bundleURL
            )

            guard result.changed else {
                return
            }

            refreshAppState()
            cliStatusError = nil
        } catch {
            cliStatusError = localizedMessage(for: error)
        }
    }

    private func refreshDonationPromptState(presentIfEligible: Bool) async {
        guard !isPreviewMode else {
            return
        }

        let snapshot: BearDonationPromptSnapshot
        do {
            snapshot = try await runtimeStateStore.loadDonationPromptSnapshot()
        } catch {
            BearDebugLog.append("donation.snapshot failed error=\(String(describing: error))")
            return
        }

        donationPromptSnapshot = snapshot

        guard presentIfEligible, snapshot.isPromptEligible else {
            if !snapshot.isPromptEligible {
                showsDonationPrompt = false
            }
            return
        }

        guard lastPresentedDonationPromptOperationCount != snapshot.totalSuccessfulOperationCount else {
            return
        }

        lastPresentedDonationPromptOperationCount = snapshot.totalSuccessfulOperationCount
        showsDonationPrompt = true
    }

    private var donationSupportURL: URL? {
        guard
            let rawValue = Bundle.main.object(forInfoDictionaryKey: "UrsusSupportURL") as? String,
            let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }

        return url
    }
}
