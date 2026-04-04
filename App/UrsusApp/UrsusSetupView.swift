import BearApplication
import BearCore
import SwiftUI

struct UrsusSetupView: View {
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
            titleAccessory: {
                Button {
                    selectedSection = .preferences
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Edit")
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                UrsusInfoRow(
                    label: "Template management",
                    value: settings.templateManagementEnabled ? "On" : "Off",
                    compact: true
                )
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
        UrsusPanel(
            title: "Bear Token",
            titleHelpText: "Token is safely stored in macOS Keychain.",
            headerAccessory: {
                if settings.selectedNoteTokenConfigured {
                    UrsusStatusBadge(title: "Saved", status: .configured)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Optional. Required for selected-note flows.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)

                if settings.selectedNoteTokenConfigured && !showsTokenInput {
                    UrsusGroupedBlock {
                        if let displayedToken = model.revealsStoredToken ? model.storedSelectedNoteToken : model.maskedStoredSelectedNoteToken {
                            HStack(spacing: 10) {
                                Text(displayedToken)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)

                                Spacer(minLength: 12)

                                Button {
                                    model.loadStoredSelectedNoteToken()
                                } label: {
                                    Image(systemName: model.revealsStoredToken ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.plain)
                                .controlSize(.small)
                                .foregroundStyle(.secondary)
                                .help(model.revealsStoredToken ? "Hide Token" : "Reveal Token")

                                Button {
                                    model.copySelectedNoteToken()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .controlSize(.small)
                                .foregroundStyle(.secondary)
                                .help("Copy Token")
                            }
                        } else {
                            HStack(spacing: 10) {
                                Text("Saved token unavailable in the app.")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)

                                Button("Try Again") {
                                    model.loadStoredSelectedNoteToken()
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                            }
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
                    UrsusGroupedBlock {
                        SecureField(
                            settings.selectedNoteTokenConfigured
                                ? "Paste a new Bear API token"
                                : "Paste Bear API token",
                            text: $model.tokenDraft
                        )
                        .textFieldStyle(.roundedBorder)
                    }

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
            VStack(alignment: .leading, spacing: 14) {
                if let title = launcherPrimaryActionTitle(for: settings) {
                    UrsusGroupedBlock {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("Install the launcher before copying setup.")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)

                            Spacer(minLength: 12)

                            Button(title) {
                                model.installPublicLauncher()
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.currentBundledCLIPath == nil)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.setupHostSetups, id: \.id) { setup in
                        UrsusGroupedBlock {
                            UrsusHostSetupRow(model: model, setup: setup)
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

    private func bridgePanel(_ settings: BearAppSettingsSnapshot) -> some View {
        let bridge = settings.bridge

        return UrsusPanel(
            title: "Remote MCP Bridge",
            titleHelpText: "Use this when an app needs a local MCP URL instead of launching Ursus directly.",
            headerAccessory: {
                UrsusStatusBadge(title: bridgeStatusTitle(for: bridge), status: bridge.status)
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let bridgeStateText = bridgeStateText(for: settings) {
                    Text(bridgeStateText)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }

                UrsusGroupedBlock {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("MCP URL")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 12)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(bridge.endpointURL)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)

                            Button {
                                model.copyBridgeURL()
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Copy URL")
                        }
                    }

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
                }

                if let progressMessage = model.bridgeOperationProgressMessage {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text(progressMessage)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
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
        case .repairBridge:
            model.installBridge(repairing: settings.bridge.status == .invalid || settings.bridge.status == .failed)
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

private enum UrsusRecoveryAction {
    case installLauncher
    case repairLauncher
    case repairBridge

    var title: String {
        switch self {
        case .installLauncher:
            return "Install Launcher"
        case .repairLauncher:
            return "Repair Launcher"
        case .repairBridge:
            return "Repair Bridge"
        }
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

private func bridgeStatusTitle(for bridge: BearAppBridgeSnapshot) -> String {
    if bridge.installed, bridge.status == .notConfigured {
        return "Paused"
    }

    return compactStatusTitle(for: bridge.status)
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
