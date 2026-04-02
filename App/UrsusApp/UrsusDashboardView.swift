import BearApplication
import BearCore
import SwiftUI

struct UrsusDashboardView: View {
    @ObservedObject var model: UrsusAppModel

    var body: some View {
        TabView {
            UrsusOverviewView(model: model)
                .tabItem {
                    Label("Overview", systemImage: "rectangle.grid.2x2")
                }

            UrsusHostsView(model: model)
                .tabItem {
                    Label("Hosts", systemImage: "desktopcomputer")
                }

            UrsusConfigurationView(model: model)
                .tabItem {
                    Label("Configuration", systemImage: "slider.horizontal.3")
                }

            UrsusTokenView(model: model)
                .tabItem {
                    Label("Token", systemImage: "key")
                }
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

private struct UrsusOverviewView: View {
    @ObservedObject var model: UrsusAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                if let settings = model.dashboard.settings {
                    cliSection(settings)
                    bridgeSection(settings.bridge)
                    pathSection(settings)
                }
                diagnosticsSection
            }
            .padding(20)
        }
    }

    private var heroSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ursus")
                    .font(.system(size: 28, weight: .semibold))
                Text("One app for diagnostics, configuration, token management, and reusable local MCP setup across many host apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    overviewChip(label: "Version", value: model.versionDescription)
                    overviewChip(label: "Bundle", value: model.bundleIdentifier)
                    overviewChip(label: "Generated", value: model.dashboard.generatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cliSection(_ settings: BearAppSettingsSnapshot) -> some View {
        GroupBox("CLI Setup") {
            VStack(alignment: .leading, spacing: 18) {
                Text("If you connect Ursus to Codex, Claude, or another local MCP app, use the one public launcher below. That same path also works from Terminal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Ursus keeps this launcher aligned with the current app build when the dashboard opens. Manual actions below are just a fallback if you need to repair it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Public launcher")
                            .font(.headline)
                        statusBadge(title: settings.launcherStatusTitle, status: settings.launcherStatus)
                    }
                    Text(settings.launcherPath)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(settings.launcherStatusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        if let title = launcherPrimaryActionTitle(for: settings) {
                            Button(title) {
                                model.installPublicLauncher()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.currentBundledCLIPath == nil)
                        }

                        Button("Copy Launcher Path") {
                            model.copyLauncherPath()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if model.currentBundledCLIPath != nil {
                    Text("This app installs one launcher at `~/.local/bin/ursus` and routes it to the bundled `ursus` binary inside the current app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This app build does not include the bundled CLI yet, so launcher actions stay unavailable until the app is rebuilt.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                if let message = model.cliStatusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.green)
                }

                if let error = model.cliStatusError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func pathSection(_ settings: BearAppSettingsSnapshot) -> some View {
        GroupBox("Paths") {
            VStack(alignment: .leading, spacing: 12) {
                pathRow("Config File", settings.configFilePath)
                pathRow("Template", settings.templatePath)
                pathRow("Bear Database", settings.databasePath)
                pathRow("Backups", settings.backupsDirectoryPath)
                pathRow("Debug Log", settings.debugLogPath)
            }
        }
    }

    private func bridgeSection(_ bridge: BearAppBridgeSnapshot) -> some View {
        GroupBox("Remote MCP Bridge") {
            VStack(alignment: .leading, spacing: 18) {
                Text("Use this optional localhost HTTP bridge for apps that only support remote MCP URLs and cannot launch Ursus as a local stdio process.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Bridge status")
                            .font(.headline)
                        statusBadge(title: bridge.statusTitle, status: bridge.status)
                    }

                    Text(bridge.statusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                labeledValue("MCP URL", bridge.endpointURL)
                labeledValue("Bridge host", bridge.host)
                labeledValue("Bridge port", "\(bridge.port)")
                labeledValue("Health probe", bridgeHealthSummary(bridge))
                labeledValue("Launcher", bridge.launcherPath)
                labeledValue("LaunchAgent", bridge.plistPath)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Bridge port")
                        .font(.headline)
                    Text("This value saves automatically to `config.json`. Set it before installing the bridge, or reinstall/resume it after edits so the running LaunchAgent picks up the new endpoint.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Stepper(value: bridgePortBinding, in: 1024...65_535) {
                        HStack {
                            Text("Bridge port")
                            Spacer()
                            Text("\(model.bridgePortDraft)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.isBridgeOperationInProgress)

                    bridgeValidationMessages(for: .bridgePort)
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

                    Button("Copy MCP URL") {
                        model.copyBridgeURL()
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Button("Reveal LaunchAgent") {
                        model.reveal(path: bridge.plistPath)
                    }
                    .buttonStyle(.bordered)

                    Button("Reveal Stdout Log") {
                        model.reveal(path: bridge.standardOutputLogPath)
                    }
                    .buttonStyle(.bordered)

                    Button("Reveal Stderr Log") {
                        model.reveal(path: bridge.standardErrorLogPath)
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

                if let message = model.bridgeStatusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.green)
                }

                if let error = model.bridgeStatusError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        GroupBox("Runtime Checks") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.dashboard.diagnostics) { check in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: statusSymbol(for: check.status))
                                .foregroundStyle(statusColor(for: check.status))
                            Text(check.key)
                                .font(.headline)
                            Spacer(minLength: 12)
                            Text(check.value)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }

                        if let detail = check.detail {
                            Text(detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 28)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func overviewChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func pathRow(_ label: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                Button("Open") {
                    model.openFile(path: path)
                }
                .buttonStyle(.link)
                Button("Reveal") {
                    model.reveal(path: path)
                }
                .buttonStyle(.link)
            }

            Text(path)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func bridgeHealthSummary(_ bridge: BearAppBridgeSnapshot) -> String {
        if bridge.endpointProtocolCompatible {
            return "TCP + MCP initialize OK"
        }

        if bridge.endpointTransportReachable {
            return "TCP OK, MCP initialize failed"
        }

        return "No healthy endpoint detected"
    }

    private func bridgeAutosavingBinding<Value>(_ keyPath: ReferenceWritableKeyPath<UrsusAppModel, Value>) -> Binding<Value> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { newValue in
                model[keyPath: keyPath] = newValue
                model.configurationDraftDidChange()
            }
        )
    }

    private var bridgePortBinding: Binding<Int> {
        Binding(
            get: { model.bridgePortDraft },
            set: { model.updateBridgePortDraft($0) }
        )
    }

    @ViewBuilder
    private func bridgeValidationMessages(for field: BearAppConfigurationField) -> some View {
        let issues = model.configurationIssues(for: field)
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(issues) { issue in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .padding(.top, 1)
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct UrsusHostsView: View {
    @ObservedObject var model: UrsusAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Host Guidance") {
                    Text("The app should stay host-agnostic first. Reuse the same stable CLI path and `mcp` argument across whatever local stdio MCP host you use, then keep app-specific snippets as convenience layers rather than hard dependencies.")
                        .foregroundStyle(.secondary)
                }

                if let settings = model.dashboard.settings {
                    GroupBox("Host Apps") {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(settings.hostAppSetups) { setup in
                                hostCard(setup)
                            }

                            if let message = model.hostSetupStatusMessage {
                                Text(message)
                                    .font(.callout)
                                    .foregroundStyle(.green)
                            }

                            if let error = model.hostSetupStatusError {
                                Text(error)
                                    .font(.callout)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func hostCard(_ setup: BearHostAppSetupSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(setup.appName)
                    .font(.headline)
                Spacer(minLength: 12)
                statusBadge(title: setup.statusTitle, status: setup.status)
            }

            if let configPath = setup.configPath {
                labeledValue("Config Path", configPath)
            }

            Text(setup.detail)
                .font(.callout)
                .foregroundStyle(.secondary)

            DisclosureGroup("Show setup details") {
                VStack(alignment: .leading, spacing: 12) {
                    if let configPath = setup.configPath {
                        labeledValue("Config Path", configPath)
                    }

                    if let mergeNote = setup.mergeNote {
                        Text(mergeNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        if setup.snippet != nil {
                            Button("Copy Snippet") {
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

                    if let snippet = setup.snippet {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(setup.snippetTitle ?? "Setup Snippet")
                                .font(.headline)
                            Text(snippet)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    if !setup.checks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Guided Checks")
                                .font(.headline)

                            ForEach(setup.checks, id: \.self) { check in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 2)
                                    Text(check)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct UrsusSettingsView: View {
    @ObservedObject var model: UrsusAppModel

    var body: some View {
        UrsusConfigurationView(model: model)
    }
}

private struct UrsusConfigurationView: View {
    @ObservedObject var model: UrsusAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let settings = model.dashboard.settings {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Configuration")
                                .font(.title3.weight(.semibold))
                            Text("Changes save automatically. Ursus keeps the JSON file in sync for you and shows inline issues before anything invalid is written.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Live Configuration") {
                        Form {
                            Section("Core") {
                                VStack(alignment: .leading, spacing: 6) {
                                    TextField(
                                        "Bear database path",
                                        text: Binding(
                                            get: { model.databasePathDraft },
                                            set: { model.updateDatabasePathDraft($0) }
                                        )
                                    )
                                    validationMessages(for: .databasePath)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    TextField("Inbox tags (comma or newline separated)", text: autosavingBinding(\.inboxTagsDraft), axis: .vertical)
                                        .lineLimit(2...4)
                                    validationMessages(for: .inboxTags)
                                }

                                Picker("Default insert position", selection: autosavingBinding(\.defaultInsertPositionDraft)) {
                                    Text("Top").tag(BearConfiguration.InsertDefault.top)
                                    Text("Bottom").tag(BearConfiguration.InsertDefault.bottom)
                                }

                                Picker("Tags merge mode", selection: autosavingBinding(\.tagsMergeModeDraft)) {
                                    Text("Append").tag(BearConfiguration.TagsMergeMode.append)
                                    Text("Replace").tag(BearConfiguration.TagsMergeMode.replace)
                                }
                            }

                            Section("Defaults") {
                                Toggle("Template management enabled", isOn: autosavingBinding(\.templateManagementEnabledDraft))
                                Toggle("Create opens note by default", isOn: autosavingBinding(\.createOpensNoteByDefaultDraft))
                                Toggle("Open uses new window by default", isOn: autosavingBinding(\.openUsesNewWindowByDefaultDraft))
                                Toggle("Create adds inbox tags by default", isOn: autosavingBinding(\.createAddsInboxTagsByDefaultDraft))
                            }

                            Section("Limits") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Stepper(value: autosavingBinding(\.defaultDiscoveryLimitDraft), in: 1...500) {
                                        labeledNumber("Default discovery limit", model.defaultDiscoveryLimitDraft)
                                    }
                                    validationMessages(for: .defaultDiscoveryLimit)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Stepper(value: autosavingBinding(\.defaultSnippetLengthDraft), in: 1...2_000) {
                                        labeledNumber("Default snippet length", model.defaultSnippetLengthDraft)
                                    }
                                    validationMessages(for: .defaultSnippetLength)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Stepper(value: autosavingBinding(\.backupRetentionDaysDraft), in: 0...365) {
                                        labeledNumber("Backup retention days", model.backupRetentionDaysDraft)
                                    }
                                    validationMessages(for: .backupRetentionDays)
                                }
                            }

                            Section("Tool Availability") {
                                Text("Some host apps do not let users hide tools. Use these toggles to control the MCP tool catalog directly inside Ursus.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)

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
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(tool.title)
                                                        Text(tool.summary)
                                                            .font(.callout)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                        .formStyle(.grouped)
                    }

                    HStack(spacing: 10) {
                        Button("Reveal Configuration") {
                            model.reveal(path: settings.configFilePath)
                        }
                        .buttonStyle(.bordered)
                    }

                    GroupBox("Template") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Edit the live `template.md` file here. This template is only the note body that appears below Bear's title line.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            labeledValue("Template Path", settings.templatePath)

                            HStack(spacing: 10) {
                                Button("Open Template") {
                                    model.openFile(path: settings.templatePath)
                                }
                                .buttonStyle(.bordered)

                                Button("Reveal Template") {
                                    model.reveal(path: settings.templatePath)
                                }
                                .buttonStyle(.bordered)
                            }

                            Text("Required: `{{content}}`, `{{tags}}`.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Text("Keep any spacing you want inside the template itself. Leading or trailing blank lines outside the template are trimmed.")
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
                            .padding(8)
                            .background(Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

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
                                Text("Unsaved changes are only in this app until you save.")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }

                            if let message = model.templateStatusMessage {
                                Text(message)
                                    .font(.callout)
                                    .foregroundStyle(model.templateValidation.warnings.isEmpty ? .green : .orange)
                            }

                            if let error = model.templateStatusError {
                                Text(error)
                                    .font(.callout)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if let message = model.configurationStatusMessage {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(model.configurationValidation.warnings.isEmpty ? .green : .orange)
                    }

                    if let error = model.configurationStatusError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                } else {
                    unavailableSection
                }
            }
            .padding(20)
        }
    }

    private var unavailableSection: some View {
        GroupBox("Configuration") {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.dashboard.settingsError ?? "Settings are unavailable.")
                    .foregroundStyle(.secondary)
                Button("Reload") {
                    model.reload()
                }
            }
        }
    }

    private func labeledNumber(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.templateValidation.issues) { issue in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .padding(.top, 1)
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func validationMessages(for field: BearAppConfigurationField) -> some View {
        let issues = model.configurationIssues(for: field)
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(issues) { issue in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .padding(.top, 1)
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct UrsusTokenView: View {
    @ObservedObject var model: UrsusAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let settings = model.dashboard.settings {
                    GroupBox("Bear Token") {
                        VStack(alignment: .leading, spacing: 12) {
                            labeledValue("Current Status", settings.selectedNoteTokenStorageDescription)

                            if let detail = settings.selectedNoteTokenStatusDetail {
                                Text(detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            if settings.selectedNoteTokenConfigured {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Stored Token")
                                        .font(.headline)

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
                                        Text("Token is configured but could not be loaded from macOS Keychain right now.")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)

                                        Button("Try Again") {
                                            model.loadStoredSelectedNoteToken()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }

                            SecureField(settings.selectedNoteTokenConfigured ? "Paste a new Bear API token to replace the current one" : "Paste Bear API token", text: $model.tokenDraft)
                                .textFieldStyle(.roundedBorder)

                            Text("Save stores the token in macOS Keychain. Ursus keeps it hidden by default and only loads it into the dashboard when you explicitly reveal it.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button("Save Token") {
                                    model.saveSelectedNoteToken()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Remove Token", role: .destructive) {
                                    model.removeSelectedNoteToken()
                                }
                                .buttonStyle(.bordered)
                                .disabled(!settings.selectedNoteTokenConfigured)
                            }

                            if let message = model.tokenStatusMessage {
                                Text(message)
                                    .font(.callout)
                                    .foregroundStyle(.green)
                            }

                            if let error = model.tokenStatusError {
                                Text(error)
                                    .font(.callout)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private func labeledValue(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label)
            .font(.headline)
        Text(value)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}

private func statusBadge(title: String, status: BearDoctorCheckStatus) -> some View {
    Text(title)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor(for: status).opacity(0.14))
        .foregroundStyle(statusColor(for: status))
        .clipShape(Capsule())
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
