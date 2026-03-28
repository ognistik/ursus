import BearApplication
import BearCore
import SwiftUI

struct BearMCPDashboardView: View {
    @ObservedObject var model: BearMCPAppModel

    var body: some View {
        TabView {
            BearMCPDiagnosticsView(model: model)
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }

            BearMCPSettingsView(model: model)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
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

private struct BearMCPDiagnosticsView: View {
    @ObservedObject var model: BearMCPAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appSummarySection
                callbackSection
                diagnosticsSection
            }
            .padding(20)
        }
    }

    private var appSummarySection: some View {
        GroupBox("App") {
            VStack(alignment: .leading, spacing: 10) {
                labeledRow("Bundle", model.appDisplayName)
                labeledRow("Identifier", model.bundleIdentifier)
                labeledRow("Version", model.versionDescription)
                labeledRow("Generated", model.dashboard.generatedAt.formatted(date: .abbreviated, time: .standard))
            }
        }
    }

    private var callbackSection: some View {
        GroupBox("Callback Registration") {
            VStack(alignment: .leading, spacing: 10) {
                labeledRow(
                    "Registered Schemes",
                    model.callbackSchemes.isEmpty ? "None detected" : model.callbackSchemes.joined(separator: ", ")
                )
                if let url = model.lastIncomingCallbackURL {
                    labeledRow("Last Incoming URL", url.absoluteString)
                    Text("`bearmcp://` is now owned by `Bear MCP.app`. The standalone helper remains only as a temporary fallback when the preferred app install is unavailable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("`Bear MCP.app` is the intended callback host, whether it launches headlessly for a request or stays open in dashboard mode. The helper should keep shrinking toward an emergency-only fallback.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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

    private func labeledRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.headline)
            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
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
}

struct BearMCPSettingsView: View {
    @ObservedObject var model: BearMCPAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let settings = model.dashboard.settings {
                    pathSection(settings)
                    cliSection(settings)
                    hostAppsSection(settings)
                    tokenSection(settings)
                    configSection(settings)
                    notesSection(settings)
                } else {
                    GroupBox("Settings") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.dashboard.settingsError ?? "Settings are unavailable.")
                                .foregroundStyle(.secondary)
                            Button("Reload") {
                                model.reload()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func pathSection(_ settings: BearAppSettingsSnapshot) -> some View {
        GroupBox("Paths") {
            VStack(alignment: .leading, spacing: 12) {
                pathRow("Config Directory", settings.configDirectoryPath)
                pathRow("Config File", settings.configFilePath)
                pathRow("Template", settings.templatePath)
                pathRow("Bear Database", settings.databasePath)
                pathRow("Backups", settings.backupsDirectoryPath)
                pathRow("Backups Index", settings.backupsIndexPath)
                pathRow("App-Managed CLI", settings.appManagedCLIPath)
                if let currentBundledCLIPath = model.currentBundledCLIPath {
                    pathRow("Bundled CLI", currentBundledCLIPath)
                } else {
                    settingsRow("Bundled CLI", "This app bundle does not currently include an embedded CLI binary.")
                }
                pathRow("Primary Lock", settings.processLockPath)
                pathRow("Fallback Lock", settings.fallbackProcessLockPath)
                pathRow("Debug Log", settings.debugLogPath)
            }
        }
    }

    private func cliSection(_ settings: BearAppSettingsSnapshot) -> some View {
        GroupBox("CLI Setup") {
            VStack(alignment: .leading, spacing: 12) {
                settingsRow("Host-Facing CLI Path", settings.appManagedCLIPath)

                Text("MCP hosts should point at the app-managed CLI path above. `Bear MCP.app` owns installing and refreshing that copy so users do not have to chase SwiftPM build outputs or independent CLI installs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let currentBundledCLIPath = model.currentBundledCLIPath {
                    Text("This app currently bundles `\(currentBundledCLIPath)` and can expose it to the stable host-facing path.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This app build is missing the bundled CLI, so install/refresh cannot run until the app is rebuilt with the embedded binary.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 10) {
                    Button("Install or Refresh CLI") {
                        model.installBundledCLI()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.currentBundledCLIPath == nil)

                    Button("Copy CLI Path") {
                        model.copyInstalledCLIPath()
                    }
                    .buttonStyle(.bordered)

                    Button("Reveal CLI Folder") {
                        model.reveal(path: settings.appManagedCLIPath)
                    }
                    .buttonStyle(.bordered)
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

    private func hostAppsSection(_ settings: BearAppSettingsSnapshot) -> some View {
        GroupBox("Host Apps") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Use these guided checks and snippets to keep host apps pointed at the stable app-managed CLI path instead of a repo-local `.build` binary.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(settings.hostAppSetups) { setup in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(setup.appName)
                                .font(.headline)
                            Spacer(minLength: 12)
                            Text(setup.statusTitle)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(statusColor(for: setup.status).opacity(0.14))
                                .foregroundStyle(statusColor(for: setup.status))
                                .clipShape(Capsule())
                        }

                        if let configPath = setup.configPath {
                            settingsRow("Config Path", configPath)
                        }

                        Text(setup.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)

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

                            if setup.configPath != nil {
                                Button("Copy Config Path") {
                                    model.copyHostConfigPath(setup)
                                }
                                .buttonStyle(.bordered)

                                Button("Reveal Config") {
                                    if let configPath = setup.configPath {
                                        model.reveal(path: configPath)
                                    }
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
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        if !setup.checks.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Guided Checks")
                                    .font(.headline)

                                ForEach(setup.checks, id: \.self) { check in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checklist")
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private func configSection(_ settings: BearAppSettingsSnapshot) -> some View {
        GroupBox("Live Configuration") {
            VStack(alignment: .leading, spacing: 10) {
                settingsRow("Active Tags", settings.activeTags.isEmpty ? "None" : settings.activeTags.joined(separator: ", "))
                settingsRow("Default Insert Position", settings.defaultInsertPosition)
                settingsRow("Tags Merge Mode", settings.tagsMergeMode)
                settingsRow("Template Management", settings.templateManagementEnabled ? "Enabled" : "Disabled")
                settingsRow("Open in Edit Mode by Default", yesNo(settings.openNoteInEditModeByDefault))
                settingsRow("Create Opens Note by Default", yesNo(settings.createOpensNoteByDefault))
                settingsRow("Open Uses New Window by Default", yesNo(settings.openUsesNewWindowByDefault))
                settingsRow("Create Adds Active Tags by Default", yesNo(settings.createAddsActiveTagsByDefault))
                settingsRow("Selected-Note Token", settings.selectedNoteTokenStorageDescription)
                settingsRow("Discovery Limit", "\(settings.defaultDiscoveryLimit) default / \(settings.maxDiscoveryLimit) max")
                settingsRow("Snippet Length", "\(settings.defaultSnippetLength) default / \(settings.maxSnippetLength) max")
                settingsRow("Backup Retention", "\(settings.backupRetentionDays) days")
            }
        }
    }

    private func tokenSection(_ settings: BearAppSettingsSnapshot) -> some View {
        GroupBox("Bear Token") {
            VStack(alignment: .leading, spacing: 12) {
                settingsRow("Current Status", settings.selectedNoteTokenStorageDescription)

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
                                if model.revealsStoredToken {
                                    Text(displayedToken)
                                        .font(.body.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                } else {
                                    Text(displayedToken)
                                        .font(.body.monospaced())
                                        .foregroundStyle(.secondary)
                                }

                                Button(model.revealsStoredToken ? "Hide" : "Show", systemImage: model.revealsStoredToken ? "eye.slash" : "eye") {
                                    model.revealsStoredToken.toggle()
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Text("Not loaded during normal app use. Reveal only when you intentionally want to read the secret from Keychain.")
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

                Text("Save stores the token in macOS Keychain, so users do not need to open Keychain Access or keep the secret in config.json.")
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

    private func notesSection(_ settings: BearAppSettingsSnapshot) -> some View {
        GroupBox("Product Direction") {
            Text("`Bear MCP.app` should be the one true install and setup surface. It owns token management, diagnostics, and now the stable CLI path at `\(settings.appManagedCLIPath)` so MCP users do not have to think in terms of a separate standalone CLI product.")
                .foregroundStyle(.secondary)
        }
    }

    private func pathRow(_ label: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                Button("Reveal") {
                    model.reveal(path: path)
                }
                .buttonStyle(.link)
            }
            Text(path)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func settingsRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.headline)
            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
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
}
