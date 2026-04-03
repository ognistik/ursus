import BearApplication
import BearCore
import SwiftUI

private enum UrsusDashboardSection: Hashable {
    case setup
    case preferences
    case advanced
}

struct UrsusDashboardView: View {
    @ObservedObject var model: UrsusAppModel
    @State private var selectedSection: UrsusDashboardSection = .setup

    var body: some View {
        TabView(selection: $selectedSection) {
            UrsusSetupView(model: model, selectedSection: $selectedSection)
                .tabItem {
                    Label("Setup", systemImage: "sparkles.rectangle.stack")
                }
                .tag(UrsusDashboardSection.setup)

            UrsusPreferencesView(model: model, showsStandaloneHeader: false)
                .tabItem {
                    Label("Preferences", systemImage: "slider.horizontal.3")
                }
                .tag(UrsusDashboardSection.preferences)

            UrsusAdvancedView(model: model)
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
                .tag(UrsusDashboardSection.advanced)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reload", systemImage: "arrow.clockwise") {
                    model.reload()
                }
            }
        }
    }
}

struct UrsusSettingsView: View {
    @ObservedObject var model: UrsusAppModel

    var body: some View {
        UrsusPreferencesView(model: model, showsStandaloneHeader: true)
    }
}

private struct UrsusSetupView: View {
    @ObservedObject var model: UrsusAppModel
    @Binding var selectedSection: UrsusDashboardSection

    var body: some View {
        UrsusScrollSurface {
            if let settings = model.dashboard.settings {
                VStack(alignment: .leading, spacing: 24) {
                    heroPanel(settings)
                    Divider()
                    defaultsPanel(settings)
                    Divider()
                    tokenPanel(settings)
                    if !model.setupHostSetups.isEmpty {
                        Divider()
                        connectAppsPanel(settings)
                    }
                    Divider()
                    bridgePanel(settings)
                }
            } else {
                unavailablePanel(
                    title: "Setup is unavailable",
                    detail: model.dashboard.settingsError ?? "Ursus could not load its current settings."
                )
            }
        }
    }

    private func heroPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ursus")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.7)

                Text("Local MCP and utilities for Bear")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(setupSteps(for: settings)) { step in
                    UrsusChecklistRow(step: step)
                }
            }
            .padding(16)
            .background(UrsusPanelBackground(style: .subtle))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func defaultsPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(
            title: "Defaults",
            headerAccessory: {
                Button("Edit") {
                    selectedSection = .preferences
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                UrsusInfoRow(label: "Template management", value: settings.templateManagementEnabled ? "On" : "Off", compact: true)
                Divider()
                UrsusInfoRow(
                    label: "Inbox tags",
                    value: settings.inboxTags.isEmpty ? "None" : settings.inboxTags.joined(separator: ", "),
                    compact: true
                )
                Divider()
                UrsusInfoRow(
                    label: "New notes",
                    value: settings.createOpensNoteByDefault ? "Open by default" : "Stay in the background",
                    compact: true
                )
                Divider()
                UrsusInfoRow(
                    label: "Default insert",
                    value: friendlyInsertPosition(settings.defaultInsertPosition),
                    compact: true
                )
            }
        }
    }

    private func tokenPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(title: "Bear token") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    UrsusStatusBadge(
                        title: settings.selectedNoteTokenConfigured ? "Saved" : "Missing",
                        status: settings.selectedNoteTokenConfigured ? .configured : .notConfigured
                    )

                    if settings.selectedNoteTokenConfigured {
                        Text("Stored in Keychain")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text("Optional. Needed only for selected-note flows.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if settings.selectedNoteTokenConfigured {
                    if let displayedToken = model.revealsStoredToken ? model.storedSelectedNoteToken : model.maskedStoredSelectedNoteToken {
                        HStack(spacing: 10) {
                            Text(displayedToken)
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            Spacer(minLength: 12)

                            Button(model.revealsStoredToken ? "Hide" : "Show") {
                                model.loadStoredSelectedNoteToken()
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    } else {
                        HStack(spacing: 10) {
                            Text("Saved token unavailable in the app.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Button("Try Again") {
                                model.loadStoredSelectedNoteToken()
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                }

                SecureField(
                    settings.selectedNoteTokenConfigured
                        ? "Paste a new Bear API token"
                        : "Paste Bear API token",
                    text: $model.tokenDraft
                )
                .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button(settings.selectedNoteTokenConfigured ? "Replace" : "Save Token") {
                        model.saveSelectedNoteToken()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Remove", role: .destructive) {
                        model.removeSelectedNoteToken()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!settings.selectedNoteTokenConfigured)
                }

                UrsusMessageStack(
                    success: model.tokenStatusMessage,
                    warning: nil,
                    error: model.tokenStatusError
                )
            }
        }
    }

    private func connectAppsPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(title: "Connect apps") {
            VStack(alignment: .leading, spacing: 16) {
                if let title = launcherPrimaryActionTitle(for: settings) {
                    UrsusInlineNotice(
                        title: "Local launcher needs attention",
                        detail: "Repair the launcher before you copy setup into a local host app.",
                        tone: .warning
                    ) {
                        Button(title) {
                            model.installPublicLauncher()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.currentBundledCLIPath == nil)
                    }
                }

                ForEach(Array(model.setupHostSetups.enumerated()), id: \.element.id) { index, setup in
                    UrsusHostSetupRow(model: model, setup: setup)

                    if index < model.setupHostSetups.count - 1 {
                        Divider()
                    }
                }

                UrsusMessageStack(
                    success: model.hostSetupStatusMessage,
                    warning: nil,
                    error: model.hostSetupStatusError
                )
            }
        }
    }

    private func bridgePanel(_ settings: BearAppSettingsSnapshot) -> some View {
        let bridge = settings.bridge

        return UrsusPanel(title: "Remote MCP bridge") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(bridgeHeadline(for: bridge))
                        .font(.headline)
                    UrsusStatusBadge(title: compactStatusTitle(for: bridge.status), status: bridge.status)
                }

                Text(bridgeSummary(for: settings))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let recoveryAction = bridgeRecoveryAction(for: settings) {
                    UrsusInlineNotice(
                        title: "Next step",
                        detail: bridgeTroubleshootingText(for: settings),
                        tone: recoveryAction.noticeTone
                    ) {
                        Button(recoveryAction.title) {
                            performRecoveryAction(recoveryAction, settings: settings)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.currentBundledCLIPath == nil || model.isBridgeOperationInProgress)
                    }
                }

                UrsusInfoRow(label: "MCP URL", value: bridge.endpointURL, compact: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Port")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)

                    UrsusNumericFieldRow(
                        label: "Saved bridge port",
                        value: bridgePortBinding,
                        range: 1024...65_535,
                        disabled: model.isBridgeOperationInProgress,
                        fieldWidth: 92
                    )

                    configurationValidationMessages(for: .bridgePort)
                }

                HStack(spacing: 10) {
                    if bridgeRecoveryAction(for: settings) == nil,
                       let title = bridgePrimaryActionTitle(for: bridge) {
                        Button(title) {
                            model.installBridge(
                                repairing: bridge.status == .invalid || bridge.status == .failed
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.currentBundledCLIPath == nil || model.isBridgeOperationInProgress)
                    }

                    if bridge.installed {
                        if bridge.loaded {
                            Button("Pause") {
                                model.pauseBridge()
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isBridgeOperationInProgress)
                        } else {
                            Button("Resume") {
                                model.resumeBridge()
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isBridgeOperationInProgress)
                        }

                        Button("Remove", role: .destructive) {
                            model.removeBridge()
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isBridgeOperationInProgress)
                    }

                    Button("Copy URL") {
                        model.copyBridgeURL()
                    }
                    .buttonStyle(.bordered)
                }

                if let progressMessage = model.bridgeOperationProgressMessage {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(progressMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                UrsusMessageStack(
                    success: model.bridgeStatusMessage,
                    warning: nil,
                    error: model.bridgeStatusError
                )
            }
        }
    }

    @ViewBuilder
    private func configurationValidationMessages(for field: BearAppConfigurationField) -> some View {
        let issues = model.configurationIssues(for: field)
        if !issues.isEmpty {
            UrsusIssueList(issues: issues)
        }
    }

    private var bridgePortBinding: Binding<Int> {
        Binding(
            get: { model.bridgePortDraft },
            set: { model.updateBridgePortDraft($0) }
        )
    }

    private func setupSteps(for settings: BearAppSettingsSnapshot) -> [UrsusSetupStep] {
        let tokenStep = UrsusSetupStep(
            title: "Save token",
            status: settings.selectedNoteTokenConfigured ? .configured : .notConfigured
        )

        let hostConfigured = model.setupHostSetups.contains { $0.status == .ok }
        let hostNeedsAttention = model.setupHostSetups.contains { $0.status == .invalid }
        let bridgeReady = settings.bridge.loaded
        let connectionStatus: BearDoctorCheckStatus

        if bridgeReady || hostConfigured {
            connectionStatus = .configured
        } else if settings.launcherStatus == .missing || settings.launcherStatus == .invalid || settings.bridge.status == .invalid || settings.bridge.status == .failed || hostNeedsAttention {
            connectionStatus = .invalid
        } else {
            connectionStatus = .notConfigured
        }

        return [
            UrsusSetupStep(
                title: "Configure defaults",
                status: .configured
            ),
            tokenStep,
            UrsusSetupStep(
                title: "Connect an app or bridge",
                status: connectionStatus
            ),
        ]
    }

    private func bridgeHeadline(for bridge: BearAppBridgeSnapshot) -> String {
        if bridge.loaded {
            return "Bridge is running"
        }

        if bridge.installed {
            return bridge.status == .failed || bridge.status == .invalid ? "Bridge needs attention" : "Bridge is installed"
        }

        return "Bridge is off"
    }

    private func bridgeSummary(for settings: BearAppSettingsSnapshot) -> String {
        let bridge = settings.bridge
        switch bridge.status {
        case .ok, .configured:
            return "Use this only for apps that need an MCP URL."
        case .missing:
            return "Optional. Leave this off unless an app needs an MCP URL."
        case .notConfigured:
            return "Installed, but not serving requests."
        case .invalid, .failed:
            return "Needs repair before a host can use it."
        }
    }

    private func bridgeTroubleshootingText(for settings: BearAppSettingsSnapshot) -> String {
        switch bridgeRecoveryAction(for: settings) {
        case .installLauncher:
            return "Install the launcher first, then try again."
        case .repairLauncher:
            return "Repair the launcher first. The bridge depends on it."
        case .installBridge:
            return "Install the bridge to serve the saved MCP URL."
        case .repairBridge:
            return "Repair the bridge and refresh the local endpoint."
        case .none:
            return settings.bridge.statusDetail
        }
    }

    private func bridgeRecoveryAction(for settings: BearAppSettingsSnapshot) -> UrsusRecoveryAction? {
        switch settings.bridge.status {
        case .missing:
            return nil
        case .invalid, .failed:
            if settings.launcherStatus == .missing {
                return .installLauncher
            }

            if settings.launcherStatus == .invalid {
                return .repairLauncher
            }

            return .repairBridge
        case .ok, .configured, .notConfigured:
            return nil
        }
    }

    private func performRecoveryAction(_ action: UrsusRecoveryAction, settings: BearAppSettingsSnapshot) {
        switch action {
        case .installLauncher, .repairLauncher:
            model.installPublicLauncher()
        case .installBridge:
            model.installBridge(repairing: false)
        case .repairBridge:
            model.installBridge(repairing: settings.bridge.status == .invalid || settings.bridge.status == .failed)
        }
    }
}

private struct UrsusPreferencesView: View {
    @ObservedObject var model: UrsusAppModel
    let showsStandaloneHeader: Bool

    var body: some View {
        UrsusScrollSurface {
            if let settings = model.dashboard.settings {
                VStack(alignment: .leading, spacing: 28) {
                    if showsStandaloneHeader {
                        UrsusScreenHeader(
                            title: "Preferences"
                        )
                    }

                    behaviorPanel
                    Divider()
                    inboxTagsPanel
                    Divider()
                    templatePanel(settings)
                    Divider()
                    limitsPanel

                    UrsusMessageStack(
                        success: model.configurationValidation.warnings.isEmpty ? model.configurationStatusMessage : nil,
                        warning: model.configurationValidation.warnings.isEmpty ? nil : model.configurationStatusMessage,
                        error: model.configurationStatusError
                    )
                }
            } else {
                unavailablePanel(
                    title: "Preferences are unavailable",
                    detail: model.dashboard.settingsError ?? "Ursus could not load its current settings."
                )
            }
        }
    }

    private var behaviorPanel: some View {
        UrsusPanel(title: "Note behavior") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Create opens note by default", isOn: autosavingBinding(\.createOpensNoteByDefaultDraft))
                    Divider()
                    Toggle("Open uses new window by default", isOn: autosavingBinding(\.openUsesNewWindowByDefaultDraft))
                    Divider()
                    Toggle("Create adds inbox tags by default", isOn: autosavingBinding(\.createAddsInboxTagsByDefaultDraft))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Default insert position")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)

                    Picker("Default insert position", selection: autosavingBinding(\.defaultInsertPositionDraft)) {
                        Text("Top").tag(BearConfiguration.InsertDefault.top)
                        Text("Bottom").tag(BearConfiguration.InsertDefault.bottom)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags merge mode")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)

                    Picker("Tags merge mode", selection: autosavingBinding(\.tagsMergeModeDraft)) {
                        Text("Append").tag(BearConfiguration.TagsMergeMode.append)
                        Text("Replace").tag(BearConfiguration.TagsMergeMode.replace)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var inboxTagsPanel: some View {
        UrsusPanel(title: "Inbox tags") {
            VStack(alignment: .leading, spacing: 12) {
                UrsusTagEditor(
                    tags: model.inboxTagValues,
                    onAdd: model.addInboxTags(from:),
                    onRemove: model.removeInboxTag(_:)
                )

                configurationValidationMessages(for: .inboxTags)
            }
        }
    }

    private func templatePanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(title: "Template") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Enable template management", isOn: autosavingBinding(\.templateManagementEnabledDraft))

                if model.templateManagementEnabledDraft {
                    Text("Required slots: `{{content}}` and `{{tags}}`.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    TextEditor(text: Binding(
                        get: { model.templateDraft },
                        set: { newValue in
                            model.templateDraft = newValue
                            model.templateDraftDidChange()
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
                    .padding(12)
                    .background(UrsusPanelBackground(style: .subtle))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                    templateValidationMessages

                    HStack(spacing: 10) {
                        Button("Save Template") {
                            model.saveTemplate()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.templateValidation.hasErrors || !model.templateHasUnsavedChanges)

                        Button("Revert Changes") {
                            model.revertTemplateDraft()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.templateHasUnsavedChanges)
                    }

                    if model.templateHasUnsavedChanges && model.templateStatusMessage == nil && model.templateStatusError == nil {
                        Text("Unsaved changes stay in the app until you save.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    UrsusMessageStack(
                        success: model.templateValidation.warnings.isEmpty ? model.templateStatusMessage : nil,
                        warning: model.templateValidation.warnings.isEmpty ? nil : model.templateStatusMessage,
                        error: model.templateStatusError
                    )
                }
            }
        }
    }

    private var limitsPanel: some View {
        UrsusPanel(title: "Read and backup limits") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    UrsusNumericFieldRow(
                        label: "Default discovery limit",
                        value: autosavingBinding(\.defaultDiscoveryLimitDraft),
                        range: 1...500
                    )
                    configurationValidationMessages(for: .defaultDiscoveryLimit)
                }

                VStack(alignment: .leading, spacing: 6) {
                    UrsusNumericFieldRow(
                        label: "Default snippet length",
                        value: autosavingBinding(\.defaultSnippetLengthDraft),
                        range: 1...2_000
                    )
                    configurationValidationMessages(for: .defaultSnippetLength)
                }

                VStack(alignment: .leading, spacing: 6) {
                    UrsusNumericFieldRow(
                        label: "Backup retention days",
                        value: autosavingBinding(\.backupRetentionDaysDraft),
                        range: 0...365
                    )
                    configurationValidationMessages(for: .backupRetentionDays)
                }
            }
        }
    }

    private func autosavingBinding<Value>(_ keyPath: ReferenceWritableKeyPath<UrsusAppModel, Value>) -> Binding<Value> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { newValue in
                model[keyPath: keyPath] = newValue
                model.configurationDraftDidChange()
            }
        )
    }

    @ViewBuilder
    private var templateValidationMessages: some View {
        if !model.templateValidation.issues.isEmpty {
            UrsusIssueList(issues: model.templateValidation.issues)
        }
    }

    @ViewBuilder
    private func configurationValidationMessages(for field: BearAppConfigurationField) -> some View {
        let issues = model.configurationIssues(for: field)
        if !issues.isEmpty {
            UrsusIssueList(issues: issues)
        }
    }
}

private struct UrsusAdvancedView: View {
    @ObservedObject var model: UrsusAppModel

    var body: some View {
        UrsusScrollSurface {
            if let settings = model.dashboard.settings {
                VStack(alignment: .leading, spacing: 28) {
                    UrsusScreenHeader(
                        title: "Advanced",
                        subtitle: "Repair actions, file reveals, and tool controls stay here so the main setup path can stay quiet."
                    )
                    launcherPanel(settings)
                    Divider()
                    filesPanel(settings)
                    Divider()
                    toolAvailabilityPanel(settings)
                }
            } else {
                unavailablePanel(
                    title: "Advanced settings are unavailable",
                    detail: model.dashboard.settingsError ?? "Ursus could not load its current settings."
                )
            }
        }
    }

    private func launcherPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(
            title: "Repair and launcher",
            subtitle: "Use this when a local stdio setup needs repair."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Local launcher")
                        .font(.title3.weight(.semibold))
                        .tracking(-0.2)
                    UrsusStatusBadge(title: compactStatusTitle(for: settings.launcherStatus), status: settings.launcherStatus)
                }

                Text(settings.launcherStatusDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                UrsusInfoRow(label: "Launcher path", value: settings.launcherPath, compact: true)

                HStack(spacing: 10) {
                    if let actionTitle = launcherPrimaryActionTitle(for: settings) {
                        Button(actionTitle) {
                            model.installPublicLauncher()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.currentBundledCLIPath == nil)
                    }

                    Button("Copy Path") {
                        model.copyLauncherPath()
                    }
                    .buttonStyle(.bordered)
                }

                UrsusMessageStack(
                    success: model.cliStatusMessage,
                    warning: nil,
                    error: model.cliStatusError
                )
            }
        }
    }

    private func filesPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(
            title: "Files and logs",
            subtitle: "Reveal support files only when you need to inspect or repair something directly."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button("Reveal Configuration") {
                        model.reveal(path: settings.configFilePath)
                    }
                    .buttonStyle(.bordered)

                    Button("Reveal Template") {
                        model.reveal(path: settings.templatePath)
                    }
                    .buttonStyle(.bordered)

                    Button("Reveal Debug Log") {
                        model.reveal(path: settings.debugLogPath)
                    }
                    .buttonStyle(.bordered)
                }

                if settings.bridge.installed || settings.bridge.status == .invalid || settings.bridge.status == .failed {
                    HStack(spacing: 10) {
                        Button("Reveal LaunchAgent") {
                            model.reveal(path: settings.bridge.plistPath)
                        }
                        .buttonStyle(.bordered)

                        Button("Reveal Bridge Stdout") {
                            model.reveal(path: settings.bridge.standardOutputLogPath)
                        }
                        .buttonStyle(.bordered)

                        Button("Reveal Bridge Stderr") {
                            model.reveal(path: settings.bridge.standardErrorLogPath)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func toolAvailabilityPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(
            title: "Tool availability",
            subtitle: "Keep host-control toggles available, but out of the beginner flow."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(BearToolCategory.allCases, id: \.self) { category in
                    let tools = settings.toolToggles.filter { $0.category == category }

                    if !tools.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.title)
                                .font(.title3.weight(.semibold))
                                .tracking(-0.2)

                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                                    Toggle(isOn: Binding(
                                        get: { model.isToolEnabledInDraft(tool.tool) },
                                        set: { model.setToolEnabledInDraft(tool.tool, enabled: $0) }
                                    )) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(tool.title)
                                            Text(tool.summary)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if index < tools.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }

                UrsusMessageStack(
                    success: model.configurationValidation.warnings.isEmpty ? model.configurationStatusMessage : nil,
                    warning: model.configurationValidation.warnings.isEmpty ? nil : model.configurationStatusMessage,
                    error: model.configurationStatusError
                )
            }
        }
    }
}

private struct UrsusHostSetupRow: View {
    @ObservedObject var model: UrsusAppModel
    let setup: BearHostAppSetupSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(setup.appName)
                    .font(.headline)
                UrsusStatusBadge(title: compactStatusTitle(for: setup.status), status: setup.status)
            }

            Text(setup.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if setup.snippet != nil {
                    Button("Copy Setup") {
                        model.copyHostSetupSnippet(setup)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if let configPath = setup.configPath {
                    Button("Reveal Config") {
                        model.reveal(path: configPath)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
        }
    }
}

private struct UrsusChecklistRow: View {
    let step: UrsusSetupStep

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusSymbol(for: step.status))
                .foregroundStyle(statusPalette(for: step.status).foreground)
                .font(.system(size: 14, weight: .semibold))

            Text(step.title)
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 12)

            UrsusStatusBadge(title: compactStatusTitle(for: step.status), status: step.status)
        }
    }
}

private struct UrsusScrollSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private enum UrsusSectionSurface {
    case plain
    case subtle
    case prominent
}

private struct UrsusPanel<Content: View>: View {
    let title: String
    let subtitle: String?
    let surface: UrsusSectionSurface
    let headerAccessory: AnyView?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        surface: UrsusSectionSurface = .plain,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.surface = surface
        self.headerAccessory = nil
        self.content = content()
    }

    init<HeaderAccessory: View>(
        title: String,
        subtitle: String? = nil,
        surface: UrsusSectionSurface = .plain,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.surface = surface
        self.headerAccessory = AnyView(headerAccessory())
        self.content = content()
    }

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(surface == .prominent ? .title2.weight(.semibold) : .title3.weight(.semibold))
                        .tracking(surface == .prominent ? -0.4 : -0.2)

                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let headerAccessory {
                    Spacer(minLength: 12)
                    headerAccessory
                }
            }

            content
        }

        switch surface {
        case .plain:
            stack
        case .subtle:
            stack
                .padding(20)
                .background(UrsusPanelBackground(style: .subtle))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        case .prominent:
            stack
                .padding(24)
                .background(UrsusPanelBackground(style: .prominent))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

private struct UrsusPanelBackground: ShapeStyle {
    let style: UrsusSectionSurface

    init(style: UrsusSectionSurface = .subtle) {
        self.style = style
    }

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        switch style {
        case .plain:
            Color.clear
        case .subtle:
            Color.secondary.opacity(environment.colorScheme == .dark ? 0.08 : 0.045)
        case .prominent:
            Color.secondary.opacity(environment.colorScheme == .dark ? 0.13 : 0.07)
        }
    }
}

private struct UrsusScreenHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.semibold))
                .tracking(-0.4)

            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct UrsusInfoRow: View {
    let label: String
    let value: String
    var compact = false

    var body: some View {
        if compact {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Text(value)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private let ursusIntegerFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .none
    formatter.allowsFloats = false
    return formatter
}()

private struct UrsusNumericFieldRow: View {
    let label: String
    let value: Binding<Int>
    let range: ClosedRange<Int>
    var disabled = false
    var fieldWidth: CGFloat = 80

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
            Spacer()
            TextField(label, value: value, formatter: ursusIntegerFormatter)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: fieldWidth)
                .disabled(disabled)

            Stepper("", value: value, in: range)
                .labelsHidden()
                .disabled(disabled)
        }
    }
}

private struct UrsusStatusBadge: View {
    let title: String
    let status: BearDoctorCheckStatus

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusPalette(for: status).background)
            .foregroundStyle(statusPalette(for: status).foreground)
            .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
    }
}

private struct UrsusIssueList<Issue: Identifiable>: View where Issue: UrsusIssuePresentable {
    let issues: [Issue]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: issue.ursusSeverity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.ursusSeverity == .error ? statusPalette(for: .failed).foreground : statusPalette(for: .notConfigured).foreground)
                        .padding(.top, 1)

                    Text(issue.ursusMessage)
                        .font(.caption)
                        .foregroundStyle(issue.ursusSeverity == .error ? statusPalette(for: .failed).foreground : statusPalette(for: .notConfigured).foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct UrsusMessageStack: View {
    let success: String?
    let warning: String?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let success {
                UrsusFeedbackRow(symbol: "checkmark.circle.fill", message: success, tone: .neutral)
            }

            if let warning, warning != success {
                UrsusFeedbackRow(symbol: "exclamationmark.triangle.fill", message: warning, tone: .warning)
            }

            if let error {
                UrsusFeedbackRow(symbol: "xmark.octagon.fill", message: error, tone: .error)
            }
        }
    }
}

private enum UrsusFeedbackTone {
    case neutral
    case warning
    case error
}

private struct UrsusFeedbackRow: View {
    let symbol: String
    let message: String
    let tone: UrsusFeedbackTone

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(feedbackColor)
                .padding(.top, 1)

            Text(message)
                .font(.callout)
                .foregroundStyle(tone == .neutral ? .secondary : feedbackColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var feedbackColor: Color {
        switch tone {
        case .neutral:
            return statusPalette(for: .configured).foreground
        case .warning:
            return statusPalette(for: .notConfigured).foreground
        case .error:
            return statusPalette(for: .failed).foreground
        }
    }
}

private enum UrsusNoticeTone {
    case neutral
    case warning
    case error
}

private struct UrsusInlineNotice<Actions: View>: View {
    let title: String
    let detail: String
    let tone: UrsusNoticeTone
    @ViewBuilder let actions: Actions

    init(
        title: String,
        detail: String,
        tone: UrsusNoticeTone = .neutral,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.detail = detail
        self.tone = tone
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                UrsusStatusBadge(title: noticeBadgeTitle, status: noticeStatus)
            }

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            actions
        }
        .padding(16)
        .background(UrsusPanelBackground(style: .subtle))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var noticeStatus: BearDoctorCheckStatus {
        switch tone {
        case .neutral:
            return .configured
        case .warning:
            return .notConfigured
        case .error:
            return .failed
        }
    }

    private var noticeBadgeTitle: String {
        switch tone {
        case .neutral:
            return "Next step"
        case .warning:
            return "Attention"
        case .error:
            return "Repair"
        }
    }
}

private struct UrsusTagEditor: View {
    let tags: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(tags.isEmpty ? "No inbox tags yet." : "\(tags.count) tag\(tags.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                if !tags.isEmpty {
                    Text("Click a tag to remove it.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if tags.isEmpty {
                Text("New notes stay untagged until you add one here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            onRemove(tag)
                        } label: {
                            HStack(spacing: 8) {
                                Text(tag)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(UrsusPanelBackground(style: .subtle))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Add a tag or paste a comma-separated list", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(addDraft)

                HStack(spacing: 10) {
                    Button("Add Tag") {
                        addDraft()
                    }
                    .buttonStyle(.bordered)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text("Duplicates and extra spacing are cleaned up automatically.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func addDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        onAdd(trimmed)
        draft = ""
    }
}

private struct UrsusSetupStep: Identifiable {
    let id = UUID()
    let title: String
    let status: BearDoctorCheckStatus
}

private enum UrsusRecoveryAction {
    case installLauncher
    case repairLauncher
    case installBridge
    case repairBridge

    var title: String {
        switch self {
        case .installLauncher:
            return "Install Launcher"
        case .repairLauncher:
            return "Repair Launcher"
        case .installBridge:
            return "Install Bridge"
        case .repairBridge:
            return "Repair Bridge"
        }
    }

    var noticeTone: UrsusNoticeTone {
        switch self {
        case .installBridge:
            return .neutral
        case .installLauncher, .repairLauncher:
            return .warning
        case .repairBridge:
            return .error
        }
    }
}

private protocol UrsusIssuePresentable {
    var ursusSeverity: BearAppConfigurationIssueSeverity { get }
    var ursusMessage: String { get }
}

extension BearAppConfigurationIssue: UrsusIssuePresentable {
    fileprivate var ursusSeverity: BearAppConfigurationIssueSeverity { severity }
    fileprivate var ursusMessage: String { message }
}

extension BearTemplateValidationIssue: UrsusIssuePresentable {
    fileprivate var ursusSeverity: BearAppConfigurationIssueSeverity {
        severity == .error ? .error : .warning
    }

    fileprivate var ursusMessage: String { message }
}

@ViewBuilder
private func unavailablePanel(title: String, detail: String) -> some View {
    UrsusPanel(title: title, subtitle: detail, surface: .subtle) {
        EmptyView()
    }
}

private func launcherPrimaryActionTitle(for settings: BearAppSettingsSnapshot) -> String? {
    switch settings.launcherStatus {
    case .missing:
        return "Install Launcher"
    case .invalid:
        return "Repair Launcher"
    case .ok, .configured, .notConfigured, .failed:
        return nil
    }
}

private func bridgePrimaryActionTitle(for bridge: BearAppBridgeSnapshot) -> String? {
    switch bridge.status {
    case .missing:
        return "Install Bridge"
    case .invalid, .failed:
        return "Repair Bridge"
    case .ok, .configured, .notConfigured:
        return bridge.installed ? nil : "Install Bridge"
    }
}

private func friendlyInsertPosition(_ rawValue: String) -> String {
    switch rawValue {
    case BearConfiguration.InsertDefault.top.rawValue:
        return "Top"
    default:
        return "Bottom"
    }
}

private func compactStatusTitle(for status: BearDoctorCheckStatus) -> String {
    switch status {
    case .ok, .configured:
        return "Ready"
    case .missing, .notConfigured:
        return "Set up"
    case .invalid, .failed:
        return "Needs attention"
    }
}

private func statusSymbol(for status: BearDoctorCheckStatus) -> String {
    switch status {
    case .ok, .configured:
        return "checkmark.circle.fill"
    case .missing, .notConfigured:
        return "exclamationmark.triangle.fill"
    case .invalid, .failed:
        return "xmark.octagon.fill"
    }
}

private func statusPalette(for status: BearDoctorCheckStatus) -> (foreground: Color, background: Color) {
    switch status {
    case .ok, .configured:
        return (
            foreground: Color.primary.opacity(0.72),
            background: Color.primary.opacity(0.08)
        )
    case .missing, .notConfigured:
        return (
            foreground: Color.orange.opacity(0.85),
            background: Color.orange.opacity(0.12)
        )
    case .invalid, .failed:
        return (
            foreground: Color.red.opacity(0.85),
            background: Color.red.opacity(0.12)
        )
    }
}

#Preview {
    UrsusDashboardView(model: UrsusAppModel())
}
