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
                    Label("Tools", systemImage: "wrench.and.screwdriver")
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
    @State private var showsTokenInput = false

    var body: some View {
        UrsusScrollSurface {
            if let settings = model.dashboard.settings {
                VStack(alignment: .leading, spacing: 20) {
                    heroPanel
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

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Ursus")
                .font(.system(size: 34, weight: .black))
                .tracking(-2.0)

            Text("Local MCP and utilities for Bear")
                .font(.callout)
                .foregroundStyle(.tertiary)
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
                UrsusInfoRow(
                    label: "Template management",
                    value: settings.templateManagementEnabled ? "On" : "Off",
                    compact: true,
                    prominentLabel: true
                )
                Divider()
                UrsusInfoRow(
                    label: "Inbox tags",
                    value: settings.inboxTags.isEmpty ? "None" : settings.inboxTags.joined(separator: ", "),
                    compact: true,
                    prominentLabel: true
                )
                Divider()
                UrsusInfoRow(
                    label: "New notes",
                    value: settings.createOpensNoteByDefault ? "Open by default" : "Stay in the background",
                    compact: true,
                    prominentLabel: true
                )
                Divider()
                UrsusInfoRow(
                    label: "Default insert",
                    value: friendlyInsertPosition(settings.defaultInsertPosition),
                    compact: true,
                    prominentLabel: true
                )
            }
        }
    }

    private func tokenPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(
            title: "Bear Token",
            titleHelpText: "Token is safely stored in macOS Keychain.",
            headerAccessory: {
                if settings.selectedNoteTokenConfigured {
                    UrsusStatusBadge(title: "Saved", status: .configured)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Optional. Required for selected-note flows.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if settings.selectedNoteTokenConfigured && !showsTokenInput {
                    if let displayedToken = model.revealsStoredToken ? model.storedSelectedNoteToken : model.maskedStoredSelectedNoteToken {
                        HStack(spacing: 10) {
                            Text(displayedToken)
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            Spacer(minLength: 12)

                            Button {
                                model.loadStoredSelectedNoteToken()
                            } label: {
                                Label(
                                    model.revealsStoredToken ? "Hide" : "Show",
                                    systemImage: model.revealsStoredToken ? "eye.slash" : "eye"
                                )
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

                    HStack(spacing: 10) {
                        Button("Replace") {
                            showsTokenInput = true
                        }
                        .buttonStyle(.bordered)

                        Button("Remove", role: .destructive) {
                            model.removeSelectedNoteToken()
                            showsTokenInput = false
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    SecureField(
                        settings.selectedNoteTokenConfigured
                            ? "Paste a new Bear API token"
                            : "Paste Bear API token",
                        text: $model.tokenDraft
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack(spacing: 10) {
                        Button("Save Token") {
                            model.saveSelectedNoteToken()
                            showsTokenInput = false
                        }
                        .buttonStyle(.bordered)

                        if showsTokenInput {
                            Button("Cancel") {
                                model.tokenDraft = ""
                                showsTokenInput = false
                            }
                            .buttonStyle(.bordered)
                        }
                    }
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
            title: "Connect Apps",
            titleHelpText: "Copy a setup snippet for apps installed on this Mac."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if let title = launcherPrimaryActionTitle(for: settings) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Install the launcher before copying setup.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 12)

                        Button(title) {
                            model.installPublicLauncher()
                        }
                        .buttonStyle(.bordered)
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

        return UrsusPanel(
            title: "Remote MCP Bridge",
            titleHelpText: "Use this when an app needs a local MCP URL instead of launching Ursus directly.",
            headerAccessory: {
                UrsusStatusBadge(title: compactStatusTitle(for: bridge.status), status: bridge.status)
            }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if let bridgeStateText = bridgeStateText(for: settings) {
                    Text(bridgeStateText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                UrsusInfoRow(label: "MCP URL", value: bridge.endpointURL, compact: true, monospaced: true)

                VStack(alignment: .leading, spacing: 6) {
                    UrsusNumericFieldRow(
                        label: "Port",
                        value: bridgePortBinding,
                        range: 1024...65_535,
                        disabled: model.isBridgeOperationInProgress,
                        readOnly: bridge.installed,
                        helpText: "Port is only customizable before installing the bridge.",
                        fieldWidth: 92
                    )
                    configurationValidationMessages(for: .bridgePort)
                }

                HStack(spacing: 10) {
                    if let recoveryAction = bridgeRecoveryAction(for: settings) {
                        Button(recoveryAction.title) {
                            performRecoveryAction(recoveryAction, settings: settings)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.currentBundledCLIPath == nil || model.isBridgeOperationInProgress)
                    } else if let title = bridgePrimaryActionTitle(for: bridge) {
                        Button(title) {
                            model.installBridge(
                                repairing: bridge.status == .invalid || bridge.status == .failed
                            )
                        }
                        .buttonStyle(.bordered)
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

    private func bridgeStateText(for settings: BearAppSettingsSnapshot) -> String? {
        let bridge = settings.bridge

        if bridge.loaded, bridge.status == .ok || bridge.status == .configured {
            return nil
        }

        switch bridge.status {
        case .missing:
            return "Install the bridge to get a local MCP URL."
        case .notConfigured:
            return bridge.installed ? "Installed, but not serving requests." : nil
        case .invalid, .failed:
            switch bridgeRecoveryAction(for: settings) {
            case .installLauncher:
                return "Install the launcher before using the bridge."
            case .repairLauncher:
                return "Repair the launcher before using the bridge."
            case .repairBridge:
                return "Repair the bridge to restore the local MCP URL."
            case .installBridge:
                return "Install the bridge to get a local MCP URL."
            case .none:
                return "Bridge needs attention."
            }
        case .ok, .configured:
            return nil
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
                VStack(alignment: .leading, spacing: 20) {
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
        UrsusPanel(
            title: "Note Behavior",
            titleHelpText: "Tools will use these defaults, but you can command the AI to override them in your requests."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Create opens note by default", isOn: autosavingBinding(\.createOpensNoteByDefaultDraft))
                Divider()
                Toggle("Open uses new window by default", isOn: autosavingBinding(\.openUsesNewWindowByDefaultDraft))
                Divider()
                Toggle("Create adds inbox tags by default", isOn: autosavingBinding(\.createAddsInboxTagsByDefaultDraft))
                Divider()
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
                Divider()
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
        UrsusPanel(title: "Inbox Tags") {
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
                    .frame(height: 158)
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
                        .buttonStyle(.bordered)
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
        UrsusPanel(title: "Read and Backup Limits") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    UrsusNumericFieldRow(
                        label: "Default discovery limit",
                        value: autosavingBinding(\.defaultDiscoveryLimitDraft),
                        range: 1...500,
                        helpText: "Maximum number of note summaries returned by the Find Notes and List Backups tools."
                    )
                    configurationValidationMessages(for: .defaultDiscoveryLimit)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    UrsusNumericFieldRow(
                        label: "Default snippet length",
                        value: autosavingBinding(\.defaultSnippetLengthDraft),
                        range: 1...2_000
                    )
                    configurationValidationMessages(for: .defaultSnippetLength)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    UrsusNumericFieldRow(
                        label: "Backup retention days",
                        value: autosavingBinding(\.backupRetentionDaysDraft),
                        range: 0...365,
                        helpText: "Temporary backups are automatically created on note editing & replace operations."
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
                VStack(alignment: .leading, spacing: 24) {
                    if launcherPrimaryActionTitle(for: settings) != nil {
                        launcherPanel(settings)
                        Divider()
                    }
                    toolAvailabilityPanel(settings)
                }
            } else {
                unavailablePanel(
                    title: "Tools are unavailable",
                    detail: model.dashboard.settingsError ?? "Ursus could not load its current settings."
                )
            }
        }
    }

    private func launcherPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(title: "Launcher") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    UrsusStatusBadge(title: compactStatusTitle(for: settings.launcherStatus), status: settings.launcherStatus)
                    Text(settings.launcherStatusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let actionTitle = launcherPrimaryActionTitle(for: settings) {
                    Button(actionTitle) {
                        model.installPublicLauncher()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.currentBundledCLIPath == nil)
                }

                UrsusMessageStack(
                    success: model.cliStatusMessage,
                    warning: nil,
                    error: model.cliStatusError
                )
            }
        }
    }

    private func toolAvailabilityPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        let sections: [(category: BearToolCategory, tools: [BearAppToolToggleSnapshot])] = BearToolCategory.allCases.compactMap { category in
            let tools = settings.toolToggles.filter { $0.category == category }
            return tools.isEmpty ? nil : (category, tools)
        }

        return VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, entry in
                let category = entry.category
                let tools = entry.tools

                if index > 0 {
                    Divider()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(category.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                            Toggle(isOn: Binding(
                                get: { model.isToolEnabledInDraft(tool.tool) },
                                set: { model.setToolEnabledInDraft(tool.tool, enabled: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tool.title)
                                        .font(.subheadline)
                                    Text(tool.summary)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(14)

                            if index < tools.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(UrsusPanelBackground(style: .subtle))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
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

private struct UrsusHostSetupRow: View {
    @ObservedObject var model: UrsusAppModel
    let setup: BearHostAppSetupSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(setup.appName)
                    .font(.callout.weight(.medium))
                Spacer()
                UrsusStatusBadge(title: compactStatusTitle(for: setup.status), status: setup.status)
            }

            if let detail = hostSetupDetail(for: setup) {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if setup.snippet != nil {
                    Button("Copy Setup") {
                        model.copyHostSetupSnippet(setup)
                    }
                    .buttonStyle(.bordered)
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
    let titleHelpText: String?
    let surface: UrsusSectionSurface
    let headerAccessory: AnyView?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        titleHelpText: String? = nil,
        surface: UrsusSectionSurface = .plain,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleHelpText = titleHelpText
        self.surface = surface
        self.headerAccessory = nil
        self.content = content()
    }

    init<HeaderAccessory: View>(
        title: String,
        subtitle: String? = nil,
        titleHelpText: String? = nil,
        surface: UrsusSectionSurface = .plain,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleHelpText = titleHelpText
        self.surface = surface
        self.headerAccessory = AnyView(headerAccessory())
        self.content = content()
    }

    var body: some View {
        if surface == .plain {
            VStack(alignment: .leading, spacing: 8) {
                panelHeader
                content
                    .padding(16)
                    .background(UrsusPanelBackground(style: .subtle))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            }
        } else if surface == .subtle {
            VStack(alignment: .leading, spacing: 12) {
                panelHeader
                content
            }
            .padding(20)
            .background(UrsusPanelBackground(style: .subtle))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                panelHeader
                content
            }
            .padding(24)
            .background(UrsusPanelBackground(style: .prominent))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var panelHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let titleHelpText {
                        UrsusHelpButton(text: titleHelpText)
                    }
                }

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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.title2, design: .default).weight(.black))
                .tracking(-1.0)

            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct UrsusInfoRow: View {
    let label: String
    let value: String
    var compact = false
    var monospaced = false
    var prominentLabel = false

    var body: some View {
        if compact {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(label)
                    .font(prominentLabel ? .caption.weight(.semibold) : .footnote)
                    .foregroundStyle(prominentLabel ? .secondary : .tertiary)
                Spacer(minLength: 12)
                Text(value)
                    .font(monospaced ? .system(.caption, design: .monospaced) : .callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
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
    var readOnly = false
    var helpText: String?
    var fieldWidth: CGFloat = 80

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .foregroundStyle(.secondary)

                if let helpText {
                    UrsusHelpButton(text: helpText)
                }
            }

            Spacer()

            if readOnly {
                Text("\(value.wrappedValue)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(UrsusPanelBackground(style: .subtle))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .help(helpText ?? "")
            } else {
                TextField(label, value: value, formatter: ursusIntegerFormatter)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: fieldWidth)
                    .disabled(disabled)
                    .help(helpText ?? "")

                Stepper("", value: value, in: range)
                    .labelsHidden()
                    .disabled(disabled)
                    .help(helpText ?? "")
            }
        }
    }
}

private struct UrsusHelpButton: View {
    let text: String
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
                .padding(14)
        }
    }
}

private struct UrsusStatusBadge: View {
    let title: String
    let status: BearDoctorCheckStatus

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusPalette(for: status).background)
            .foregroundStyle(statusPalette(for: status).foreground)
            .clipShape(Capsule())
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
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(noticeAccentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(noticeAccentColor)
                    .textCase(.uppercase)
                    .tracking(0.4)

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                actions
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(UrsusPanelBackground(style: .prominent))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var noticeAccentColor: Color {
        switch tone {
        case .neutral: return .accentColor
        case .warning: return .orange
        case .error: return .red
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

private func hostSetupDetail(for setup: BearHostAppSetupSnapshot) -> String? {
    switch setup.status {
    case .ok, .configured:
        return nil
    case .missing:
        return "Open the app once if needed, then copy setup to connect it."
    case .notConfigured:
        return "Copy setup to connect this app."
    case .invalid, .failed:
        return "Copy setup again to repair this app's connection."
    }
}

private func statusPalette(for status: BearDoctorCheckStatus) -> (foreground: Color, background: Color) {
    switch status {
    case .ok, .configured:
        return (
            foreground: Color.mint,
            background: Color.mint.opacity(0.12)
        )
    case .missing, .notConfigured:
        return (
            foreground: Color.orange,
            background: Color.orange.opacity(0.1)
        )
    case .invalid, .failed:
        return (
            foreground: Color.red,
            background: Color.red.opacity(0.1)
        )
    }
}

#Preview {
    UrsusDashboardView(model: UrsusAppModel())
}
