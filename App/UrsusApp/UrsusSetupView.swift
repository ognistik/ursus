import BearApplication
import BearCore
import SwiftUI

struct UrsusSetupView: View {
    @ObservedObject var model: UrsusAppModel
    @Binding var selectedSection: UrsusDashboardSection
    @State private var showsTokenInput = false
    @State private var isSupportAffordanceHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            UrsusScrollSurface {
                if let settings = model.dashboard.settings {
                    VStack(alignment: .leading, spacing: 20) {
                        heroPanel
                        Divider()
                        defaultsPanel(settings)
                        Divider()
                        tokenPanel(settings)
                        Divider()
                        connectAppsPanel()
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
            .allowsHitTesting(!model.showsBridgeAccessOverlay)

            ZStack {
                (colorScheme == .dark
                 ? Color.black.opacity(0.50)
                 : Color.black.opacity(0.26))
            }
            .ignoresSafeArea()
            .opacity(model.showsBridgeAccessOverlay ? 1 : 0)
            .allowsHitTesting(model.showsBridgeAccessOverlay)
            .accessibilityHidden(!model.showsBridgeAccessOverlay)
            .animation(.easeInOut(duration: 0.18), value: model.showsBridgeAccessOverlay)
            .onTapGesture {
                model.closeBridgeAccessOverlay()
            }

            UrsusBridgeAccessOverlay(model: model)
                .padding(.horizontal, 32)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(model.showsBridgeAccessOverlay ? 1 : 0)
                .offset(y: model.showsBridgeAccessOverlay ? 0 : 28)
                .disabled(!model.showsBridgeAccessOverlay)
                .allowsHitTesting(model.showsBridgeAccessOverlay)
                .accessibilityHidden(!model.showsBridgeAccessOverlay)
                .animation(.easeInOut(duration: 0.18), value: model.showsBridgeAccessOverlay)
        }
        .task {
            await model.preloadBridgeAccessOverlayIfNeeded()
        }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image("UrsusLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)

                Text("Ursus")
                    .font(.custom("Montserrat-Bold", size: 34))
                    .tracking(0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Local MCP and utilities for Bear")

                if model.showsSupportAffordance {
                    Text("·")

                    Button {
                        model.presentDonationPrompt()
                    } label: {
                        Text("Support Ursus")
                    }
                    .buttonStyle(UrsusSubtitleLinkButtonStyle(isHovered: isSupportAffordanceHovered))
                    .onHover { isHovered in
                        isSupportAffordanceHovered = isHovered
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(ursusTertiaryTextColor)
            .padding(.leading, 1)
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
                .foregroundStyle(ursusInlineLabelColor)
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
            titleHelpText: "Token is safely stored in macOS Keychain."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Optional. Required for selected-note flows.")
                    .font(.footnote)
                    .foregroundStyle(ursusTertiaryTextColor)

                if settings.selectedNoteTokenConfigured && !showsTokenInput {
                    UrsusGroupedBlock {
                        if let displayedToken = model.revealsStoredToken ? model.storedSelectedNoteToken : model.maskedStoredSelectedNoteToken {
                            HStack(spacing: 10) {
                                Text(displayedToken)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(ursusSecondaryTextColor)
                                    .textSelection(.enabled)

                                Spacer(minLength: 12)

                                Button {
                                    model.loadStoredSelectedNoteToken()
                                } label: {
                                    Image(systemName: model.revealsStoredToken ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.plain)
                                .controlSize(.small)
                                .foregroundStyle(ursusInlineLabelColor)
                                .help(model.revealsStoredToken ? "Hide Token" : "Reveal Token")

                                Button {
                                    model.copySelectedNoteToken()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .controlSize(.small)
                                .foregroundStyle(ursusInlineLabelColor)
                                .help("Copy Token")
                            }
                        } else {
                            HStack(spacing: 10) {
                                Text("Saved token unavailable in the app.")
                                    .font(.footnote)
                                    .foregroundStyle(ursusTertiaryTextColor)

                                Button("Try Again") {
                                    model.loadStoredSelectedNoteToken()
                                }
                                .ursusButtonStyle()
                                .controlSize(.small)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Replace") {
                            showsTokenInput = true
                        }
                        .ursusButtonStyle()

                        Button("Remove", role: .destructive) {
                            model.removeSelectedNoteToken()
                            showsTokenInput = false
                        }
                        .ursusButtonStyle(.destructive)
                    }
                } else {
                    UrsusGroupedBlock {
                        SecureField(
                            settings.selectedNoteTokenConfigured
                                ? "Paste a new Bear API token"
                                : "Paste Bear API token",
                            text: $model.tokenDraft
                        )
                        .textFieldStyle(.plain)
                        .ursusInputChrome()
                    }

                    HStack(spacing: 10) {
                        Button("Save Token") {
                            model.saveSelectedNoteToken()
                            showsTokenInput = false
                        }
                        .ursusButtonStyle()

                        if showsTokenInput {
                            Button("Cancel") {
                                model.tokenDraft = ""
                                showsTokenInput = false
                            }
                            .ursusButtonStyle()
                        }
                    }
                }

                UrsusMessageStack(error: model.tokenStatusError)
            }
        }
    }

    private func connectAppsPanel() -> some View {
        let supportedSetups = model.setupHostSetups

        return UrsusPanel(
            title: "Connect Apps"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if supportedSetups.isEmpty {
                    Text("For third-party AI apps that support local MCP servers, add Ursus as a stdio MCP server using the copied launcher path as the command and \"mcp\" as an argument. Use the Remote MCP Bridge below when an app supports a local MCP URL instead.")
                        .font(.footnote)
                        .foregroundStyle(ursusTertiaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Copy Launcher Path") {
                        model.copyLauncherPath()
                    }
                    .ursusButtonStyle()

                    UrsusMessageStack(error: model.cliStatusError)
                } else {
                    Text("Supported apps found on this Mac are shown below. Other clients can still connect manually using the Ursus launcher path or the Remote MCP Bridge.")
                        .font(.footnote)
                        .foregroundStyle(ursusTertiaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !supportedSetups.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(supportedSetups, id: \.id) { setup in
                            UrsusGroupedBlock {
                                UrsusHostSetupRow(model: model, setup: setup)
                            }
                        }
                    }
                }

                UrsusMessageStack(error: model.hostSetupStatusError)
            }
        }
    }

    private func bridgePanel(_ settings: BearAppSettingsSnapshot) -> some View {
        let bridge = settings.bridge

        if let badge = bridgeBadge(for: settings) {
            return AnyView(
                UrsusPanel(
                    title: "Remote MCP Bridge",
                    titleHelpText: "Use this when an app supports a local MCP URL instead of launching Ursus directly.",
                    headerAccessory: {
                        UrsusStatusBadge(title: badge.title, status: badge.status)
                    }
                ) {
                    bridgePanelBody(settings, bridge: bridge)
                }
            )
        }

        return AnyView(
            UrsusPanel(
                title: "Remote MCP Bridge",
                titleHelpText: "Use this when an app supports a local MCP URL instead of launching Ursus directly."
            ) {
                bridgePanelBody(settings, bridge: bridge)
            }
        )
    }

    @ViewBuilder
    private func bridgePanelBody(_ settings: BearAppSettingsSnapshot, bridge: BearAppBridgeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            bridgeStatusSummary(for: settings)

            UrsusGroupedBlock {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("MCP URL")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(ursusInlineLabelColor)

                    Spacer(minLength: 12)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(bridge.endpointURL)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(ursusSecondaryTextColor)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)

                        Button {
                            model.copyBridgeURL()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ursusInlineLabelColor)
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
                        showsHelpButton: false,
                        fieldWidth: 92
                    )
                    configurationValidationMessages(for: .bridgePort)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    bridgeAuthorizationRow(for: bridge)

                    if bridge.installed, let bridgeAccessSummary = bridgeAccessSummary(for: bridge) {
                        Text(bridgeAccessSummary)
                            .font(.footnote)
                            .foregroundStyle(ursusTertiaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 10) {
                if let installAction = bridgeInstallAction(for: settings) {
                    Button(installAction.title) {
                        performBridgeInstallAction(installAction, settings: settings)
                    }
                    .ursusButtonStyle(bridgeInstallButtonRole(for: settings, action: installAction))
                    .disabled(model.currentBundledCLIPath == nil || model.isBridgeOperationInProgress)
                }

                if let lifecycleAction = bridgeLifecycleAction(for: settings) {
                    Button(lifecycleAction.title) {
                        performBridgeLifecycleAction(lifecycleAction)
                    }
                    .ursusButtonStyle(lifecycleAction.buttonRole)
                    .disabled(model.isBridgeOperationInProgress)
                }

                if bridgeRememberedClientCount(for: bridge) > 0 {
                    Button("Manage Access") {
                        model.openBridgeAccessOverlay()
                    }
                    .ursusButtonStyle(.secondary)
                    .disabled(model.isBridgeOperationInProgress)
                }

                if bridge.installed {
                    Button("Remove", role: .destructive) {
                        model.removeBridge()
                    }
                    .ursusButtonStyle(.destructive)
                    .disabled(model.isBridgeOperationInProgress)
                }
            }

            UrsusMessageStack(error: model.bridgeStatusError)
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

    private var bridgeRequiresOAuthBinding: Binding<Bool> {
        Binding(
            get: { model.bridgeRequiresOAuthDraft },
            set: {
                model.bridgeRequiresOAuthDraft = $0
                model.configurationDraftDidChange()
            }
        )
    }

    @ViewBuilder
    private func bridgeAuthorizationRow(for bridge: BearAppBridgeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                Text("Authorization")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(ursusInlineLabelColor)

                Spacer(minLength: 12)

                if bridge.installed {
                    Text(bridge.authModeSummary)
                        .font(.callout)
                        .foregroundStyle(ursusSecondaryTextColor)
                        .multilineTextAlignment(.trailing)
                } else {
                    Toggle("", isOn: bridgeRequiresOAuthBinding)
                        .toggleStyle(.switch)
                        .tint(ursusToggleTrackTint)
                        .labelsHidden()
                        .disabled(model.isBridgeOperationInProgress)
                }
            }

            if !bridge.installed {
                Text("Require OAuth for all bridge requests")
                    .font(.footnote)
                    .foregroundStyle(ursusTertiaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bridgeRememberedClientCount(for bridge: BearAppBridgeSnapshot) -> Int {
        if model.bridgeAuthReview != nil {
            return model.bridgeRememberedClientCount
        }

        return bridge.auth.activeGrantCount
    }

    private func bridgeAccessSummary(for bridge: BearAppBridgeSnapshot) -> String? {
        switch bridgeRememberedClientCount(for: bridge) {
        case 0:
            return nil
        case 1:
            return "1 remembered client"
        default:
            return "\(bridgeRememberedClientCount(for: bridge)) remembered clients"
        }
    }

    private func bridgeStateText(for settings: BearAppSettingsSnapshot) -> String? {
        let bridge = settings.bridge

        if bridge.restartRequired {
            return "Installed and serving requests, but recent changes will not apply until restart."
        }

        if bridge.loaded, (bridge.status == .ok || bridge.status == .configured) {
            if bridge.requiresOAuth {
                return "Installed and serving requests at the local MCP URL below. OAuth is required for every bridge request."
            }
            return "Installed and serving requests at the local MCP URL below."
        }

        switch bridge.status {
        case .missing:
            return "Install the bridge to get a local MCP URL."
        case .notConfigured:
            return bridge.installed ? "Installed, but not serving requests." : "Install the bridge to get a local MCP URL."
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

    @ViewBuilder
    private func bridgeStatusSummary(for settings: BearAppSettingsSnapshot) -> some View {
        if let bridgeStateText = bridgeStateText(for: settings) {
            Text(bridgeStateText)
                .font(.footnote)
                .foregroundStyle(ursusTertiaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
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

    private func performBridgeInstallAction(
        _ action: UrsusBridgeInstallAction,
        settings: BearAppSettingsSnapshot
    ) {
        switch action {
        case .installBridge:
            model.installBridge()
        case .installLauncher, .repairLauncher, .repairBridge:
            performRecoveryAction(action.recoveryAction, settings: settings)
        }
    }

    private func performBridgeLifecycleAction(_ action: UrsusBridgeLifecycleAction) {
        switch action {
        case .pause:
            model.pauseBridge()
        case .restart:
            model.restartBridge()
        case .resume:
            model.resumeBridge()
        }
    }

}

private struct UrsusSubtitleLinkButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered ? ursusSecondaryTextColor : ursusTertiaryTextColor.opacity(0.52))
            .opacity(configuration.isPressed ? 0.70 : 1)
    }
}

private enum UrsusRecoveryAction {
    case installLauncher
    case repairLauncher
    case repairBridge
}

private struct UrsusHostSetupRow: View {
    @ObservedObject var model: UrsusAppModel
    let setup: BearHostAppSetupSnapshot

    private var showsInstalledState: Bool {
        setup.integrationState == .installed
    }

    private var primaryActionTitle: String? {
        setup.primaryAction?.title
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(setup.appName)
                .font(.callout.weight(.medium))

            Spacer(minLength: 12)

            if let badgeStatus = hostSetupBadgeStatus(for: setup.status) {
                UrsusStatusBadge(title: compactStatusTitle(for: badgeStatus), status: badgeStatus)
            }

            if showsInstalledState {
                UrsusInstalledIndicator()
            }

            if let primaryActionTitle {
                Button(primaryActionTitle) {
                    model.installHostAppIntegration(setup)
                }
                .ursusButtonStyle(primaryActionTitle == "Repair" ? .softPrimary : .secondary)
                .disabled(model.currentBundledCLIPath == nil)
            }

            Menu {
                if let configPath = setup.configPath {
                    Button("Reveal Config") {
                        model.reveal(path: configPath)
                    }
                }

                if setup.snippet != nil {
                    Button("Copy Setup") {
                        model.copyHostSetupSnippet(setup)
                    }
                }

                if setup.managedByUrsus {
                    Divider()

                    Button("Remove from \(setup.appName)", role: .destructive) {
                        model.removeHostAppIntegration(setup)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ursusInlineLabelColor)
            }
            .menuStyle(.borderlessButton)
            .help("More")
        }
    }
}

private struct UrsusInstalledIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            UrsusConfiguredMark()

            Text("Installed")
                .font(.caption)
                .foregroundStyle(ursusTertiaryTextColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Installed")
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

private enum UrsusBridgeInstallAction {
    case installBridge
    case installLauncher
    case repairLauncher
    case repairBridge

    init(recoveryAction: UrsusRecoveryAction) {
        switch recoveryAction {
        case .installLauncher:
            self = .installLauncher
        case .repairLauncher:
            self = .repairLauncher
        case .repairBridge:
            self = .repairBridge
        }
    }

    var title: String {
        switch self {
        case .installBridge:
            return "Install Bridge"
        case .installLauncher:
            return "Install Launcher"
        case .repairLauncher:
            return "Repair Launcher"
        case .repairBridge:
            return "Repair"
        }
    }

    var recoveryAction: UrsusRecoveryAction {
        switch self {
        case .installBridge:
            preconditionFailure("Install bridge does not map to a recovery action.")
        case .installLauncher:
            return .installLauncher
        case .repairLauncher:
            return .repairLauncher
        case .repairBridge:
            return .repairBridge
        }
    }
}

private enum UrsusBridgeLifecycleAction {
    case pause
    case restart
    case resume

    var title: String {
        switch self {
        case .pause:
            return "Pause"
        case .restart:
            return "Restart"
        case .resume:
            return "Resume"
        }
    }

    var buttonRole: UrsusButtonRole {
        switch self {
        case .restart:
            return .softPrimary
        case .pause:
            return .secondary
        case .resume:
            return .secondary
        }
    }
}

private func bridgeInstallAction(for settings: BearAppSettingsSnapshot) -> UrsusBridgeInstallAction? {
    if let recoveryAction = bridgeRecoveryAction(for: settings) {
        return UrsusBridgeInstallAction(recoveryAction: recoveryAction)
    }

    return settings.bridge.installed ? nil : .installBridge
}

private func bridgeInstallButtonRole(
    for settings: BearAppSettingsSnapshot,
    action: UrsusBridgeInstallAction
) -> UrsusButtonRole {
    switch action {
    case .installBridge:
        return .secondary
    case .repairBridge:
        return .softPrimary
    case .installLauncher, .repairLauncher:
        return settings.bridge.installed ? .secondary : .primary
    }
}

private func bridgeLifecycleAction(for settings: BearAppSettingsSnapshot) -> UrsusBridgeLifecycleAction? {
    let bridge = settings.bridge

    guard bridge.installed, bridgeRecoveryAction(for: settings) == nil else {
        return nil
    }

    if bridge.loaded {
        return bridge.restartRequired ? .restart : .pause
    }

    return .resume
}

private func friendlyInsertPosition(_ rawValue: String) -> String {
    switch rawValue {
    case BearConfiguration.InsertDefault.top.rawValue:
        return "Top"
    default:
        return "Bottom"
    }
}

private func bridgeBadge(for settings: BearAppSettingsSnapshot) -> (title: String, status: BearDoctorCheckStatus)? {
    let bridge = settings.bridge

    if bridge.restartRequired {
        return ("Restart Required", .notConfigured)
    }

    switch bridge.status {
    case .notConfigured where bridge.installed:
        return ("Paused", .notConfigured)
    case .invalid, .failed:
        return (compactStatusTitle(for: bridge.status), bridge.status)
    case .ok, .configured, .missing, .notConfigured:
        return nil
    }
}

private func hostSetupBadgeStatus(for status: BearDoctorCheckStatus) -> BearDoctorCheckStatus? {
    switch status {
    case .invalid, .failed:
        return status
    case .ok, .configured, .missing, .notConfigured:
        return nil
    }
}
