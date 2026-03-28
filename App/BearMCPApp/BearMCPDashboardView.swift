import BearApplication
import BearCore
import SwiftUI

struct BearMCPDashboardView: View {
    @ObservedObject var model: BearMCPAppModel

    var body: some View {
        TabView {
            BearMCPOverviewView(model: model)
                .tabItem {
                    Label("Overview", systemImage: "rectangle.grid.2x2")
                }

            BearMCPHostsView(model: model)
                .tabItem {
                    Label("Hosts", systemImage: "desktopcomputer")
                }

            BearMCPConfigurationView(model: model)
                .tabItem {
                    Label("Configuration", systemImage: "slider.horizontal.3")
                }

            BearMCPTokenView(model: model)
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

private struct BearMCPOverviewView: View {
    @ObservedObject var model: BearMCPAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                if let settings = model.dashboard.settings {
                    cliSection(settings)
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
                Text("Bear MCP")
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
        GroupBox("CLI Access") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host-facing CLI")
                        .font(.headline)
                    Text(settings.appManagedCLIPath)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Terminal command")
                            .font(.headline)
                        statusBadge(title: settings.terminalCLIStatusTitle, status: settings.terminalCLIStatus)
                    }
                    Text(settings.terminalCLIPath)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(settings.terminalCLIStatusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button("Install or Refresh CLI") {
                        model.installBundledCLI()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.currentBundledCLIPath == nil)

                    Button("Install Terminal CLI") {
                        model.installTerminalCLI()
                    }
                    .buttonStyle(.bordered)

                    Button("Copy CLI Path") {
                        model.copyInstalledCLIPath()
                    }
                    .buttonStyle(.bordered)

                    Button("Copy Terminal Path") {
                        model.copyTerminalCLIPath()
                    }
                    .buttonStyle(.bordered)
                }

                if let currentBundledCLIPath = model.currentBundledCLIPath {
                    Text("This app bundles `\(currentBundledCLIPath)` and can expose it both to host apps and to Terminal.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This app build does not include the embedded CLI yet, so install actions stay unavailable until the app is rebuilt.")
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
}

private struct BearMCPHostsView: View {
    @ObservedObject var model: BearMCPAppModel

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

struct BearMCPSettingsView: View {
    @ObservedObject var model: BearMCPAppModel

    var body: some View {
        BearMCPConfigurationView(model: model)
    }
}

private struct BearMCPConfigurationView: View {
    @ObservedObject var model: BearMCPAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let settings = model.dashboard.settings {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Configuration")
                                .font(.title3.weight(.semibold))
                            Text("Changes save automatically. Bear MCP keeps the JSON file in sync for you and shows inline issues before anything invalid is written.")
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
                                Toggle("Open notes in edit mode by default", isOn: autosavingBinding(\.openNoteInEditModeByDefaultDraft))
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
                                    Stepper(value: autosavingBinding(\.maxDiscoveryLimitDraft), in: model.defaultDiscoveryLimitDraft...1_000) {
                                        labeledNumber("Max discovery limit", model.maxDiscoveryLimitDraft)
                                    }
                                    validationMessages(for: .maxDiscoveryLimit)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Stepper(value: autosavingBinding(\.defaultSnippetLengthDraft), in: 1...2_000) {
                                        labeledNumber("Default snippet length", model.defaultSnippetLengthDraft)
                                    }
                                    validationMessages(for: .defaultSnippetLength)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Stepper(value: autosavingBinding(\.maxSnippetLengthDraft), in: model.defaultSnippetLengthDraft...4_000) {
                                        labeledNumber("Max snippet length", model.maxSnippetLengthDraft)
                                    }
                                    validationMessages(for: .maxSnippetLength)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Stepper(value: autosavingBinding(\.backupRetentionDaysDraft), in: 0...365) {
                                        labeledNumber("Backup retention days", model.backupRetentionDaysDraft)
                                    }
                                    validationMessages(for: .backupRetentionDays)
                                }
                            }

                            Section("Tool Availability") {
                                Text("Some host apps do not let users hide tools. Use these toggles to control the MCP tool catalog directly inside Bear MCP.")
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

                        Button("Reveal Template") {
                            model.reveal(path: settings.templatePath)
                        }
                        .buttonStyle(.bordered)
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

    private func autosavingBinding<Value>(_ keyPath: ReferenceWritableKeyPath<BearMCPAppModel, Value>) -> Binding<Value> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { newValue in
                model[keyPath: keyPath] = newValue
                model.configurationDraftDidChange()
            }
        )
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

private struct BearMCPTokenView: View {
    @ObservedObject var model: BearMCPAppModel

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

                                    if model.storedTokenHasBeenExplicitlyLoaded, let displayedToken = model.revealsStoredToken ? model.storedSelectedNoteToken : model.maskedStoredSelectedNoteToken {
                                        HStack(spacing: 10) {
                                            Text(displayedToken)
                                                .font(.body.monospaced())
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)

                                            Button(model.revealsStoredToken ? "Hide" : "Show", systemImage: model.revealsStoredToken ? "eye.slash" : "eye") {
                                                model.revealsStoredToken.toggle()
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                    } else {
                                        Text("Not loaded during routine app use. Reveal it only when you intentionally want to read the secret from Keychain.")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)

                                        Button("Load from Keychain") {
                                            model.loadStoredSelectedNoteToken()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }

                            SecureField(settings.selectedNoteTokenConfigured ? "Paste a new Bear API token to replace the current one" : "Paste Bear API token", text: $model.tokenDraft)
                                .textFieldStyle(.roundedBorder)

                            Text("Save stores the token in macOS Keychain so the configuration file can stay non-secret.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button("Save to Keychain") {
                                    model.saveSelectedNoteToken()
                                }
                                .buttonStyle(.borderedProminent)

                                if settings.selectedNoteLegacyConfigTokenDetected && !settings.selectedNoteTokenStoredInKeychain {
                                    Button("Import from config.json") {
                                        model.importSelectedNoteTokenFromConfig()
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Button("Remove Token", role: .destructive) {
                                    model.removeSelectedNoteToken()
                                }
                                .buttonStyle(.bordered)
                                .disabled(!settings.selectedNoteTokenConfigured && !settings.selectedNoteLegacyConfigTokenDetected)
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
