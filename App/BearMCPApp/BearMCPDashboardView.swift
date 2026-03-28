import BearApplication
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
                    Text("`bearmcp://` is now wired for the Phase 3 selected-note callback flow. During verification, the legacy helper remains available as a fallback path.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("`bearmcp://` is registered on the app bundle and can now host the selected-note callback flow in a hidden app launch. The legacy helper is retained only as a low-risk fallback during verification.")
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
                    tokenSection(settings)
                    configSection(settings)
                    notesSection
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
                pathRow("Primary Lock", settings.processLockPath)
                pathRow("Fallback Lock", settings.fallbackProcessLockPath)
                pathRow("Debug Log", settings.debugLogPath)
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

                if settings.selectedNoteTokenConfigured, let displayedToken = model.revealsStoredToken ? model.storedSelectedNoteToken : model.maskedStoredSelectedNoteToken {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stored Token")
                            .font(.headline)

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

    private var notesSection: some View {
        GroupBox("Phase 4 Direction") {
            Text("`Bear MCP.app` is becoming the friendly place to manage the Bear API token. The CLI still runs headlessly, but token entry, import, update, and removal should happen here instead of in Keychain Access or plaintext config.")
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
}
