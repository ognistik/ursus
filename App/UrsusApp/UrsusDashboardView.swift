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
                    defaultsPanel(settings)
                    tokenPanel(settings)
                    connectAppsPanel(settings)
                    bridgePanel(settings.bridge)
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
        UrsusPanel(
            title: "Set up Ursus once, come back only when something needs repair.",
            subtitle: "The main path is simple: review a few defaults, save your Bear token, then connect a local app or enable the optional bridge."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ursus \(model.versionDescription)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                ForEach(setupSteps(for: settings)) { step in
                    UrsusChecklistRow(step: step)
                }
            }
        }
    }

    private func defaultsPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(
            title: "1. Configure defaults",
            subtitle: "These are the only durable settings most people need to care about up front."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                UrsusInfoRow(label: "Template management", value: settings.templateManagementEnabled ? "On" : "Off")
                UrsusInfoRow(
                    label: "Inbox tags",
                    value: settings.inboxTags.isEmpty ? "None yet" : settings.inboxTags.joined(separator: ", ")
                )
                UrsusInfoRow(
                    label: "New notes",
                    value: settings.createOpensNoteByDefault ? "Open in Bear by default" : "Stay in the background by default"
                )
                UrsusInfoRow(
                    label: "Default insert",
                    value: friendlyInsertPosition(settings.defaultInsertPosition)
                )

                Button("Open Preferences") {
                    selectedSection = .preferences
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func tokenPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(
            title: "2. Save Bear token",
            subtitle: "Ursus stores the token in macOS Keychain and keeps it hidden unless you explicitly reveal it."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(tokenStatusTitle(for: settings))
                        .font(.headline)
                    UrsusStatusBadge(
                        title: settings.selectedNoteTokenConfigured ? "Saved" : "Missing",
                        status: settings.selectedNoteTokenConfigured ? .configured : .notConfigured
                    )
                }

                if let detail = settings.selectedNoteTokenStatusDetail, !settings.selectedNoteTokenConfigured {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if settings.selectedNoteTokenConfigured {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stored token")
                            .font(.subheadline.weight(.semibold))

                        if let displayedToken = model.revealsStoredToken ? model.storedSelectedNoteToken : model.maskedStoredSelectedNoteToken {
                            HStack(spacing: 10) {
                                Text(displayedToken)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)

                                Button(model.revealsStoredToken ? "Hide" : "Show", systemImage: model.revealsStoredToken ? "eye.slash" : "eye") {
                                    model.loadStoredSelectedNoteToken()
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Text("The token is saved, but Ursus could not load it into the app right now.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Button("Try Again") {
                                model.loadStoredSelectedNoteToken()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                SecureField(
                    settings.selectedNoteTokenConfigured
                        ? "Paste a new Bear API token to replace the current one"
                        : "Paste Bear API token",
                    text: $model.tokenDraft
                )
                .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button(settings.selectedNoteTokenConfigured ? "Replace Token" : "Save Token") {
                        model.saveSelectedNoteToken()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Remove Token", role: .destructive) {
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
        UrsusPanel(
            title: "3. Connect an app",
            subtitle: "Only show the apps that matter on this Mac. Copy the setup snippet if you want Ursus to run as a local stdio MCP server."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if let title = launcherPrimaryActionTitle(for: settings) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Local launcher needs attention")
                                .font(.headline)
                            UrsusStatusBadge(title: settings.launcherStatusTitle, status: settings.launcherStatus)
                        }

                        Text("Repair the launcher before you copy setup into Codex or Claude Desktop.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button(title) {
                            model.installPublicLauncher()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.currentBundledCLIPath == nil)
                    }

                    Divider()
                }

                if model.setupHostSetups.isEmpty {
                    Text("No supported local host apps were detected. If you need an MCP URL instead of a local launcher, use the bridge below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.setupHostSetups.enumerated()), id: \.element.id) { index, setup in
                        UrsusHostSetupRow(model: model, setup: setup)

                        if index < model.setupHostSetups.count - 1 {
                            Divider()
                        }
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

    private func bridgePanel(_ bridge: BearAppBridgeSnapshot) -> some View {
        UrsusPanel(
            title: "Optional localhost bridge",
            subtitle: "Use the bridge only when an app needs an MCP URL instead of launching Ursus locally."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(bridge.loaded ? "Bridge is running" : bridge.installed ? "Bridge is installed" : "Bridge is off")
                        .font(.headline)
                    UrsusStatusBadge(title: bridge.statusTitle, status: bridge.status)
                }

                if bridge.status != .ok || bridge.status == .configured {
                    Text(bridge.statusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                UrsusInfoRow(label: "MCP URL", value: bridge.endpointURL)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Bridge port")
                        .font(.subheadline.weight(.semibold))

                    Stepper(value: bridgePortBinding, in: 1024...65_535) {
                        HStack {
                            Text("Saved port")
                            Spacer()
                            Text("\(model.bridgePortDraft)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.isBridgeOperationInProgress)

                    configurationValidationMessages(for: .bridgePort)
                }

                HStack(spacing: 10) {
                    if let title = bridgePrimaryActionTitle(for: bridge) {
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
            detail: settings.selectedNoteTokenConfigured
                ? "Your Bear token is already stored in Keychain."
                : "Paste a Bear API token so selected-note flows can work.",
            status: settings.selectedNoteTokenConfigured ? .configured : .notConfigured
        )

        let hostConfigured = model.setupHostSetups.contains { $0.status == .ok }
        let hostNeedsAttention = model.setupHostSetups.contains { $0.status == .invalid }
        let bridgeReady = settings.bridge.loaded
        let connectionStatus: BearDoctorCheckStatus
        let connectionDetail: String

        if bridgeReady || hostConfigured {
            connectionStatus = .configured
            if bridgeReady && hostConfigured {
                connectionDetail = "A local host is configured and the bridge is running."
            } else if bridgeReady {
                connectionDetail = "The bridge is ready to share an MCP URL."
            } else {
                connectionDetail = "A detected local app is already configured."
            }
        } else if settings.launcherStatus == .missing || settings.launcherStatus == .invalid || settings.bridge.status == .invalid || settings.bridge.status == .failed || hostNeedsAttention {
            connectionStatus = .invalid
            connectionDetail = "Repair the launcher, update one app connection, or fix the bridge."
        } else {
            connectionStatus = .notConfigured
            connectionDetail = "Choose one local app to connect, or enable the bridge instead."
        }

        return [
            UrsusSetupStep(
                title: "Configure defaults",
                detail: defaultsSummary(for: settings),
                status: .configured
            ),
            tokenStep,
            UrsusSetupStep(
                title: "Connect an app or bridge",
                detail: connectionDetail,
                status: connectionStatus
            ),
        ]
    }

    private func defaultsSummary(for settings: BearAppSettingsSnapshot) -> String {
        let tagSummary = settings.inboxTags.isEmpty ? "no inbox tags" : "\(settings.inboxTags.count) inbox \(settings.inboxTags.count == 1 ? "tag" : "tags")"
        let templateSummary = settings.templateManagementEnabled ? "template on" : "template off"
        return "\(templateSummary), \(tagSummary), insert at \(friendlyInsertPosition(settings.defaultInsertPosition).lowercased())."
    }

    private func tokenStatusTitle(for settings: BearAppSettingsSnapshot) -> String {
        settings.selectedNoteTokenConfigured ? "Token is saved in Keychain" : "Token is missing"
    }
}

private struct UrsusPreferencesView: View {
    @ObservedObject var model: UrsusAppModel
    let showsStandaloneHeader: Bool

    var body: some View {
        UrsusScrollSurface {
            if let settings = model.dashboard.settings {
                VStack(alignment: .leading, spacing: 24) {
                    if showsStandaloneHeader {
                        UrsusPanel(
                            title: "Preferences",
                            subtitle: "These settings shape note creation, template behavior, and read-side defaults. Changes save automatically."
                        ) {
                            EmptyView()
                        }
                    }

                    behaviorPanel
                    inboxTagsPanel
                    templatePanel(settings)
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
        UrsusPanel(
            title: "Note behavior",
            subtitle: "Keep the main defaults compact and easy to scan."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Create opens note by default", isOn: autosavingBinding(\.createOpensNoteByDefaultDraft))
                Divider()
                Toggle("Open uses new window by default", isOn: autosavingBinding(\.openUsesNewWindowByDefaultDraft))
                Divider()
                Toggle("Create adds inbox tags by default", isOn: autosavingBinding(\.createAddsInboxTagsByDefaultDraft))
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Default insert position")
                        .font(.subheadline.weight(.semibold))

                    Picker("Default insert position", selection: autosavingBinding(\.defaultInsertPositionDraft)) {
                        Text("Top").tag(BearConfiguration.InsertDefault.top)
                        Text("Bottom").tag(BearConfiguration.InsertDefault.bottom)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags merge mode")
                        .font(.subheadline.weight(.semibold))

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
        UrsusPanel(
            title: "Inbox tags",
            subtitle: "Use tags here when you want new notes to start with a predictable inbox bucket."
        ) {
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
        UrsusPanel(
            title: "Template",
            subtitle: "Keep template editing in the app, but only surface it when template management is turned on."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Enable template management", isOn: autosavingBinding(\.templateManagementEnabledDraft))

                if model.templateManagementEnabledDraft {
                    Text("Required slots: `{{content}}` and `{{tags}}`.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    TextEditor(text: Binding(
                        get: { model.templateDraft },
                        set: { newValue in
                            model.templateDraft = newValue
                            model.templateDraftDidChange()
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
                    .padding(10)
                    .background(UrsusPanelBackground())
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    UrsusMessageStack(
                        success: model.templateValidation.warnings.isEmpty ? model.templateStatusMessage : nil,
                        warning: model.templateValidation.warnings.isEmpty ? nil : model.templateStatusMessage,
                        error: model.templateStatusError
                    )
                } else {
                    Text("Template editing is hidden while template management is off.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var limitsPanel: some View {
        UrsusPanel(
            title: "Limits",
            subtitle: "Keep the advanced defaults in one quiet place instead of mixing them into the main setup flow."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Stepper(value: autosavingBinding(\.defaultDiscoveryLimitDraft), in: 1...500) {
                        UrsusNumberRow(label: "Default discovery limit", value: model.defaultDiscoveryLimitDraft)
                    }
                    configurationValidationMessages(for: .defaultDiscoveryLimit)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Stepper(value: autosavingBinding(\.defaultSnippetLengthDraft), in: 1...2_000) {
                        UrsusNumberRow(label: "Default snippet length", value: model.defaultSnippetLengthDraft)
                    }
                    configurationValidationMessages(for: .defaultSnippetLength)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Stepper(value: autosavingBinding(\.backupRetentionDaysDraft), in: 0...365) {
                        UrsusNumberRow(label: "Backup retention days", value: model.backupRetentionDaysDraft)
                    }
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
                VStack(alignment: .leading, spacing: 24) {
                    launcherPanel(settings)
                    filesPanel(settings)
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
            subtitle: "Keep the deeper repair controls out of the main setup path."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Local launcher")
                        .font(.headline)
                    UrsusStatusBadge(title: settings.launcherStatusTitle, status: settings.launcherStatus)
                }

                Text(settings.launcherStatusDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                UrsusInfoRow(label: "Launcher path", value: settings.launcherPath)

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
            VStack(alignment: .leading, spacing: 12) {
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
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.title)
                                .font(.headline)

                            ForEach(tools) { tool in
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
                UrsusStatusBadge(title: setup.statusTitle, status: setup.status)
            }

            Text(setup.detail)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if setup.snippet != nil {
                    Button("Copy Setup") {
                        model.copyHostSetupSnippet(setup)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let configPath = setup.configPath {
                    Button("Reveal Config") {
                        model.reveal(path: configPath)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct UrsusChecklistRow: View {
    let step: UrsusSetupStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol(for: step.status))
                .foregroundStyle(statusColor(for: step.status))
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.headline)

                Text(step.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
            .frame(maxWidth: 860, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct UrsusPanel<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .tracking(-0.2)

                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(22)
        .background(UrsusPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct UrsusPanelBackground: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        Color.secondary.opacity(environment.colorScheme == .dark ? 0.12 : 0.06)
    }
}

private struct UrsusInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct UrsusNumberRow: View {
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
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
            .background(statusColor(for: status).opacity(0.12))
            .foregroundStyle(statusColor(for: status))
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
                        .foregroundStyle(issue.ursusSeverity == .error ? .red : .orange)
                        .padding(.top, 1)

                    Text(issue.ursusMessage)
                        .font(.caption)
                        .foregroundStyle(issue.ursusSeverity == .error ? .red : .orange)
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
                Text(success)
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            if let warning, warning != success {
                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct UrsusTagEditor: View {
    let tags: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tags.isEmpty {
                Text("No inbox tags yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Add a tag or paste a comma-separated list", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDraft)

                Button("Add") {
                    addDraft()
                }
                .buttonStyle(.bordered)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    let detail: String
    let status: BearDoctorCheckStatus
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
    UrsusPanel(title: title, subtitle: detail) {
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
        return "Needs setup"
    case .invalid, .failed:
        return "Attention"
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

private func statusColor(for status: BearDoctorCheckStatus) -> Color {
    switch status {
    case .ok, .configured:
        return .green
    case .missing, .notConfigured:
        return .orange
    case .invalid, .failed:
        return .red
    }
}

#Preview {
    UrsusDashboardView(model: UrsusAppModel())
}
