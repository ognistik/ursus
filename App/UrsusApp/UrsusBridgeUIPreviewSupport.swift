#if DEBUG
import BearApplication
import BearCore
import SwiftUI

enum UrsusBridgeUIPreviewScenario: String, CaseIterable {
    case notInstalledNoClients
    case notInstalledWithRememberedClient
    case installedNoClients
    case installedSingleClient
    case installedMultipleClients
    case overlayMultipleClients
}

// Change this one line while developing to preview a different bridge state in Xcode canvas.
private let ursusBridgePreviewScenarioSelection: UrsusBridgeUIPreviewScenario = .overlayMultipleClients

struct UrsusBridgeUIPreviewState {
    let dashboard: BearAppDashboardSnapshot
    let bridgeAuthReview: BearBridgeAuthReviewSnapshot?
    let showsBridgeAccessOverlay: Bool
}

enum UrsusBridgeUIPreviewFactory {
    static func make(_ scenario: UrsusBridgeUIPreviewScenario) -> UrsusBridgeUIPreviewState {
        let now = Date()
        let singleGrant = grant(
            id: "grant-preview-1",
            clientID: "chatgpt-preview",
            clientDisplayName: "ChatGPT",
            resource: "https://chatgpt.com",
            createdAt: now.addingTimeInterval(-86_400 * 5)
        )
        let multipleGrants = [
            singleGrant,
            grant(
                id: "grant-preview-2",
                clientID: "claude-preview",
                clientDisplayName: "Claude Desktop",
                resource: "https://claude.ai",
                createdAt: now.addingTimeInterval(-86_400 * 2)
            ),
            grant(
                id: "grant-preview-3",
                clientID: "codex-preview",
                clientDisplayName: "Codex",
                resource: nil,
                createdAt: now.addingTimeInterval(-86_400)
            ),
        ]

        let grants: [BearBridgeAuthGrantSummary]
        let installed: Bool
        let loaded: Bool
        let authMode: BearBridgeAuthMode
        let overlayVisible: Bool

        switch scenario {
        case .notInstalledNoClients:
            grants = []
            installed = false
            loaded = false
            authMode = .oauth
            overlayVisible = false
        case .notInstalledWithRememberedClient:
            grants = [singleGrant]
            installed = false
            loaded = false
            authMode = .open
            overlayVisible = false
        case .installedNoClients:
            grants = []
            installed = true
            loaded = true
            authMode = .oauth
            overlayVisible = false
        case .installedSingleClient:
            grants = [singleGrant]
            installed = true
            loaded = true
            authMode = .oauth
            overlayVisible = false
        case .installedMultipleClients:
            grants = multipleGrants
            installed = true
            loaded = true
            authMode = .oauth
            overlayVisible = false
        case .overlayMultipleClients:
            grants = multipleGrants
            installed = true
            loaded = true
            authMode = .oauth
            overlayVisible = true
        }

        let bridgeAuthSnapshot = BearBridgeAuthStoreSnapshot(
            storagePath: "/Users/preview/Library/Application Support/Ursus/Auth/bridge-auth.sqlite",
            storageReady: installed || !grants.isEmpty,
            registeredClientCount: max(grants.count, grants.isEmpty ? 0 : 1),
            activeGrantCount: grants.count,
            pendingAuthorizationRequestCount: 0,
            activeAuthorizationCodeCount: 0,
            activeRefreshTokenCount: grants.isEmpty ? 0 : grants.count,
            activeAccessTokenCount: grants.isEmpty ? 0 : grants.count,
            revocationCount: 0
        )

        let bridgeSnapshot = BearAppBridgeSnapshot(
            enabled: true,
            host: BearBridgeConfiguration.defaultHost,
            port: BearBridgeConfiguration.preferredPort,
            authMode: authMode,
            auth: bridgeAuthSnapshot,
            endpointURL: "http://127.0.0.1:6190/mcp",
            currentSelectedNoteTokenConfigured: false,
            loadedSelectedNoteTokenConfigured: installed ? false : nil,
            currentRuntimeConfigurationGeneration: 1,
            loadedRuntimeConfigurationGeneration: installed ? 1 : nil,
            currentRuntimeConfigurationFingerprint: "preview-config",
            loadedRuntimeConfigurationFingerprint: installed ? "preview-config" : nil,
            currentBridgeSurfaceMarker: "preview-surface",
            loadedBridgeSurfaceMarker: installed ? "preview-surface" : nil,
            launcherPath: "/Users/preview/.local/bin/ursus",
            launchAgentLabel: "com.aft.ursus",
            plistPath: "/Users/preview/Library/LaunchAgents/com.aft.ursus.plist",
            standardOutputLogPath: "/Users/preview/Library/Application Support/Ursus/Logs/bridge.stdout.log",
            standardErrorLogPath: "/Users/preview/Library/Application Support/Ursus/Logs/bridge.stderr.log",
            installed: installed,
            loaded: loaded,
            plistMatchesExpected: installed,
            endpointTransportReachable: installed,
            endpointProtocolCompatible: installed,
            endpointProbeDetail: installed ? nil : "Install the bridge to start serving requests.",
            status: installed ? .ok : .missing,
            statusTitle: installed ? "Running" : "Not Installed",
            statusDetail: installed ? "Serving local MCP requests." : "Install the bridge to get a local MCP URL."
        )

        let settings = BearAppSettingsSnapshot(
            configDirectoryPath: "/Users/preview/Library/Application Support/Ursus",
            configFilePath: "/Users/preview/Library/Application Support/Ursus/config.json",
            templatePath: "/Users/preview/Library/Application Support/Ursus/template.md",
            backupsDirectoryPath: "/Users/preview/Library/Application Support/Ursus/Backups",
            backupsMetadataPath: "/Users/preview/Library/Application Support/Ursus/backups.sqlite",
            launcherPath: "/Users/preview/.local/bin/ursus",
            launcherStatus: .ok,
            launcherStatusTitle: "Ready",
            launcherStatusDetail: "Launcher is installed.",
            processLockPath: "/Users/preview/Library/Application Support/Ursus/Runtime/ursus.lock",
            fallbackProcessLockPath: "/tmp/ursus/Runtime/ursus.lock",
            debugLogPath: "/Users/preview/Library/Application Support/Ursus/Logs/debug.log",
            runtimeConfigurationGeneration: 1,
            cliMaintenancePrompt: nil,
            inboxTags: ["0-inbox"],
            defaultInsertPosition: BearConfiguration.InsertDefault.bottom.rawValue,
            templateManagementEnabled: true,
            createOpensNoteByDefault: true,
            openUsesNewWindowByDefault: true,
            createAddsInboxTagsByDefault: true,
            tagsMergeMode: BearConfiguration.TagsMergeMode.append.rawValue,
            defaultDiscoveryLimit: 20,
            defaultSnippetLength: 280,
            backupRetentionDays: 30,
            disabledTools: [],
            selectedNoteTokenConfigured: true,
            selectedNoteTokenStorageDescription: "Stored in macOS Keychain",
            selectedNoteTokenStatusDetail: nil,
            bridge: bridgeSnapshot,
            toolToggles: [],
            hostAppSetups: []
        )

        let review = BearBridgeAuthReviewSnapshot(
            storagePath: bridgeAuthSnapshot.storagePath,
            storageReady: bridgeAuthSnapshot.storageReady,
            pendingRequests: [],
            activeGrants: grants
        )

        return UrsusBridgeUIPreviewState(
            dashboard: BearAppDashboardSnapshot(
                generatedAt: now,
                diagnostics: [],
                settings: settings,
                settingsError: nil
            ),
            bridgeAuthReview: review,
            showsBridgeAccessOverlay: overlayVisible
        )
    }

    private static func grant(
        id: String,
        clientID: String,
        clientDisplayName: String?,
        resource: String?,
        createdAt: Date
    ) -> BearBridgeAuthGrantSummary {
        BearBridgeAuthGrantSummary(
            id: id,
            clientID: clientID,
            clientDisplayName: clientDisplayName,
            scope: "bear:notes",
            resource: resource,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}

#Preview("Bridge UI") {
    UrsusSetupView(
        model: UrsusAppModel(previewState: UrsusBridgeUIPreviewFactory.make(ursusBridgePreviewScenarioSelection)),
        selectedSection: .constant(.setup)
    )
}
#endif
